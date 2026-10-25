import CoreML
import CryptoKit
import Darwin
import Dispatch
import FluidAudio
import Foundation
import Synchronization
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// Live and recovery composition default to CPU-only. An explicit adapter
/// override may allow the Neural Engine; neither policy enables the GPU.
public enum CoreMLParakeetComputePolicy: String, Equatable, Sendable {
    case cpuOnly, cpuAndNeuralEngine
}

public struct CoreMLParakeetModelFiles: Equatable, Sendable {
    public let directory: URL
    public let revision: String
    public let runtimeVersion: String
    public let manifest: ModelManifest
    public init(directory: URL, revision: String, runtimeVersion: String) {
        self.directory = directory; self.revision = revision; self.runtimeVersion = runtimeVersion
        self.manifest = ParakeetCoreMLModel.manifest
    }
    public init(directory: URL, manifest: ModelManifest) {
        self.directory = directory; self.manifest = manifest
        self.revision = manifest.revision; self.runtimeVersion = manifest.runtimeVersion
    }
}

public struct CoreMLParakeetSnapshot: Equatable, Sendable {
    public let phase: SpeechRecognitionPhase
    public let epochID: UUID?
    public let computePolicy: CoreMLParakeetComputePolicy?
    public let modelRevision: String?
    public let acceptedSampleCount: Int64
    public let bufferedSampleCount: Int

    public init(phase: SpeechRecognitionPhase, epochID: UUID?, computePolicy: CoreMLParakeetComputePolicy?,
                modelRevision: String?, acceptedSampleCount: Int64, bufferedSampleCount: Int) {
        self.phase = phase; self.epochID = epochID; self.computePolicy = computePolicy
        self.modelRevision = modelRevision; self.acceptedSampleCount = acceptedSampleCount
        self.bufferedSampleCount = bufferedSampleCount
    }
}

enum CoreMLParakeetNativeOperation: Equatable, Sendable { case load, decode }
typealias CoreMLParakeetExecutionObserver = @Sendable
    (CoreMLParakeetNativeOperation, Bool, Bool, CoreMLParakeetComputePolicy) -> Void

