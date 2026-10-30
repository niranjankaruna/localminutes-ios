import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class NarrativeSummaryWriterTests: XCTestCase {
    func testSingleRequestContainsAllOriginalTextAndReturnsValidatedProse() async throws {
        let boundary = WriterBoundary(reply: Self.valid)
        let result = try await writer(boundary).draft(units: units, notes: "Keep the condition.")
        XCTAssertEqual(result.bullets[0].sourceIDs, [41, 73])
        XCTAssertEqual(result.overview.sourceIDs, [73])
        let prompts = await boundary.prompts
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(prompts[0].contains(units[0].text))
        XCTAssertTrue(prompts[0].contains(units[1].text))
        XCTAssertTrue(prompts[0].contains("Keep the condition."))
        XCTAssertFalse(prompts[0].contains("NARRATIVE_REVIEW"))
        let maxima = await boundary.maxima
        XCTAssertEqual(maxima, [3_000])
    }

    func testMalformedEmptyUnknownAndForgedExcerptResponsesFailWithoutRetry() async throws {
        let invalid: [(String, NarrativeSummaryError)] = [
            ("not JSON", .invalidResponse),
            (#"{"bullets":[],"overview":{"text":"Overview","source_ids":[41]}}"#, .invalidResponse),
            (#"{"bullets":[{"text":"","source_ids":[41]}],"overview":{"text":"Overview","source_ids":[41]}}"#, .invalidResponse),
            (#"{"bullets":[{"text":"Point","source_ids":[]}],"overview":{"text":"Overview","source_ids":[41]}}"#, .unsupportedEvidence),
            (#"{"bullets":[{"text":"Point","source_ids":[999]}],"overview":{"text":"Overview","source_ids":[41]}}"#, .unsupportedEvidence),
            (#"{"bullets":[{"text":"Point","source_ids":[41],"source_excerpt":true}],"overview":{"text":"Overview","source_ids":[41]}}"#, .invalidResponse)
        ]
        for (reply, expected) in invalid {
            let boundary = WriterBoundary(reply: reply)
            do {
                _ = try await writer(boundary).draft(units: units, notes: "")
                XCTFail("Invalid output must be rejected")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, expected) }
            let calls = await boundary.prompts
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testRepeatedValidReferencesAreDeduplicatedLocally() async throws {
        let boundary = WriterBoundary(reply: Self.valid.replacingOccurrences(of: "[41,73]", with: "[41,41,73]"))
        let result = try await writer(boundary).draft(units: units, notes: "")
        XCTAssertEqual(result.bullets[0].sourceIDs, [41, 73])
        let calls = await boundary.prompts
        XCTAssertEqual(calls.count, 1)
    }

    func testOutputAllowanceUsesSelectedModelCeiling() async throws {
        let boundary = WriterBoundary(reply: Self.valid)
        _ = try await writer(boundary, outputLimit: 1_024).draft(units: units, notes: "")
        let maxima = await boundary.maxima
        XCTAssertEqual(maxima, [1_024])
    }

    func testInvalidTokenizerCountFailsBeforeGeneration() async throws {
        let boundary = WriterBoundary(reply: Self.valid)
        do {
            _ = try await writer(boundary, inputTokens: 0).draft(units: units, notes: "")
            XCTFail("Invalid token counts must not admit a request")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidTokenCount) }
        let calls = await boundary.prompts
        XCTAssertTrue(calls.isEmpty)
    }

    func testInvalidSourcesFailBeforeTokenizationOrGeneration() async throws {
        let boundary = WriterBoundary(reply: Self.valid)
        let instance = NarrativeSummaryWriter(tokenizer: { _ in
            XCTFail("Invalid source IDs must fail before tokenization"); return 500
        }, generator: { try await boundary.generate($0, $1, $2) },
           budget: try .init(contextTokenLimit: 32_768, outputTokenLimit: 16_384))
        do {
            _ = try await instance.draft(units: [units[0], units[0]], notes: "")
            XCTFail("Duplicate source IDs cannot be admitted")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .unsupportedEvidence) }
        let calls = await boundary.prompts
        XCTAssertTrue(calls.isEmpty)
    }

    private static let valid = """
    {"bullets":[{"text":"A supplier delay moved the launch to Tuesday, subject to approval.","source_ids":[41,73]}],
    "overview":{"text":"The team revised the launch plan.\\nApproval remains pending.","source_ids":[73]}}
    """

    private var units: [NarrativeSourceUnit] {
        [.init(id: 41, segments: [.init(id: "first", startSample: 0, endSample: 80_000,
            text: "We proposed Friday for launch.")]),
         .init(id: 73, segments: [.init(id: "last", startSample: 80_000, endSample: 160_000,
            text: "The supplier is late. Change the proposal to Tuesday, if security approves. Approval is pending.")])]
    }

    private func writer(_ boundary: WriterBoundary, inputTokens: Int = 12_000,
                        outputLimit: Int = 16_384) throws -> NarrativeSummaryWriter {
        .init(tokenizer: { _ in inputTokens }, generator: { try await boundary.generate($0, $1, $2) },
              budget: try .init(contextTokenLimit: 32_768, outputTokenLimit: outputLimit))
    }
}

private actor WriterBoundary {
    let reply: String
    private(set) var prompts: [String] = []
    private(set) var maxima: [Int] = []
    init(reply: String) { self.reply = reply }
    func generate(_ prompt: String, _ schema: StructuredJSONSchema, _ maximum: Int) throws -> String {
        prompts.append(prompt); maxima.append(maximum)
        _ = try schema.grammar()
        return reply
    }
}

