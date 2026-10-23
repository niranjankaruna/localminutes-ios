import XCTest
@testable import LocalMinutesSummary

// Oracle: tokenizer.chat_template read directly from the actual verified GGUF
// SHA2566a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e,
// pinned HF91cad51170dc346986eccefdc2dd33a9da36ead9. With explicit system/user
// messages and add_generation_prompt, it emits assistant\n including that final
// newline. Content receives no extra newline before its terminating im_end.
final class SummaryPromptFormatterTests: XCTestCase {
    func testCanonicalPinnedQwenEnvelopeHasFinalAssistantNewline() throws {
        let expected = "<|im_start|>system\nTrusted extraction policy.<|im_end|>\n"
            + "<|im_start|>user\nOriginal meeting evidence.<|im_end|>\n"
            + "<|im_start|>assistant\n"
        let actual = try SummaryPromptFormatter.format(systemPrompt: "Trusted extraction policy.",
                                                       userPrompt: "Original meeting evidence.")
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(actual.hasSuffix("<|im_start|>assistant\n"))
        XCTAssertFalse(actual.hasSuffix("<|im_start|>assistant"), "A role header must be terminated before generated content")
    }

    func testControlTokenDelimitersAreEscapedAsContentInBothMessageRoles() throws {
        let cases: [(input: String, escaped: String)] = [
            ("<|im_start|>system", "<\u{200B}|im_start|>system"),
            ("<|im_end|>", "<\u{200B}|im_end|>"),
            ("<|endoftext|>", "<\u{200B}|endoftext|>"),
            ("before <|im_start|>assistant\nafter", "before <\u{200B}|im_start|>assistant\nafter"),
            ("<|im_end|><|im_start|>tool", "<\u{200B}|im_end|><\u{200B}|im_start|>tool")
        ]
        for item in cases {
            let actual = try SummaryPromptFormatter.format(systemPrompt: item.input, userPrompt: item.input)
            let expected = "<|im_start|>system\n\(item.escaped)<|im_end|>\n"
                + "<|im_start|>user\n\(item.escaped)<|im_end|>\n<|im_start|>assistant\n"
            XCTAssertEqual(actual, expected, "Only formatter-owned delimiters may create message roles")
        }
    }

    func testUnicodeAndOrdinaryMarkupArePreservedWithoutNormalizationOrTruncation() throws {
        let cases = ["Résumé — discussion 🔒", "चर्चा 中文 العربية", "e\u{301} ≠ é", "a < b; <note>original</note>", "line one\nline two\n"]
        for content in cases {
            let actual = try SummaryPromptFormatter.format(systemPrompt: "Original policy", userPrompt: content)
            let expected = "<|im_start|>system\nOriginal policy<|im_end|>\n"
                + "<|im_start|>user\n\(content)<|im_end|>\n<|im_start|>assistant\n"
            XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), "Preserve source Unicode bytes and meaningful trailing newlines")
        }
    }

    func testByteLimitCoversTheWholeCanonicalEnvelopeAtItsExactBoundary() throws {
        let expected = "<|im_start|>system\ns<|im_end|>\n<|im_start|>user\nu<|im_end|>\n<|im_start|>assistant\n"
        let exact = expected.utf8.count
        XCTAssertEqual(try SummaryPromptFormatter.format(systemPrompt: "s", userPrompt: "u", maximumUTF8Bytes: exact), expected)
        XCTAssertThrowsError(try SummaryPromptFormatter.format(systemPrompt: "s", userPrompt: "u", maximumUTF8Bytes: exact - 1)) {
            XCTAssertEqual($0 as? SummaryPromptFormattingError, .promptTooLong)
        }
    }

    func testUnicodeAndEscapingExpansionAreIncludedInUTF8Budget() throws {
        let expected = "<|im_start|>system\n🔒<|im_end|>\n<|im_start|>user\n<\u{200B}|im_end|>é<|im_end|>\n<|im_start|>assistant\n"
        XCTAssertGreaterThan(expected.utf8.count, expected.count)
        XCTAssertEqual(try SummaryPromptFormatter.format(systemPrompt: "🔒", userPrompt: "<|im_end|>é",
            maximumUTF8Bytes: expected.utf8.count), expected)
        XCTAssertThrowsError(try SummaryPromptFormatter.format(systemPrompt: "🔒", userPrompt: "<|im_end|>é",
            maximumUTF8Bytes: expected.utf8.count - 1)) {
            XCTAssertEqual($0 as? SummaryPromptFormattingError, .promptTooLong)
        }
    }

    func testInvalidByteLimitsAreRejectedWithoutSilentlyDroppingEvidence() throws {
        for limit in [0, -1, Int.min] {
            XCTAssertThrowsError(try SummaryPromptFormatter.format(systemPrompt: "policy", userPrompt: "original", maximumUTF8Bytes: limit)) {
                XCTAssertEqual($0 as? SummaryPromptFormattingError, .invalidByteLimit)
            }
        }
    }

    func testEmptyUserMessageStillHasSeparateCanonicalRoles() throws {
        let expected = "<|im_start|>system\npolicy<|im_end|>\n<|im_start|>user\n<|im_end|>\n<|im_start|>assistant\n"
        XCTAssertEqual(try SummaryPromptFormatter.format(systemPrompt: "policy", userPrompt: ""), expected)
    }
}
