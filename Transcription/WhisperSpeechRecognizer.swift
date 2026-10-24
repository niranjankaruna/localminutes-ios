import Foundation
import CryptoKit
import Dispatch
import Synchronization
import whisper

public struct WhisperSpeechModelFiles: Equatable, Sendable {
    public let model: URL
    public let revision: String
    public let byteCount: Int64
    public let sha256: String
    public init(model: URL, revision: String, byteCount: Int64, sha256: String) {
        self.model = model; self.revision = revision; self.byteCount = byteCount; self.sha256 = sha256
    }
}

public struct WhisperSpeechSegment: Equatable, Sendable {
    public let id: UUID
    public let startSample: Int64
    public let endSample: Int64
    public let text: String
    public init(id: UUID, startSample: Int64, endSample: Int64, text: String) {
        self.id = id; self.startSample = startSample; self.endSample = endSample; self.text = text
    }
}

public struct WhisperSpeechUpdate: Equatable, Sendable {
    public let epochID: UUID
    public let partial: String
    /// Newly finalized segments only; finish replay must not emit them twice.
    public let finalized: [WhisperSpeechSegment]
    public init(epochID: UUID, partial: String, finalized: [WhisperSpeechSegment]) {
        self.epochID = epochID; self.partial = partial; self.finalized = finalized
    }
}

public struct WhisperSpeechSnapshot: Equatable, Sendable {
    public let phase: StreamingASRPhase
    public let epochID: UUID?
    public let provider: StreamingASRProvider?
    public let acceptedSampleCount: Int64
    public let bufferedSampleCount: Int
    public init(phase: StreamingASRPhase, epochID: UUID?, provider: StreamingASRProvider?,
                acceptedSampleCount: Int64, bufferedSampleCount: Int) {
        self.phase = phase; self.epochID = epochID; self.provider = provider
        self.acceptedSampleCount = acceptedSampleCount; self.bufferedSampleCount = bufferedSampleCount
    }
}

enum WhisperNativeOperation: Equatable, Sendable { case load, decode }
typealias WhisperNativeExecutionObserver = @Sendable (WhisperNativeOperation, Bool, Bool) -> Void

