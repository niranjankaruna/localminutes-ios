import Foundation

/// Explicit formats preserve prior behavior; automatic validates actual GGUF
/// architecture/template metadata against the supported canonical envelopes.
public enum LocalSummaryChatFormat: Equatable, Sendable { case qwen, phi3, automatic }

public enum Phi3SummaryPromptFormatter {
    /// The pinned Phi GGUF template handles user/assistant turns only. Fold the
    /// policy into that user content; native add_special supplies its BOS token.
    public static func format(systemPrompt: String, userPrompt: String,
                              maximumUTF8Bytes: Int = 65_536) throws -> String {
        guard maximumUTF8Bytes > 0 else { throw SummaryPromptFormattingError.invalidByteLimit }
        guard systemPrompt.utf8.count <= maximumUTF8Bytes,
              userPrompt.utf8.count <= maximumUTF8Bytes else {
            throw SummaryPromptFormattingError.promptTooLong
        }
        let system = escape(systemPrompt)
        let user = escape(userPrompt)
        let envelope = "<|user|>\n\(system)\n\n\(user)<|end|>\n<|assistant|>\n"
        guard envelope.utf8.count <= maximumUTF8Bytes else { throw SummaryPromptFormattingError.promptTooLong }
        return envelope
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "<|", with: "<\u{200B}|")
            .replacingOccurrences(of: "<s>", with: "<\u{200B}s>")
    }
}
