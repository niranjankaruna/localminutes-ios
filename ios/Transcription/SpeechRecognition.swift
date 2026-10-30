import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

public enum SpeechRecognitionError: Error, Equatable, Sendable {
    case invalidModel, noActiveStream, alreadyStarted, finished, cancelled, invalidSamples
    case discontinuity(expected: Int64, actual: Int64)
}

public enum SpeechRecognitionPhase: Equatable, Sendable {
    case unloaded, ready, streaming, finished, cancelled
}

public struct SpeechSegment: Equatable, Sendable {
    public let id: UUID
    public let startSample: Int64
    public let endSample: Int64
    public let text: String
    public init(id: UUID, startSample: Int64, endSample: Int64, text: String) {
        self.id = id; self.startSample = startSample; self.endSample = endSample; self.text = text
    }
}

public struct SpeechUpdate: Equatable, Sendable {
    public let epochID: UUID
    public let partial: String
    /// Newly finalized segments only; finishing an epoch does not repeat them.
    public let finalized: [SpeechSegment]
    public init(epochID: UUID, partial: String, finalized: [SpeechSegment]) {
        self.epochID = epochID; self.partial = partial; self.finalized = finalized
    }
}

/// The audio contract shared by capture and recovery. Adapters receive mono,
/// normalized Float32 PCM and report ranges in the original sample timeline.
public struct SpeechModelCapabilities: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let maximumInputSampleCount: Int
    public let producesPartialResults: Bool

    public init(sampleRate: Int = 16_000, channelCount: Int = 1,
                maximumInputSampleCount: Int, producesPartialResults: Bool) {
        self.sampleRate = sampleRate; self.channelCount = channelCount
        self.maximumInputSampleCount = maximumInputSampleCount
        self.producesPartialResults = producesPartialResults
    }
}

public struct SpeechModelSnapshot: Equatable, Sendable {
    public let phase: SpeechRecognitionPhase
    public let epochID: UUID?
    public let modelRevision: String?
    public let acceptedSampleCount: Int64
    public let bufferedSampleCount: Int

    public init(phase: SpeechRecognitionPhase, epochID: UUID?, modelRevision: String?,
                acceptedSampleCount: Int64, bufferedSampleCount: Int) {
        self.phase = phase; self.epochID = epochID; self.modelRevision = modelRevision
        self.acceptedSampleCount = acceptedSampleCount; self.bufferedSampleCount = bufferedSampleCount
    }
}

/// Application-facing speech interface. Loading must honor task cancellation;
/// unload must wait for native work to settle before releasing model resources.
/// Capture/replay require 16 kHz mono and accept input chunks up to 3,200 samples.
/// Each start begins a new sample timeline at zero. finish emits only remaining
/// finalized segments and is idempotent; cancel must affect only its epoch.
public protocol SpeechModelRuntime: Sendable {
    var profile: HuggingFaceRuntimeProfile { get }
    var capabilities: SpeechModelCapabilities { get }
    func load() async throws
    func start(epochID: UUID) async throws
    func accept(_ samples: [Float], at globalSampleOffset: Int64) async throws -> SpeechUpdate
    func finish() async throws -> SpeechUpdate
    func cancel(epochID: UUID) async
    func unload() async
    func runtimeSnapshot() async -> SpeechModelSnapshot
}

/// Construction is separate from load so the owner can retain the runtime for
/// cleanup even when native loading fails or is cancelled.
public typealias SpeechModelRuntimeFactory = @Sendable (VerifiedModel) throws -> any SpeechModelRuntime

/// The composition boundary for speech engines. New adapters are registered
/// here; live capture and recovered-audio replay only consume the interface.
public enum SpeechModelRuntimeRegistry {
    public static func makeRuntime(for model: VerifiedModel) throws -> any SpeechModelRuntime {
        guard model.manifest.purpose == .speechRecognition,
              (try? ParakeetModelPack.configuration(for: model.manifest)) != nil else {
            throw SpeechRecognitionError.invalidModel
        }
        return ParakeetSpeechAdapter(files: .init(directory: model.directoryURL, manifest: model.manifest))
    }
}
