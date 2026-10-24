import CoreML
import FluidAudio
import Foundation

/// Core ML never enables GPU for background capture. Native CI uses CPU-only;
/// an equipped phone may use CPU and the Apple Neural Engine.
public enum CoreMLParakeetComputePolicy: String, Equatable, Sendable {
    case cpuOnly, cpuAndNeuralEngine
}

public struct CoreMLParakeetModelFiles: Equatable, Sendable {
    public let directory: URL
    public let revision: String
    public let runtimeVersion: String
    public init(directory: URL, revision: String, runtimeVersion: String) {
        self.directory = directory; self.revision = revision; self.runtimeVersion = runtimeVersion
    }
}

public struct CoreMLParakeetSnapshot: Equatable, Sendable {
    public let phase: StreamingASRPhase
    public let epochID: UUID?
    public let computePolicy: CoreMLParakeetComputePolicy?
    public let modelRevision: String?
    public let acceptedSampleCount: Int64
    public let bufferedSampleCount: Int

    public init(phase: StreamingASRPhase, epochID: UUID?, computePolicy: CoreMLParakeetComputePolicy?,
                modelRevision: String?, acceptedSampleCount: Int64, bufferedSampleCount: Int) {
        self.phase = phase; self.epochID = epochID; self.computePolicy = computePolicy
        self.modelRevision = modelRevision; self.acceptedSampleCount = acceptedSampleCount
        self.bufferedSampleCount = bufferedSampleCount
    }
}

enum CoreMLParakeetNativeOperation: Equatable, Sendable { case load, decode }
typealias CoreMLParakeetExecutionObserver = @Sendable
    (CoreMLParakeetNativeOperation, Bool, Bool, CoreMLParakeetComputePolicy) -> Void

/// TEST-FIRST INTERFACE ONLY. The v2 Core ML family is offline: a future
/// implementation uses FluidAudio's Swift TDT decoder over bounded audio
/// windows, with no sherpa/ONNX, whisper or llama adapter underneath it.
public actor CoreMLParakeetRecognizer {
    public static let sampleRate = 16_000
    public static let stepSamples = 80_000
    public static let maximumWindowSamples = 240_000

    public init(files: CoreMLParakeetModelFiles,
                computePolicy: CoreMLParakeetComputePolicy = .cpuAndNeuralEngine) {}
    init(files: CoreMLParakeetModelFiles, computePolicy: CoreMLParakeetComputePolicy,
         executionObserver: @escaping CoreMLParakeetExecutionObserver) {}
    public func load() async throws { throw StreamingASRError.notImplemented }
    public func start(epochID: UUID) throws { throw StreamingASRError.notImplemented }
    public func accept(_ samples: [Float], at globalSampleOffset: Int64) async throws -> WhisperSpeechUpdate {
        throw StreamingASRError.notImplemented
    }
    public func finish() async throws -> WhisperSpeechUpdate { throw StreamingASRError.notImplemented }
    public func cancel(epochID: UUID) async {}
    public func unload() async {}
    public func snapshot() -> CoreMLParakeetSnapshot {
        .init(phase: .unloaded, epochID: nil, computePolicy: nil, modelRevision: nil,
              acceptedSampleCount: 0, bufferedSampleCount: 0)
    }
}
