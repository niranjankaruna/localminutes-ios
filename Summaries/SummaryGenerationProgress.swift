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
    public let item: Int?
    public let totalItems: Int?

    public init(phase: SummaryWorkPhase, completedFraction: Double, operationFraction: Double,
                item: Int? = nil, totalItems: Int? = nil) {
        self.phase = phase
        self.completedFraction = completedFraction
        self.operationFraction = operationFraction
        self.item = item; self.totalItems = totalItems
    }

    public var message: String {
        guard let item, let totalItems, item > 0, item <= totalItems else { return phase.message }
        let unit = phase == .indexing ? "section" : "topic"
        return phase.message.replacingOccurrences(of: "…", with: "") + " — \(unit) \(item) of \(totalItems)…"
    }
}

struct SummaryWorkScope: Sendable {
    let report: (@Sendable (SummaryWorkProgress) -> Void)?
    var start: Double = 0
    var span: Double = 1
    var item: Int? = nil
    var totalItems: Int? = nil

    func child(_ lower: Double, _ upper: Double) -> Self {
        .init(report: report, start: start + lower * span, span: (upper - lower) * span,
            item: item, totalItems: totalItems)
    }

    func counted(item: Int, total: Int) -> Self {
        .init(report: report, start: start, span: span, item: item, totalItems: total)
    }

    func begin(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start, operationFraction: span, item: item, totalItems: totalItems))
    }

    func complete(_ phase: SummaryWorkPhase) {
        report?(.init(phase: phase, completedFraction: start + span, operationFraction: 0, item: item, totalItems: totalItems))
    }
}
