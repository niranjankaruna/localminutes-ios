import Foundation

public struct GroundedSummarySource: Equatable, Sendable {
    public let meetingID: UUID
    public let segments: [SummaryEvidenceSegment]
    public let originalManualNotes: String
    public init(meetingID: UUID, segments: [SummaryEvidenceSegment], originalManualNotes: String) {
        self.meetingID = meetingID; self.segments = segments; self.originalManualNotes = originalManualNotes
    }
}

public struct SummaryGenerationProvenance: Equatable, Sendable {
    public let modelRevision: String
    public let promptVersion: String
    public let mapIndex: Int
    public init(modelRevision: String, promptVersion: String, mapIndex: Int) {
        self.modelRevision = modelRevision; self.promptVersion = promptVersion; self.mapIndex = mapIndex
    }
}

public struct GroundedSummaryEvidence: Equatable, Sendable {
    public let sourceID: String
    public let startSample: Int64
    public let endSample: Int64
    public let quote: String
    public init(sourceID: String, startSample: Int64, endSample: Int64, quote: String) {
        self.sourceID = sourceID; self.startSample = startSample; self.endSample = endSample; self.quote = quote
    }
}

public struct GroundedSummaryLimits: Equatable, Sendable {
    public let maximumJSONBytes: Int
    public let maximumItems: Int
    public let maximumQuoteUTF8Bytes: Int
    public init(maximumJSONBytes: Int = 1_048_576, maximumItems: Int = 128, maximumQuoteUTF8Bytes: Int = 4_096) {
        self.maximumJSONBytes = maximumJSONBytes; self.maximumItems = maximumItems
        self.maximumQuoteUTF8Bytes = maximumQuoteUTF8Bytes
    }
}

public enum GroundedSummaryError: Error, Equatable, Sendable {
    case invalidSource, invalidProvenance, invalidLimits, meetingMismatch
}

