import Foundation

/// Text extraction and ID selection have different token costs. Keep enough
/// slots for larger model budgets without exceeding grounded-result bounds.
enum SummaryOutputBudget {
    static func itemLimit(outputTokens: Int) -> Int {
        max(1, min(32, outputTokens / 512))
    }

    static func referenceTokens(itemCount: Int, outputTokens: Int) -> Int {
        min(outputTokens, max(256, 64 + min(128, max(0, itemCount)) * 12))
    }

    static func consolidatedItems(outputTokens: Int) -> Int {
        min(128, max(48, outputTokens / 128))
    }
}
