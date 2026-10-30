import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// The selected model supplies both hard limits. The response allowance grows
/// with the actual prompt, rather than reserving a fixed working context.
struct NarrativeSummaryBudget: Sendable {
    let contextTokens: Int
    let outputTokenLimit: Int
    let safetyTokens = 64

    init(contextTokenLimit: Int, outputTokenLimit: Int) throws {
        guard (512...SummaryContextWindow.maximumSupportedTokens).contains(contextTokenLimit),
              (1...SummaryContextWindow.maximumSupportedOutputTokens).contains(outputTokenLimit),
              outputTokenLimit < contextTokenLimit else {
            throw NarrativeSummaryError.invalidConfiguration
        }
        self.contextTokens = contextTokenLimit
        self.outputTokenLimit = outputTokenLimit
    }

    func outputTokens(prompt: String, tokenizer: SummaryTokenCounter) async throws -> Int {
        try Task.checkCancellation()
        guard prompt.utf8.count <= SummaryContextWindow.maximumPromptUTF8Bytes else {
            throw NarrativeSummaryError.contextExceeded
        }
        let inputTokens = try await tokenizer(prompt)
        try Task.checkCancellation()
        guard inputTokens > 0 else { throw NarrativeSummaryError.invalidTokenCount }
        // Estimate a concise summary at one quarter of the input. Small meetings
        // still need room for the overview, minutes and citation JSON. This is a
        // maximum response allowance, not a requested length or guaranteed fit.
        let outputTokens = min(outputTokenLimit, max(512, inputTokens / 4))
        guard inputTokens < contextTokens - outputTokens - safetyTokens else {
            throw NarrativeSummaryError.contextExceeded
        }
        return outputTokens
    }
}