/// Parakeet TDT v2/v3 Core ML inference with FluidAudio's Swift decoder.
/// Disjoint five-second windows are finalized during capture.
public actor CoreMLParakeetRecognizer {
    public static let sampleRate = 16_000
    public static let stepSamples = 80_000
    public static let maximumWindowSamples = 240_000

    private nonisolated let worker = CoreMLParakeetWorker()
    public nonisolated var unownedExecutor: UnownedSerialExecutor { worker.asUnownedSerialExecutor() }
    private nonisolated let cancellationRouter = CoreMLParakeetCancellationRouter()
    private let files: CoreMLParakeetModelFiles
    private let computePolicy: CoreMLParakeetComputePolicy
    private let executionObserver: CoreMLParakeetExecutionObserver?
    private var manager: AsrManager?
    private var phase: SpeechRecognitionPhase = .unloaded
    private var epochID: UUID?
    private var cancellation = CoreMLParakeetCancellation()
    private var pcm: [Float] = []
    private var acceptedSamples: Int64 = 0
    private var windowStart: Int64 = 0
    private var decodeTask: Task<ASRResult, Error>?
    private var decodeID: UUID?
    private var teardown: Task<Void, Never>?

    public init(files: CoreMLParakeetModelFiles,
                computePolicy: CoreMLParakeetComputePolicy = .cpuOnly) {
        self.files = files; self.computePolicy = computePolicy; executionObserver = nil
    }
    init(files: CoreMLParakeetModelFiles, computePolicy: CoreMLParakeetComputePolicy,
         executionObserver: @escaping CoreMLParakeetExecutionObserver) {
        self.files = files; self.computePolicy = computePolicy; self.executionObserver = executionObserver
    }

    public func load() async throws {
        worker.assertCurrent()
        guard teardown == nil else { throw SpeechRecognitionError.noActiveStream }
        if manager != nil { return }
        let flag = CoreMLParakeetCancellation()
        cancellationRouter.select(nil, flag: flag)
        try await withTaskCancellationHandler {
            try validateModel(flag)
            let configuration = MLModelConfiguration()
            switch computePolicy {
            case .cpuOnly: configuration.computeUnits = .cpuOnly
            case .cpuAndNeuralEngine: configuration.computeUnits = .cpuAndNeuralEngine
            }
            configuration.allowLowPrecisionAccumulationOnGPU = false
            // The upstream default mirrors Debug text to stderr, including
            // decoder text. Keep that route disabled for real meeting input.
            AppLogger.minimumLevel = .fault
            AppLogger.mirrorsToConsole = false
            observe(.load)
            let models = try ParakeetModelAdapter.load(directory: files.directory,
                manifest: files.manifest, configuration: configuration)
            try checkCancellation(flag)
            manager = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1), models: models)
            phase = .ready
        } onCancel: { flag.cancel() }
    }

    public func start(epochID: UUID) throws {
        worker.assertCurrent()
        try Task.checkCancellation()
        guard manager != nil, teardown == nil else { throw SpeechRecognitionError.noActiveStream }
        guard phase != .streaming, decodeTask == nil else { throw SpeechRecognitionError.alreadyStarted }
        self.epochID = epochID
        phase = .streaming
        acceptedSamples = 0; windowStart = 0
        pcm = []; pcm.reserveCapacity(Self.stepSamples)
        cancellation = CoreMLParakeetCancellation()
        cancellationRouter.select(epochID, flag: cancellation)
    }

    public func accept(_ samples: [Float], at globalSampleOffset: Int64) async throws -> SpeechUpdate {
        worker.assertCurrent()
        let epoch = try activeEpoch()
        let flag = cancellation
        try checkCancellation(flag)
        guard decodeTask == nil else { throw SpeechRecognitionError.alreadyStarted }
        guard !samples.isEmpty, samples.count <= Self.stepSamples,
              samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }),
              acceptedSamples <= Int64.max - Int64(samples.count) else { throw SpeechRecognitionError.invalidSamples }
        guard globalSampleOffset == acceptedSamples else {
            throw SpeechRecognitionError.discontinuity(expected: acceptedSamples, actual: globalSampleOffset)
        }
        var offset = 0
        var finalized: [SpeechSegment] = []
        while offset < samples.count {
            try checkCancellation(flag)
            let count = min(Self.stepSamples - pcm.count, samples.count - offset)
            pcm.append(contentsOf: samples[offset..<(offset + count)])
            acceptedSamples += Int64(count); offset += count
            if pcm.count == Self.stepSamples {
                finalized += try await decode(epoch: epoch, flag: flag)
            }
        }
        try checkCancellation(flag)
        guard epochID == epoch, cancellation === flag, phase == .streaming else { throw SpeechRecognitionError.cancelled }
        return .init(epochID: epoch, partial: "", finalized: finalized)
    }

    public func finish() async throws -> SpeechUpdate {
        worker.assertCurrent()
        if phase == .finished, let epochID { return .init(epochID: epochID, partial: "", finalized: []) }
        let epoch = try activeEpoch()
        let flag = cancellation
        guard decodeTask == nil else { throw SpeechRecognitionError.alreadyStarted }
        let result = try await decode(epoch: epoch, flag: flag)
        try checkCancellation(flag)
        guard epochID == epoch, cancellation === flag, phase == .streaming, teardown == nil else {
            throw SpeechRecognitionError.cancelled
        }
        phase = .finished
        return .init(epochID: epoch, partial: "", finalized: result)
    }

    public nonisolated func cancel(epochID: UUID) async {
        guard let flag = cancellationRouter.cancel(epochID) else { return }
        await cancelOnWorker(epochID: epochID, flag: flag)
    }

    private func cancelOnWorker(epochID: UUID, flag: CoreMLParakeetCancellation) async {
        worker.assertCurrent()
        guard self.epochID == epochID, cancellation === flag else { return }
        phase = .cancelled
        if let task = decodeTask {
            task.cancel()
            _ = try? await task.value
        }
        guard self.epochID == epochID, cancellation === flag else { return }
        decodeTask = nil; decodeID = nil
        pcm.removeAll(keepingCapacity: true); windowStart = acceptedSamples
    }

    public nonisolated func unload() async {
        cancellationRouter.cancelAll()
        await requestUnload()
    }

    private func requestUnload() async {
        worker.assertCurrent()
        if let teardown { await teardown.value; return }
        let task = Task { await self.performUnload() }
        teardown = task
        await task.value
    }

    private func performUnload() async {
        worker.assertCurrent()
        if let task = decodeTask {
            task.cancel()
            _ = try? await task.value
        }
        if let manager {
            // No model cache is used by loadLocal. Cleanup releases each model
            // reference after the sole decoder task has actually settled.
            await withTaskExecutorPreference(worker) { await manager.cleanup() }
        }
        manager = nil; decodeTask = nil; decodeID = nil
        pcm = []; acceptedSamples = 0; windowStart = 0; epochID = nil
        phase = .unloaded
        cancellationRouter.select(nil, flag: nil)
        teardown = nil
    }

    public func snapshot() -> CoreMLParakeetSnapshot {
        .init(phase: phase, epochID: epochID, computePolicy: manager == nil ? nil : computePolicy,
              modelRevision: manager == nil ? nil : files.revision,
              acceptedSampleCount: acceptedSamples, bufferedSampleCount: pcm.count)
    }

    private func activeEpoch() throws -> UUID {
        if phase == .cancelled || cancellation.isCancelled { throw SpeechRecognitionError.cancelled }
        if phase == .finished { throw SpeechRecognitionError.finished }
        guard phase == .streaming, let epochID, manager != nil, teardown == nil else {
            throw SpeechRecognitionError.noActiveStream
        }
        return epochID
    }

    private func checkCancellation(_ flag: CoreMLParakeetCancellation) throws {
        if flag.isCancelled || Task.isCancelled { throw CancellationError() }
    }

    private func decode(epoch: UUID, flag: CoreMLParakeetCancellation) async throws -> [SpeechSegment] {
        worker.assertCurrent()
        try checkCancellation(flag)
        guard !pcm.isEmpty else { return [] }
        guard let manager, decodeTask == nil, teardown == nil else { throw SpeechRecognitionError.noActiveStream }
        let start = windowStart
        let end = start + Int64(pcm.count)
        var input = pcm
        // FluidAudio rejects very short clips. Decoder padding never advances
        // source counters or the range of the resulting genuine audio segment.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate)
        guard minimum > 0, minimum <= Self.maximumWindowSamples else { throw SpeechRecognitionError.invalidSamples }
        if input.count < minimum { input.append(contentsOf: repeatElement(Float(0), count: minimum - input.count)) }
        let samples = input
        let observer = executionObserver
        let policy = computePolicy
        let executor = worker
        let operationID = UUID()
        let task = Task(executorPreference: executor) {
            executor.assertCurrent()
            try Task.checkCancellation()
            var state = try TdtDecoderState(decoderLayers: 2)
            observer?(.decode, Self.isMainThread(), true, policy)
            return try await manager.transcribe(samples, decoderState: &state)
        }
        decodeID = operationID; decodeTask = task
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                flag.cancel(); task.cancel()
            }
            if decodeID == operationID { decodeID = nil; decodeTask = nil }
            try checkCancellation(flag)
            guard epochID == epoch, cancellation === flag, phase == .streaming, teardown == nil else {
                throw SpeechRecognitionError.cancelled
            }
            pcm.removeAll(keepingCapacity: true); windowStart = end
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [.init(id: UUID(), startSample: start, endSample: end, text: text)]
        } catch {
            if decodeID == operationID { decodeID = nil; decodeTask = nil }
            throw error
        }
    }

    private func observe(_ operation: CoreMLParakeetNativeOperation) {
        worker.assertCurrent()
        executionObserver?(operation, Thread.isMainThread, true, computePolicy)
    }

    private nonisolated static func isMainThread() -> Bool { Thread.isMainThread }

    private func validateModel(_ flag: CoreMLParakeetCancellation) throws {
        try checkCancellation(flag)
        let manifest = files.manifest
        guard (try? ParakeetModelPack.configuration(for: manifest)) != nil else { throw SpeechRecognitionError.invalidModel }
        guard files.revision == manifest.revision, files.runtimeVersion == manifest.runtimeVersion,
              files.directory.isFileURL else { throw SpeechRecognitionError.invalidModel }
        let root = files.directory.standardizedFileURL
        let canonical = root.resolvingSymlinksInPath()
        let rootComponents = canonical.pathComponents
        do {
            let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw SpeechRecognitionError.invalidModel }
            let expected = Set(manifest.artifacts.map(\.fileName))
            let allowedFiles = expected.union(["manifest.json"])
            let maximumDepth = manifest.artifacts.map { $0.fileName.split(separator: "/").count }.max() ?? 1
            var directories: Set<String> = []
            for artifact in manifest.artifacts {
                let parts = artifact.fileName.split(separator: "/")
                for count in 1..<parts.count { directories.insert(parts.prefix(count).joined(separator: "/")) }
            }
            guard let iterator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
                throw SpeechRecognitionError.invalidModel
            }
            var observed: Set<String> = []
            var visited = 0
            for case let url as URL in iterator {
                visited += 1
                // Directory-hinted and enumerated URLs can differ in trailing
                // slash or system alias spelling (/var versus /private/var).
                // Canonical component ancestry defines containment and names.
                let components = url.resolvingSymlinksInPath().pathComponents
                guard visited <= allowedFiles.count + directories.count,
                      components.count > rootComponents.count,
                      components.starts(with: rootComponents),
                      components.count - rootComponents.count <= maximumDepth else { throw SpeechRecognitionError.invalidModel }
                let name = components.dropFirst(rootComponents.count).joined(separator: "/")
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw SpeechRecognitionError.invalidModel }
                if values.isDirectory == true {
                    guard directories.contains(name) else { throw SpeechRecognitionError.invalidModel }
                } else if name == "manifest.json" {
                    guard values.isRegularFile == true else { throw SpeechRecognitionError.invalidModel }
                    try validateInstallationManifest(url, expected: manifest, flag: flag)
                } else {
                    guard values.isRegularFile == true, expected.contains(name) else { throw SpeechRecognitionError.invalidModel }
                    observed.insert(name)
                }
            }
            guard observed == expected else { throw SpeechRecognitionError.invalidModel }
            for artifact in manifest.artifacts {
                try checkCancellation(flag)
                let url = root.appendingPathComponent(artifact.fileName)
                let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                guard size == artifact.byteCount else { throw SpeechRecognitionError.invalidModel }
                let handle = try FileHandle(forReadingFrom: url)
                var hash = SHA256()
                do {
                    try ModelFileIO.forEachChunk(in: handle) { bytes in
                        try checkCancellation(flag)
                        hash.update(data: bytes)
                    }
                    try handle.close()
                } catch { try? handle.close(); throw error }
                let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
                guard actual == artifact.sha256 else { throw SpeechRecognitionError.invalidModel }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw SpeechRecognitionError.invalidModel }
    }

    /// Only the real installer's own bounded metadata is permitted beside the
    /// 21 immutable Core ML assets. The opened descriptor, rather than a prior
    /// path inspection alone, establishes regular-file/no-link ownership.
    private func validateInstallationManifest(_ url: URL, expected: ModelManifest,
                                              flag: CoreMLParakeetCancellation) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw SpeechRecognitionError.invalidModel }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              UInt32(info.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG),
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 65_536 else {
            throw SpeechRecognitionError.invalidModel
        }
        var bytes = Data()
        while let next = try handle.read(upToCount: 4_096), !next.isEmpty {
            try checkCancellation(flag)
            guard bytes.count <= 65_536 - next.count else { throw SpeechRecognitionError.invalidModel }
            bytes.append(next)
        }
        guard bytes.count == Int(info.st_size),
              try JSONDecoder().decode(ModelManifest.self, from: bytes) == expected,
              let actualObject = try JSONSerialization.jsonObject(with: bytes) as? NSDictionary,
              let expectedObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? NSDictionary,
              actualObject.isEqual(expectedObject) else { throw SpeechRecognitionError.invalidModel }
    }
}