/// CPU rolling-window inference on an owned serial worker. Capture supplies
/// bounded normalized PCM; finalized deltas retain native source-global ranges.
public actor WhisperSpeechRecognizer {
    public static let sampleRate = 16_000
    public static let stepSamples = 80_000
    public static let maximumWindowSamples = 480_000
    private nonisolated let workerExecutor = WhisperSerialExecutor()
    public nonisolated var unownedExecutor: UnownedSerialExecutor { workerExecutor.asUnownedSerialExecutor() }
    private nonisolated let cancellationRouter = WhisperCancellationRouter()
    private let files: WhisperSpeechModelFiles
    private let executionObserver: WhisperNativeExecutionObserver?
    private let native = WhisperNativeResources()
    private var phase: StreamingASRPhase = .unloaded
    private var epochID: UUID?
    private var cancellation = WhisperCancellation()
    private var pcm: [Float] = []
    private var windowStart: Int64 = 0
    private var acceptedSamples: Int64 = 0
    private var nextDecode: Int64 = 80_000
    private var committedThrough: Int64 = 0
    private var partial = ""

    public init(files: WhisperSpeechModelFiles) { self.files = files; executionObserver = nil }
    init(files: WhisperSpeechModelFiles, executionObserver: @escaping WhisperNativeExecutionObserver) {
        self.files = files; self.executionObserver = executionObserver
    }

    public func load() async throws {
        workerExecutor.assertCurrent()
        if native.context != nil { return }
        let flag = WhisperCancellation()
        cancellationRouter.select(nil, flag: flag)
        try await withTaskCancellationHandler {
            try validateModel(flag)
            _ = WhisperNativeBackend.initialized
            var parameters = whisper_context_default_params()
            parameters.use_gpu = false
            parameters.flash_attn = false
            parameters.dtw_token_timestamps = false
            observe(.load, gpu: parameters.use_gpu)
            guard let context = files.model.path.withCString({ whisper_init_from_file_with_params($0, parameters) }) else {
                throw StreamingASRError.nativeCreationFailed
            }
            if flag.isCancelled || Task.isCancelled {
                whisper_free(context)
                throw CancellationError()
            }
            native.context = context
            phase = .ready
        } onCancel: { flag.cancel() }
    }

    public func start(epochID: UUID) throws {
        workerExecutor.assertCurrent()
        try Task.checkCancellation()
        guard native.context != nil else { throw StreamingASRError.noActiveStream }
        guard phase != .streaming else { throw StreamingASRError.alreadyStarted }
        self.epochID = epochID
        phase = .streaming
        pcm = []; windowStart = 0; acceptedSamples = 0; nextDecode = 80_000; committedThrough = 0; partial = ""
        cancellation = WhisperCancellation()
        cancellationRouter.select(epochID, flag: cancellation)
    }

    public func accept(_ samples: [Float], at globalSampleOffset: Int64) async throws -> WhisperSpeechUpdate {
        workerExecutor.assertCurrent()
        let flag = cancellation
        return try await withTaskCancellationHandler {
            let epoch = try activeEpoch()
            try checkCancellation(flag)
            guard !samples.isEmpty, samples.count <= Self.stepSamples,
                  samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }),
                  acceptedSamples <= Int64.max - Int64(samples.count) else { throw StreamingASRError.invalidSamples }
            guard globalSampleOffset == acceptedSamples else {
                throw StreamingASRError.discontinuity(expected: acceptedSamples, actual: globalSampleOffset)
            }
            var offset = 0
            var finalized: [WhisperSpeechSegment] = []
            while offset < samples.count {
                try checkCancellation(flag)
                let capacity = Self.maximumWindowSamples - pcm.count
                if capacity == 0 { finalized += try decode(forceFinal: true, flag: flag); continue }
                let untilStep = Int(min(Int64(Self.stepSamples), nextDecode - acceptedSamples))
                let count = min(capacity, samples.count - offset, max(1, untilStep))
                pcm.append(contentsOf: samples[offset..<(offset + count)])
                offset += count; acceptedSamples += Int64(count)
                if acceptedSamples >= nextDecode || pcm.count == Self.maximumWindowSamples {
                    finalized += try decode(forceFinal: pcm.count == Self.maximumWindowSamples, flag: flag)
                    nextDecode = acceptedSamples <= Int64.max - 80_000 ? acceptedSamples + 80_000 : Int64.max
                }
            }
            return .init(epochID: epoch, partial: partial, finalized: finalized)
        } onCancel: { flag.cancel() }
    }

    public func finish() async throws -> WhisperSpeechUpdate {
        workerExecutor.assertCurrent()
        if phase == .finished, let epochID { return .init(epochID: epochID, partial: "", finalized: []) }
        let flag = cancellation
        return try await withTaskCancellationHandler {
            let epoch = try activeEpoch()
            try checkCancellation(flag)
            let finalized = try decode(forceFinal: true, flag: flag)
            phase = .finished
            partial = ""
            return .init(epochID: epoch, partial: "", finalized: finalized)
        } onCancel: { flag.cancel() }
    }

    public nonisolated func cancel(epochID: UUID) async {
        guard let flag = cancellationRouter.cancel(epochID) else { return }
        await cancelOnWorker(epochID: epochID, flag: flag)
    }

    private func cancelOnWorker(epochID: UUID, flag: WhisperCancellation) {
        workerExecutor.assertCurrent()
        guard self.epochID == epochID, cancellation === flag else { return }
        phase = .cancelled
        pcm = []; partial = ""; windowStart = acceptedSamples
    }

    public nonisolated func unload() async {
        cancellationRouter.cancelAll()
        await unloadOnWorker()
    }

    private func unloadOnWorker() {
        workerExecutor.assertCurrent()
        if let context = native.context { whisper_free(context); native.context = nil }
        cancellationRouter.select(nil, flag: nil)
        phase = .unloaded; epochID = nil; pcm = []; partial = ""
        acceptedSamples = 0; windowStart = 0; committedThrough = 0; nextDecode = 80_000
    }

    public func snapshot() -> WhisperSpeechSnapshot {
        .init(phase: phase, epochID: epochID, provider: native.context == nil ? nil : .cpu,
              acceptedSampleCount: acceptedSamples, bufferedSampleCount: pcm.count)
    }

    private func activeEpoch() throws -> UUID {
        if phase == .cancelled { throw StreamingASRError.cancelled }
        if phase == .finished { throw StreamingASRError.finished }
        guard phase == .streaming, let epochID, native.context != nil else { throw StreamingASRError.noActiveStream }
        return epochID
    }

    private func checkCancellation(_ flag: WhisperCancellation) throws {
        if flag.isCancelled || Task.isCancelled { throw CancellationError() }
    }

    private func decode(forceFinal: Bool, flag: WhisperCancellation) throws -> [WhisperSpeechSegment] {
        workerExecutor.assertCurrent()
        try checkCancellation(flag)
        guard !pcm.isEmpty else { return [] }
        // Digital silence has no speech information. This is not a fabricated
        // recognition result; native speech is still required for every word.
        guard pcm.contains(where: { $0 != 0 }) else {
            pcm = []; windowStart = acceptedSamples; partial = ""
            return []
        }
        guard let context = native.context else { throw StreamingASRError.noActiveStream }
        let sourceCount = pcm.count
        var input = pcm
        if input.count < Self.sampleRate { input += Array(repeating: 0, count: Self.sampleRate - input.count) }
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.n_threads = 4
        parameters.n_max_text_ctx = 0
        parameters.no_context = true
        parameters.no_timestamps = false
        parameters.single_segment = false
        parameters.token_timestamps = false
        parameters.print_special = false; parameters.print_progress = false
        parameters.print_realtime = false; parameters.print_timestamps = false
        parameters.translate = false; parameters.detect_language = false
        parameters.temperature = 0; parameters.temperature_inc = 0
        parameters.greedy.best_of = 1
        parameters.suppress_blank = true; parameters.suppress_nst = true
        parameters.abort_callback = { pointer in
            guard let pointer else { return false }
            return Unmanaged<WhisperCancellation>.fromOpaque(pointer).takeUnretainedValue().isCancelled
        }
        parameters.abort_callback_user_data = Unmanaged.passUnretained(flag).toOpaque()
        observe(.decode, gpu: false)
        let status = "en".withCString { language in
            parameters.language = language
            return input.withUnsafeBufferPointer { audio in
                whisper_full(context, parameters, audio.baseAddress, Int32(audio.count))
            }
        }
        try checkCancellation(flag)
        guard status == 0 else { throw StreamingASRError.nativeCreationFailed }
        let segmentCount = whisper_full_n_segments(context)
        guard segmentCount >= 0, segmentCount <= 1_024 else { throw StreamingASRError.nativeCreationFailed }
        let stableEnd = forceFinal ? acceptedSamples : max(0, acceptedSamples - 32_000)
        var finalized: [WhisperSpeechSegment] = []
        var tail: [String] = []
        for index in 0..<segmentCount {
            try checkCancellation(flag)
            guard whisper_full_get_segment_no_speech_prob(context, index) <= parameters.no_speech_thold,
                  let textPointer = whisper_full_get_segment_text(context, index) else { continue }
            let text = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            let t0 = whisper_full_get_segment_t0(context, index)
            let t1 = whisper_full_get_segment_t1(context, index)
            guard !text.isEmpty, text.utf8.count <= 65_536, t0 >= 0, t1 >= t0 else { continue }
            let start = windowStart + min(Int64(sourceCount), min(t0, 3_000) * 160)
            let end = windowStart + min(Int64(sourceCount), min(t1, 3_000) * 160)
            guard end > start, end > committedThrough, start >= committedThrough else { continue }
            if end <= stableEnd {
                finalized.append(.init(id: UUID(), startSample: start, endSample: end, text: text))
                committedThrough = end
            } else { tail.append(text) }
        }
        if forceFinal {
            // The complete source window was processed, including any native
            // no-speech tail. Internal padding never advances source counters.
            pcm = []; windowStart = acceptedSamples; partial = ""
        } else {
            let consumed = Int(min(Int64(sourceCount), max(0, committedThrough - windowStart)))
            if consumed > 0 { pcm.removeFirst(consumed); windowStart += Int64(consumed) }
            partial = tail.joined(separator: " ")
        }
        return finalized
    }

    private func observe(_ operation: WhisperNativeOperation, gpu: Bool) {
        workerExecutor.assertCurrent()
        executionObserver?(operation, Thread.isMainThread, gpu)
    }

    private func validateModel(_ flag: WhisperCancellation) throws {
        guard files.model.isFileURL, files.revision.utf8.count == 40,
              files.revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              files.byteCount > 0, files.byteCount <= 4_000_000_000, files.sha256.utf8.count == 64,
              files.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw StreamingASRError.invalidModel
        }
        do {
            let values = try files.model.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize.map({ Int64($0) }) == files.byteCount else { throw StreamingASRError.invalidModel }
            let input = try FileHandle(forReadingFrom: files.model)
            defer { try? input.close() }
            var digest = SHA256(); var count: Int64 = 0
            while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty {
                try checkCancellation(flag)
                count += Int64(bytes.count)
                guard count <= files.byteCount else { throw StreamingASRError.invalidModel }
                digest.update(data: bytes)
            }
            guard count == files.byteCount,
                  digest.finalize().map({ String(format: "%02x", $0) }).joined() == files.sha256 else {
                throw StreamingASRError.invalidModel
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw StreamingASRError.invalidModel }
    }
}

private enum WhisperNativeBackend {
    static let initialized: Void = {
        whisper_log_set({ _, _, _ in }, nil)
        ggml_log_set({ _, _, _ in }, nil)
    }()
}

private final class WhisperNativeResources {
    var context: OpaquePointer?
    deinit { if let context { whisper_free(context) } }
}

private final class WhisperCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

private final class WhisperCancellationRouter: Sendable {
    private struct State: Sendable { var id: UUID?; var flag: WhisperCancellation? }
    private let state = Mutex(State())
    func select(_ id: UUID?, flag: WhisperCancellation?) { state.withLock { $0 = State(id: id, flag: flag) } }
    func cancel(_ id: UUID) -> WhisperCancellation? {
        state.withLock {
            guard $0.id == id else { return nil }
            $0.flag?.cancel(); return $0.flag
        }
    }
    func cancelAll() { state.withLock { $0.flag?.cancel() } }
}

private final class WhisperSerialExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "LocalMinutes.whisper.cpu", qos: .userInitiated)
    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { unowned.runSynchronously(on: executor) }
    }
    func assertCurrent() { dispatchPrecondition(condition: .onQueue(queue)) }
}
