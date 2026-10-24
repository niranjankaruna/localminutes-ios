import Foundation
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

/// TEST-FIRST STUB. No native initialization, PCM processing or inference exists
/// before meaningful hosted RED. Intended rolling cadence5s/window<=30s at16kHz.
public actor WhisperSpeechRecognizer {
    public static let sampleRate = 16_000
    public static let stepSamples = 80_000
    public static let maximumWindowSamples = 480_000
    private var epochID = UUID()
    public init(files: WhisperSpeechModelFiles) {}
    init(files: WhisperSpeechModelFiles, executionObserver: @escaping WhisperNativeExecutionObserver) {}
    public func load() throws {}
    public func start(epochID: UUID) throws { self.epochID = epochID }
    public func accept(_ samples: [Float], at globalSampleOffset: Int64) throws -> WhisperSpeechUpdate {
        .init(epochID: epochID, partial: "", finalized: [])
    }
    public func finish() throws -> WhisperSpeechUpdate { .init(epochID: epochID, partial: "", finalized: []) }
    public func cancel(epochID: UUID) {}
    public func unload() {}
    public func snapshot() -> WhisperSpeechSnapshot {
        .init(phase: .unloaded, epochID: nil, provider: nil, acceptedSampleCount: 0, bufferedSampleCount: 0)
    }
}
