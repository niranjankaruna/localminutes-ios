import Foundation

public enum SummaryPromptFormattingError: Error, Equatable, Sendable {
    case invalidByteLimit, promptTooLong
}

public enum SummaryPromptFormatter {
    public static func format(systemPrompt: String, userPrompt: String,
                              maximumUTF8Bytes: Int = 65_536) throws -> String {
        guard maximumUTF8Bytes > 0 else { throw SummaryPromptFormattingError.invalidByteLimit }
        guard systemPrompt.utf8.count <= maximumUTF8Bytes,
              userPrompt.utf8.count <= maximumUTF8Bytes else {
            throw SummaryPromptFormattingError.promptTooLong
        }
        let system = systemPrompt.replacingOccurrences(of: "<|", with: "<\u{200B}|")
        let user = userPrompt.replacingOccurrences(of: "<|", with: "<\u{200B}|")
        let envelope = "<|im_start|>system\n\(system)<|im_end|>\n"
            + "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        guard envelope.utf8.count <= maximumUTF8Bytes else {
            throw SummaryPromptFormattingError.promptTooLong
        }
        return envelope
    }
}
