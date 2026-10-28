import Foundation

/// Counts from completed native work. Response limits are budgets, not a
/// promise of the final response length; no generated text is exposed here.
public enum SummaryGenerationProgress: Equatable, Sendable {
    case promptTokens(completed: Int, total: Int)
    case responseTokens(completed: Int, limit: Int)
}

public typealias SummaryGenerationProgressReporter = @Sendable (SummaryGenerationProgress) -> Void
