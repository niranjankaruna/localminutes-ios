import Foundation

/// Counts from completed native work. Response limits are budgets, not a
/// promise of the final response length; no generated text is exposed here.
public enum SummaryGenerationProgress: Equatable, Sendable {
    case promptTokens(completed: Int, total: Int)
    case responseTokens(completed: Int, limit: Int)
}

public typealias SummaryGenerationProgressReporter = @Sendable (SummaryGenerationProgress) -> Void

public enum SummaryWorkPhase: String, Equatable, Sendable {
    case indexing, organizing, writing, checking, correcting, overview, checkpointing

    public var message: String {
        switch self {
        case .indexing: "Reading transcript"
        case .organizing: "Organizing the discussion"
        case .writing: "Writing the summary"
        case .checking: "Checking facts and sources"
        case .correcting: "Correcting the summary"
        case .overview: "Writing the overview"
        case .checkpointing: "Saving reading progress"
        }
    }

    public var explanation: String {
        switch self {
        case .indexing: "Reading the transcript before drafting your summary. Parts refer to transcript sections, not a count of topics."
        case .organizing: "Connecting related discussion across the transcript."
        case .writing: "Turning the discussion into bullet points for your overview and meeting minutes."
        case .checking: "Comparing the drafted points with the transcript before saving."
        case .correcting: "Revising a point that did not match its source."
        case .overview: "Writing a brief overview of what the meeting was about."
        case .checkpointing: "Keeping completed reading on this iPhone so it can be resumed."
        }
    }
}

/// A slice of the planned generation work, independent of output token ceilings.
/// Nested writers divide their own slice when the number of paragraphs is known.
public struct SummaryWorkProgress: Equatable, Sendable {
    public let phase: SummaryWorkPhase
    public let completedFraction: Double
    public let operationFraction: Double
    public let item: Int?
    public let totalItems: Int?
    public let isRetry: Bool

    public init(phase: SummaryWorkPhase, completedFraction: Double, operationFraction: Double,
                item: Int? = nil, totalItems: Int? = nil, isRetry: Bool = false) {
        self.phase = phase
        self.completedFraction = completedFraction
        self.operationFraction = operationFraction
        self.item = item; self.totalItems = totalItems
        self.isRetry = isRetry
    }

    public var title: String {
        guard isRetry else { return phase.message }
        switch phase {
        case .indexing: return "Reading a smaller transcript part"
        case .writing: return "Writing a smaller summary part"
        case .overview: return "Writing a shorter overview"
        case .checking: return "Retrying the source check"
        case .correcting: return "Writing a shorter correction"
        default: return phase.message
        }
    }

    /// Render separately from the phase so the total cannot be truncated at
    /// the end of a long status sentence. Include even a single known part.
    public var counterText: String? {
        guard let item, let totalItems, totalItems > 0, item > 0, item <= totalItems else { return nil }
        let unit = phase == .indexing || phase == .checkpointing ? "Part" : "Discussion"
        return "\(unit) \(item) of \(totalItems)"
    }

    public var message: String {
        guard let item, let totalItems, totalItems > 1, item > 0, item <= totalItems else { return title }
        let unit = phase == .indexing || phase == .checkpointing ? "part" : "discussion"
        return title + " · \(unit) \(item) of \(totalItems)"
    }

    public var explanation: String {
        guard isRetry else { return phase.explanation }
        if phase == .indexing {
            return "The model did not complete the last pass. Retrying smaller parts while keeping the full transcript."
        }
        return "The model's response was incomplete or invalid. Retrying with shorter responses or smaller parts while keeping the transcript and source checks."
    }
}

struct SummaryWorkScope: Sendable {
    let report: (@Sendable (SummaryWorkProgress) -> Void)?
    var start: Double = 0
    var span: Double = 1
    var item: Int? = nil
    var totalItems: Int? = nil
    var isRetry = false

    func child(_ lower: Double, _ upper: Double) -> Self {
        .init(report: report, start: start + lower * span, span: (upper - lower) * span,
            item: item, totalItems: totalItems, isRetry: isRetry)
    }

    func counted(item: Int, total: Int) -> Self {
        .init(report: report, start: start, span: span, item: item, totalItems: total, isRetry: isRetry)
    }

    func retrying() -> Self {
        .init(report: report, start: start, span: span, item: item, totalItems: totalItems, isRetry: true)
    }

    func begin(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start, operationFraction: span,
            item: item, totalItems: totalItems, isRetry: isRetry))
    }

    func complete(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start + span, operationFraction: 0,
            item: item, totalItems: totalItems, isRetry: isRetry))
    }
}
