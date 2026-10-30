import Foundation

public struct NarrativeSummaryPipelineSnapshot: Equatable, Sendable {
    public let phase: SummaryPipelinePhase
    public let meetingID: UUID?
    public let result: NarrativeSummary?
}

/// One request containing the complete transcript. Input, generation and
/// validation failures are returned to the caller without retries or fallbacks.
public actor AdaptiveSummaryPipeline {
    public static let currentPromptVersion = "narrative-v5"
    private let modelRevision: String
    private let promptVersion: String
    private let contextTokenLimit: Int
    private let reservedOutputTokens: Int
    private let tokenizer: SummaryTokenCounter
    private let generator: SummaryMapJSONGenerator
    private let planningProgress: (@Sendable (Int, Int, Int) -> Void)?
    private let workProgress: (@Sendable (SummaryWorkProgress) -> Void)?
    private var state = NarrativeSummaryPipelineSnapshot(phase: .idle, meetingID: nil, result: nil)

    public init(modelRevision: String, promptVersion: String = AdaptiveSummaryPipeline.currentPromptVersion,
                contextTokenLimit: Int, reservedOutputTokens: Int,
                tokenizer: @escaping SummaryTokenCounter, generator: @escaping SummaryMapJSONGenerator,
                planningProgress: (@Sendable (Int, Int, Int) -> Void)? = nil,
                workProgress: (@Sendable (SummaryWorkProgress) -> Void)? = nil) {
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
        self.tokenizer = tokenizer; self.generator = generator
        self.planningProgress = planningProgress; self.workProgress = workProgress
    }

    public func snapshot() -> NarrativeSummaryPipelineSnapshot { state }

    public func summarize(selectedMeetingID: UUID, source: GroundedSummarySource) async throws -> NarrativeSummary {
        guard state.phase != .running else { throw NarrativeSummaryError.alreadyRunning }
        state = .init(phase: .running, meetingID: selectedMeetingID, result: nil)
        do {
            try Task.checkCancellation()
            let validation = try SummarySourceValidation(selectedMeetingID: selectedMeetingID, source: source, limits: .init())
            let provenance = SummaryGenerationProvenance(modelRevision: modelRevision, promptVersion: promptVersion, mapIndex: 0)
            try validation.provenance(provenance)
            let budget = try NarrativeSummaryBudget(contextTokenLimit: contextTokenLimit, outputTokenLimit: reservedOutputTokens)
            planningProgress?(0, source.segments.count, 1)
            let units = try NarrativeSourcePlanner.units(source: source)
            guard !units.isEmpty else { throw NarrativeSummaryError.invalidResponse }
            planningProgress?(source.segments.count, source.segments.count, 1)
            let writer = NarrativeSummaryWriter(tokenizer: tokenizer, generator: generator, budget: budget)
            let draft = try await writer.draft(units: units, notes: source.originalManualNotes,
                progress: SummaryWorkScope(report: workProgress))

            let byID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
            func paragraph(_ value: NarrativeDraftParagraph) throws -> NarrativeSummaryParagraph {
                guard !value.sourceIDs.isEmpty, value.sourceIDs.allSatisfy({ byID[$0] != nil }) else {
                    throw NarrativeSummaryError.unsupportedEvidence
                }
                var seen: Set<GroundedEvidenceKey> = []
                let evidence = value.sourceIDs.flatMap { byID[$0]!.evidence }
                    .filter { seen.insert(GroundedEvidenceKey($0)).inserted }
                    .sorted(by: SummarySourceValidation.evidenceLess)
                return .init(text: value.text, evidence: evidence)
            }
            let result = try NarrativeSummary(meetingID: selectedMeetingID, overview: paragraph(draft.overview),
                bullets: draft.bullets.map(paragraph), provenance: provenance)
            try Task.checkCancellation()
            state = .init(phase: .completed, meetingID: selectedMeetingID, result: result)
            return result
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            state = .init(phase: cancelled ? .cancelled : .failed, meetingID: selectedMeetingID, result: nil)
            if cancelled { throw CancellationError() }
            throw error
        }
    }
}
