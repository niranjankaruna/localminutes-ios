import Foundation

/// Counts from completed native work. Response limits are budgets, not a
/// promise of the final response length; no generated text is exposed here.
public enum SummaryGenerationProgress: Equatable, Sendable {
    case promptTokens(completed: Int, total: Int)
    case responseTokens(completed: Int, limit: Int)
}

public typealias SummaryGenerationProgressReporter = @Sendable (SummaryGenerationProgress) -> Void

public enum SummaryWorkPhase: String, Equatable, Sendable {
    case indexing, organizing, writing, checking, correcting, overview

    public var message: String {
        switch self {
        case .indexing: "Finding meeting topics…"
        case .organizing: "Organizing related topics…"
        case .writing: "Writing the summary…"
        case .checking: "Checking facts and sources…"
        case .correcting: "Correcting the summary…"
        case .overview: "Writing the overview…"
        }
    }
}

/// A slice of the planned generation work, independent of output token ceilings.
/// Nested writers divide their own slice when the number of paragraphs is known.
public struct SummaryWorkProgress: Equatable, Sendable {
    public let phase: SummaryWorkPhase
    public let completedFraction: Double
    public let operationFraction: Double

    public init(phase: SummaryWorkPhase, completedFraction: Double, operationFraction: Double) {
        self.phase = phase
        self.completedFraction = completedFraction
        self.operationFraction = operationFraction
    }
}

struct SummaryWorkScope: Sendable {
    let report: (@Sendable (SummaryWorkProgress) -> Void)?
    var start: Double = 0
    var span: Double = 1

    func child(_ lower: Double, _ upper: Double) -> Self {
        .init(report: report, start: start + lower * span, span: (upper - lower) * span)
    }

    func begin(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start, operationFraction: span))
    }

    func complete(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start + span, operationFraction: 0))
    }
}
