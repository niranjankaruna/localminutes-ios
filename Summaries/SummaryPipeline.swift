import Foundation

public typealias SummaryMapJSONGenerator = @Sendable (String, StructuredJSONSchema, Int) async throws -> String

public enum SummaryPipelinePhase: Equatable, Sendable { case idle, running, completed, failed, cancelled }

public struct SummaryPipelineSnapshot: Equatable, Sendable {
    public let phase: SummaryPipelinePhase
    public let meetingID: UUID?
    public let result: GroundedSummary?
    public init(phase: SummaryPipelinePhase, meetingID: UUID?, result: GroundedSummary?) {
        self.phase = phase; self.meetingID = meetingID; self.result = result
    }
}

public enum SummaryPipelineError: Error, Equatable, Sendable { case invalidConfiguration, alreadyRunning }

/// Draft test-first orchestration boundary. Release closures must call the
/// leased real runtime; unit tests double only tokenizer/generated JSON edges.
public actor SummaryPipeline {
    private let modelRevision: String
    private let promptVersion: String
    private let contextTokenLimit: Int
    private let reservedOutputTokens: Int
    private let tokenizer: SummaryTokenCounter
    private let generator: SummaryMapJSONGenerator

    public init(modelRevision: String, promptVersion: String = "grounded-map-v1",
                contextTokenLimit: Int = 4_096, reservedOutputTokens: Int = 1_024,
                tokenizer: @escaping SummaryTokenCounter, generator: @escaping SummaryMapJSONGenerator) {
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
        self.tokenizer = tokenizer; self.generator = generator
    }

    public func summarize(selectedMeetingID: UUID, source: GroundedSummarySource) async throws -> GroundedSummary {
        try Task.checkCancellation()
        return GroundedSummary(meetingID: selectedMeetingID, summaryPoints: [], decisions: [], actions: [])
    }

    public func snapshot() -> SummaryPipelineSnapshot {
        .init(phase: .idle, meetingID: nil, result: nil)
    }
}
