import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
import LocalMinutesSummary
#endif

public enum MeetingQuestionStatus: String, Codable, Equatable, Sendable {
    case supportedQuote = "supported_quote"
    case insufficientEvidence = "insufficient_evidence"
}

/// References the unchanged original segment, including ASR revision and global
/// sample positions. `quote` must be an exact UTF-8 substring of `source.text`.
public struct MeetingQuestionEvidence: Equatable, Sendable {
    public let source: StoredTranscriptSegment
    public let quote: String
    public init(source: StoredTranscriptSegment, quote: String) {
        self.source = source; self.quote = quote
    }
}

public struct MeetingQuestionAnswer: Equatable, Sendable {
    public let meetingID: UUID
    public let status: MeetingQuestionStatus
    public let evidence: [MeetingQuestionEvidence]
    public let modelRevision: String
    public let promptVersion: String
    public init(meetingID: UUID, status: MeetingQuestionStatus,
                evidence: [MeetingQuestionEvidence], modelRevision: String, promptVersion: String) {
        self.meetingID = meetingID; self.status = status; self.evidence = evidence
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
    }
}

public struct MeetingQuestionLimits: Equatable, Sendable {
    public let maximumQuestionUTF8Bytes: Int
    public let maximumEvidenceCount: Int
    public let maximumExcerptUTF8Bytes: Int
    public let contextTokenLimit: Int
    public let reservedOutputTokens: Int
    public init(maximumQuestionUTF8Bytes: Int = 2_048, maximumEvidenceCount: Int = 8,
                maximumExcerptUTF8Bytes: Int = 4_096, contextTokenLimit: Int = 4_096,
                reservedOutputTokens: Int = 192) {
        self.maximumQuestionUTF8Bytes = maximumQuestionUTF8Bytes
        self.maximumEvidenceCount = maximumEvidenceCount
        self.maximumExcerptUTF8Bytes = maximumExcerptUTF8Bytes
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
    }
}

public enum MeetingQuestionError: Error, Equatable, Sendable {
    case invalidConfiguration, emptyQuestion, questionTooLong
    case evidenceExceedsBudget, invalidJSON, unsupportedEvidence
}

public struct MeetingQuestionGenerationRequest: Sendable {
    public let meetingID: UUID
    public let question: String
    public let evidence: [StoredTranscriptSegment]
    public let prompt: String
    public let schema: StructuredJSONSchema
    public let promptTokenCount: Int
    public let maximumOutputTokens: Int
    public init(meetingID: UUID, question: String, evidence: [StoredTranscriptSegment],
                prompt: String, schema: StructuredJSONSchema, promptTokenCount: Int,
                maximumOutputTokens: Int) {
        self.meetingID = meetingID; self.question = question; self.evidence = evidence
        self.prompt = prompt; self.schema = schema; self.promptTokenCount = promptTokenCount
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public typealias MeetingQuestionGenerator = @Sendable (MeetingQuestionGenerationRequest) async throws -> String

/// Test-first seam ONLY: this declaration does not retrieve or generate.
/// Production adapters must use the actual pinned LocalSummaryRuntime for both
/// canonical prompt token counts and typed JSON generation.
public struct MeetingQuestionAnswerer: Sendable {
    private let modelRevision: String
    private let promptVersion: String

    public init(store: SQLiteMeetingStore, modelRevision: String,
                promptVersion: String = "meeting-qa-v1", limits: MeetingQuestionLimits = .init(),
                tokenCounter: @escaping SummaryTokenCounter,
                generator: @escaping MeetingQuestionGenerator) {
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
    }

    public func answer(meetingID: UUID, question: String) async throws -> MeetingQuestionAnswer {
        // Deliberate no-op for hosted behavioral RED. No working QA behavior.
        MeetingQuestionAnswer(meetingID: meetingID, status: .insufficientEvidence,
            evidence: [], modelRevision: modelRevision, promptVersion: promptVersion)
    }
}