private final class CoreMLParakeetCancellation: Sendable {
    private let cancelled = Mutex(false)
    var isCancelled: Bool { cancelled.withLock { $0 } }
    func cancel() { cancelled.withLock { $0 = true } }
}

private final class CoreMLParakeetCancellationRouter: Sendable {
    private struct State: Sendable { var epoch: UUID?; var flag: CoreMLParakeetCancellation? }
    private let state = Mutex(State())
    func select(_ epoch: UUID?, flag: CoreMLParakeetCancellation?) {
        state.withLock { $0 = State(epoch: epoch, flag: flag) }
    }
    func cancel(_ epoch: UUID) -> CoreMLParakeetCancellation? {
        state.withLock { value in
            guard value.epoch == epoch else { return nil }
            value.flag?.cancel(); return value.flag
        }
    }
    func cancelAll() { state.withLock { $0.flag?.cancel() } }
}

/// The task preference keeps FluidAudio's default actor and its structured
/// decoder work on this serial queue, rather than the cooperative global pool.
private final class CoreMLParakeetWorker: SerialExecutor, TaskExecutor {
    private let queue = DispatchQueue(label: "LocalMinutes.asr.coreml.parakeet", qos: .userInitiated)
    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(isolatedTo: self.asUnownedSerialExecutor(),
                                     taskExecutor: self.asUnownedTaskExecutor())
        }
    }
    func asUnownedSerialExecutor() -> UnownedSerialExecutor { .init(ordinary: self) }
    func asUnownedTaskExecutor() -> UnownedTaskExecutor { .init(ordinary: self) }
    func assertCurrent() { dispatchPrecondition(condition: .onQueue(queue)) }
}
