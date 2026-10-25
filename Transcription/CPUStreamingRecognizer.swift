import CryptoKit
import Dispatch
import Foundation
import SherpaOnnx
import SherpaOnnxC

// In the app, these immutable files come from a held verified-model lease.
// The adapter additionally verifies the exact supported bytes before entering
// C++, whose model constructor cannot report every failure as a Swift error.
public struct StreamingASRModelFiles: Equatable, Sendable {
    public let encoder: URL
    public let decoder: URL
    public let joiner: URL
    public let tokens: URL
    public let revision: String
    public let runtimeVersion: String

    public init(encoder: URL, decoder: URL, joiner: URL, tokens: URL,
                revision: String, runtimeVersion: String) {
        self.encoder = encoder
        self.decoder = decoder
        self.joiner = joiner
        self.tokens = tokens
        self.revision = revision
        self.runtimeVersion = runtimeVersion
    }
}

public enum StreamingASRError: Error, Equatable, Sendable {
    case invalidModel
    case nativeCreationFailed
    case noActiveStream
    case alreadyStarted
    case finished
    case cancelled
    case invalidSamples
    case discontinuity(expected: Int64, actual: Int64)
    case endpointRequired
}

public enum StreamingASRPhase: Equatable, Sendable {
    case unloaded, ready, streaming, finished, cancelled
}

public enum StreamingASRProvider: Equatable, Sendable { case cpu }

enum StreamingASRNativeOperation: Equatable, Sendable { case load, decode }
// Arguments: native operation, actual Thread.isMainThread, actual queue identity.
typealias StreamingASRExecutionObserver = @Sendable (StreamingASRNativeOperation, Bool, Bool) -> Void

public struct StreamingASRSnapshot: Equatable, Sendable {
    public let phase: StreamingASRPhase
    public let epochID: UUID?
    public let provider: StreamingASRProvider?
    public let modelRevision: String?
    public let runtimeVersion: String?
    public let acceptedSampleCount: Int64

    public init(phase: StreamingASRPhase, epochID: UUID? = nil,
                provider: StreamingASRProvider? = nil, modelRevision: String? = nil,
                runtimeVersion: String? = nil, acceptedSampleCount: Int64 = 0) {
        self.phase = phase
        self.epochID = epochID
        self.provider = provider
        self.modelRevision = modelRevision
        self.runtimeVersion = runtimeVersion
        self.acceptedSampleCount = acceptedSampleCount
    }
}

public struct StreamingASRResult: Equatable, Sendable {
    public let epochID: UUID
    public let text: String
    public let isFinal: Bool
    public let isEndpoint: Bool
    // Actual upstream token times are relative to the current utterance. An
    // empty array means unavailable; this slice does not invent global timing.
    public let tokenTimes: [Float]

    public init(epochID: UUID, text: String, isFinal: Bool,
                isEndpoint: Bool, tokenTimes: [Float] = []) {
        self.epochID = epochID
        self.text = text
        self.isFinal = isFinal
        self.isEndpoint = isEndpoint
        self.tokenTimes = tokenTimes
    }
}

