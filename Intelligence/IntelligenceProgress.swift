import Foundation
#if SWIFT_PACKAGE
import LocalMinutesSummary
#endif

/// Operational progress only: no meeting titles, text or questions leave the
/// inference session when presenting system background-task progress.
public enum IntelligenceProgress: Equatable, Sendable {
    case preparing
    case loadingModel(completedBytes: Int64, totalBytes: Int64)
    case planningSummary(completed: Int, total: Int, pass: Int)
    case summaryChunks(completed: Int, total: Int)
    case answering
    case generating(SummaryGenerationProgress)
    case generationStarted
    case recoveringSummary
    case consolidatingSummary(completed: Int, total: Int)
    case saving

    public var message: String {
        switch self {
        case .preparing: return "Preparing the selected model…"
        case .loadingModel: return "Checking the selected model…"
        case .planningSummary: return "Preparing transcript sections and shared context…"
        case .summaryChunks(let completed, let total):
            return completed < total ? "Summarizing section \(completed + 1) of \(total)…" : "Checking summary sources…"
        case .answering: return "Reading meeting evidence…"
        case .generating(.promptTokens): return "Reading meeting text…"
        case .generationStarted: return "Reading meeting text…"
        case .generating(.responseTokens): return "Writing a response…"
        case .recoveringSummary: return "Finishing this section with a shorter response…"
        case .consolidatingSummary: return "Combining meeting sections and checking context…"
        case .saving: return "Saving on this iPhone…"
        }
    }
}

public typealias IntelligenceProgressReporter = @Sendable (IntelligenceProgress) -> Void
