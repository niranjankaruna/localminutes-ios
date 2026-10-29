import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// A working context is an execution policy, not a claim about model quality.
/// The conservative default bounds phone KV-cache use; a measured deployment
/// can supply a different ceiling without changing the model's hard limits.
struct NarrativeSummaryBudget: Sendable {
    let contextTokens: Int
    let writingTokens: Int
    let readingTokens: Int
    let checkingTokens: Int
    let safetyTokens: Int

    init(contextTokenLimit: Int, outputTokenLimit: Int, workingContextTokenLimit: Int? = nil) throws {
        guard (512...SummaryContextWindow.maximumSupportedTokens).contains(contextTokenLimit),
              (1...SummaryContextWindow.maximumSupportedOutputTokens).contains(outputTokenLimit),
              outputTokenLimit < contextTokenLimit,
              workingContextTokenLimit.map({ $0 >= 512 && $0 <= contextTokenLimit }) ?? true else {
            throw NarrativeSummaryError.invalidConfiguration
        }
        contextTokens = min(contextTokenLimit, workingContextTokenLimit ?? 8_192)
        writingTokens = min(outputTokenLimit, min(1_536, max(128, contextTokens / 4)))
        readingTokens = min(outputTokenLimit, min(1_024, max(128, contextTokens / 6)))
        checkingTokens = min(outputTokenLimit, min(512, max(96, contextTokens / 8)))
        safetyTokens = 64
    }

    func fits(prompt: String, outputTokens: Int, tokenizer: SummaryTokenCounter) async throws -> Bool {
        try Task.checkCancellation()
        guard outputTokens > 0, outputTokens < contextTokens,
              prompt.utf8.count <= SummaryContextWindow.maximumPromptUTF8Bytes else { return false }
        let count = try await tokenizer(prompt)
        try Task.checkCancellation()
        guard count > 0 else { throw NarrativeSummaryError.invalidTokenCount }
        return count < contextTokens - outputTokens - safetyTokens
    }
}