// A caller supplies one bounded chunk at a time and awaits its result. All C
// ownership and inference remain on the dedicated executor. Endpoint reset
// preserves the captured source timeline; decoder-only final padding does not
// advance that timeline. Await unload() before releasing the model lease.
public actor CPUStreamingRecognizer {
    private nonisolated let workerExecutor = ASRSerialExecutor()
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        workerExecutor.asUnownedSerialExecutor()
    }

    private let files: StreamingASRModelFiles
    private let executionObserver: StreamingASRExecutionObserver?
    private let native = ASRNativeResources()
    private var recognizer: OpaquePointer? {
        get { native.recognizer }
        set { native.recognizer = newValue }
    }
    private var stream: OpaquePointer? {
        get { native.stream }
        set { native.stream = newValue }
    }
    private var phase: StreamingASRPhase = .unloaded
    private var epochID: UUID?
    private var acceptedSampleCount: Int64 = 0
    private var nativeVersion: String?
    private var completedResult: StreamingASRResult?

    public init(files: StreamingASRModelFiles) {
        self.files = files
        executionObserver = nil
    }

    // Test-only observation of the actual native-call site. The public
    // initializer always uses nil; this hook adds no production task/locking.
    init(files: StreamingASRModelFiles, executionObserver: @escaping StreamingASRExecutionObserver) {
        self.files = files
        self.executionObserver = executionObserver
    }

    public func load() throws {
        workerExecutor.assertCurrent()
        if recognizer != nil { return }
        try validateSupportedFiles()
        observe(.load)
        guard let version = SherpaOnnxGetVersionStr() else {
            throw StreamingASRError.nativeCreationFailed
        }
        let actualVersion = String(cString: version)
        guard actualVersion == "1.13.8" else { throw StreamingASRError.invalidModel }

        // The C entry point copies these strings synchronously into C++ owned
        // configuration. None of the borrowed pointers escapes these scopes.
        let created = files.encoder.path.withCString { encoder in
            files.decoder.path.withCString { decoder in
                files.joiner.path.withCString { joiner in
                    files.tokens.path.withCString { tokens in
                        "cpu".withCString { provider in
                            "greedy_search".withCString { decoding in
                                var config = SherpaOnnxOnlineRecognizerConfig()
                                config.feat_config.sample_rate = 16_000
                                config.feat_config.feature_dim = 80
                                config.model_config.transducer.encoder = encoder
                                config.model_config.transducer.decoder = decoder
                                config.model_config.transducer.joiner = joiner
                                config.model_config.tokens = tokens
                                config.model_config.num_threads = 2
                                config.model_config.provider = provider
                                config.model_config.debug = 0
                                config.decoding_method = decoding
                                config.max_active_paths = 4
                                config.enable_endpoint = 1
                                config.rule1_min_trailing_silence = 2.4
                                config.rule2_min_trailing_silence = 1.2
                                config.rule3_min_utterance_length = 20
                                return SherpaOnnxCreateOnlineRecognizer(&config)
                            }
                        }
                    }
                }
            }
        }
        guard let created else { throw StreamingASRError.nativeCreationFailed }
        recognizer = created
        nativeVersion = actualVersion
        phase = .ready
        epochID = nil
        acceptedSampleCount = 0
        completedResult = nil
    }

    public func start(epochID: UUID) throws {
        workerExecutor.assertCurrent()
        guard let recognizer else { throw StreamingASRError.noActiveStream }
        guard phase != .streaming else { throw StreamingASRError.alreadyStarted }
        guard let created = SherpaOnnxCreateOnlineStream(recognizer) else {
            throw StreamingASRError.nativeCreationFailed
        }
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        stream = created
        self.epochID = epochID
        acceptedSampleCount = 0
        completedResult = nil
        phase = .streaming
    }

    // Exactly 16 kHz mono normalized Float32; 1...3,200 finite samples per call.
    // Source positions start at zero per epoch and must remain contiguous.
    public func accept(samples: [Float], sourceStartSample: Int64) throws -> StreamingASRResult {
        workerExecutor.assertCurrent()
        try requireActiveStream()
        guard !samples.isEmpty, samples.count <= 3_200,
              samples.allSatisfy(\.isFinite) else { throw StreamingASRError.invalidSamples }
        guard sourceStartSample == acceptedSampleCount else {
            throw StreamingASRError.discontinuity(expected: acceptedSampleCount, actual: sourceStartSample)
        }
        let (nextCount, overflow) = acceptedSampleCount.addingReportingOverflow(Int64(samples.count))
        guard !overflow else { throw StreamingASRError.invalidSamples }
        guard let stream else { throw StreamingASRError.noActiveStream }
        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxOnlineStreamAcceptWaveform(stream, 16_000, buffer.baseAddress, Int32(buffer.count))
        }
        acceptedSampleCount = nextCount
        do {
            try drainReadyFrames()
            return try copyResult(isFinal: false)
        } catch {
            cancel()
            throw error
        }
    }

    public func finish() throws -> StreamingASRResult {
        workerExecutor.assertCurrent()
        if let completedResult { return completedResult }
        try requireActiveStream()
        guard let stream else { throw StreamingASRError.noActiveStream }
        do {
            // Bounded model lookahead flush, observed necessary for the final
            // plural word in the pinned real fixture. This is not source audio.
            let padding = [Float](repeating: 0, count: 3_200)
            var remaining = 24_000
            while remaining > 0 {
                let count = min(remaining, padding.count)
                padding.withUnsafeBufferPointer { buffer in
                    SherpaOnnxOnlineStreamAcceptWaveform(stream, 16_000, buffer.baseAddress, Int32(count))
                }
                try drainReadyFrames()
                remaining -= count
            }
            SherpaOnnxOnlineStreamInputFinished(stream)
            try drainReadyFrames()
            let final = try copyResult(isFinal: true)
            completedResult = final
            SherpaOnnxDestroyOnlineStream(stream)
            self.stream = nil
            phase = .finished
            return final
        } catch {
            cancel()
            throw error
        }
    }

    public func resetAfterEndpoint() throws {
        workerExecutor.assertCurrent()
        try requireActiveStream()
        guard let recognizer, let stream else { throw StreamingASRError.noActiveStream }
        guard SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0 else {
            throw StreamingASRError.endpointRequired
        }
        SherpaOnnxOnlineStreamReset(recognizer, stream)
    }

    public func cancel() {
        workerExecutor.assertCurrent()
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        stream = nil
        completedResult = nil
        if recognizer != nil { phase = .cancelled }
    }

    public func unload() {
        workerExecutor.assertCurrent()
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        if let recognizer { SherpaOnnxDestroyOnlineRecognizer(recognizer) }
        stream = nil
        recognizer = nil
        completedResult = nil
        nativeVersion = nil
        epochID = nil
        acceptedSampleCount = 0
        phase = .unloaded
    }

    public func snapshot() -> StreamingASRSnapshot {
        StreamingASRSnapshot(phase: phase, epochID: epochID,
            provider: recognizer == nil ? nil : .cpu,
            modelRevision: recognizer == nil ? nil : files.revision,
            runtimeVersion: nativeVersion, acceptedSampleCount: acceptedSampleCount)
    }

    private func requireActiveStream() throws {
        switch phase {
        case .cancelled: throw StreamingASRError.cancelled
        case .finished: throw StreamingASRError.finished
        case .streaming:
            guard recognizer != nil, stream != nil, epochID != nil else {
                throw StreamingASRError.noActiveStream
            }
        case .unloaded, .ready: throw StreamingASRError.noActiveStream
        }
    }

    private func drainReadyFrames() throws {
        guard let recognizer, let stream else { throw StreamingASRError.noActiveStream }
        var decoded = 0
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            guard decoded < 2_048 else { throw StreamingASRError.nativeCreationFailed }
            observe(.decode)
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
            decoded += 1
        }
    }

    private func copyResult(isFinal: Bool) throws -> StreamingASRResult {
        guard let recognizer, let stream, let epochID else {
            throw StreamingASRError.noActiveStream
        }
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else {
            throw StreamingASRError.nativeCreationFailed
        }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        let native = result.pointee
        guard let textPointer = native.text, let text = String(validatingCString: textPointer),
              native.count >= 0, native.count <= 16_384 else {
            throw StreamingASRError.nativeCreationFailed
        }
        let times: [Float]
        if let timestamps = native.timestamps, native.count > 0 {
            times = Array(UnsafeBufferPointer(start: timestamps, count: Int(native.count)))
            guard times.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw StreamingASRError.nativeCreationFailed
            }
        } else {
            times = []
        }
        return StreamingASRResult(epochID: epochID, text: text, isFinal: isFinal,
            isEndpoint: SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0,
            tokenTimes: times)
    }

    private func observe(_ operation: StreamingASRNativeOperation) {
        workerExecutor.assertCurrent()
        executionObserver?(operation, Thread.isMainThread, true)
    }

    private func validateSupportedFiles() throws {
        guard files.revision == "672fbf1b30579d6585301139bb363f42a0ad4a24",
              files.runtimeVersion == "sherpa-onnx-1.13.8" else { throw StreamingASRError.invalidModel }
        let artifacts: [(URL, Int, String)] = [
            (files.encoder, 71_083_163, "563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1"),
            (files.decoder, 1_307_236, "98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02"),
            (files.joiner, 259_335, "d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297"),
            (files.tokens, 5_048, "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb")
        ]
        do {
            for (url, expectedCount, expectedDigest) in artifacts {
                guard url.isFileURL else { throw StreamingASRError.invalidModel }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      values.fileSize == expectedCount, let input = InputStream(url: url) else {
                    throw StreamingASRError.invalidModel
                }
                input.open()
                defer { input.close() }
                var digest = SHA256()
                var bytes = [UInt8](repeating: 0, count: 65_536)
                var total = 0
                while true {
                    let count = input.read(&bytes, maxLength: bytes.count)
                    guard count >= 0 else { throw StreamingASRError.invalidModel }
                    if count == 0 { break }
                    total += count
                    guard total <= expectedCount else { throw StreamingASRError.invalidModel }
                    digest.update(data: Data(bytes.prefix(count)))
                }
                let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard total == expectedCount, actual == expectedDigest else {
                    throw StreamingASRError.invalidModel
                }
            }
        } catch {
            throw StreamingASRError.invalidModel
        }
    }
}

// This non-Sendable box never escapes the actor. Ordinary ARC destruction runs
// only after the owning actor and its jobs release it, so no callback/inference
// can still access these handles. Explicit awaited unload() clears the handles
// on the dedicated worker first; the fallback only handles abandoned clients.
// A normal box deinit supports iOS18/macOS15, unlike actor isolated deinit which
// requires the newer18.4/15.4 runtime. No pointer is made Sendable or cast to an
// integer to circumvent ownership checking.
private final class ASRNativeResources {
    var recognizer: OpaquePointer?
    var stream: OpaquePointer?

    deinit {
        if let stream { SherpaOnnxDestroyOnlineStream(stream) }
        if let recognizer { SherpaOnnxDestroyOnlineRecognizer(recognizer) }
    }
}

private final class ASRSerialExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "LocalMinutes.asr.cpu", qos: .userInitiated)

    func enqueue(_ job: consuming ExecutorJob) {
        let unownedJob = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { unownedJob.runSynchronously(on: executor) }
    }

    func assertCurrent() { dispatchPrecondition(condition: .onQueue(queue)) }
}
