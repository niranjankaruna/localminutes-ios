// Minimal test-first interface. Keep native generation unchanged until the
// canonical-envelope assertions actually execute RED on the compatible host.
public enum SummaryPromptFormattingError: Error, Equatable, Sendable {
    case invalidByteLimit, promptTooLong
}

public enum SummaryPromptFormatter {
    public static func format(systemPrompt: String, userPrompt: String,
                              maximumUTF8Bytes: Int = 65_536) throws -> String {
        ""
    }
}
