import Foundation

/// Operational progress only: no meeting titles, text or questions leave the
/// inference session when presenting system background-task progress.
public enum IntelligenceProgress: Equatable, Sendable {
    case preparing
    case summaryChunks(completed: Int, total: Int)
    case answering
    case saving
}

public typealias IntelligenceProgressReporter = @Sendable (IntelligenceProgress) -> Void
