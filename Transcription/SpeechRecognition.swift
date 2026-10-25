import Foundation

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
