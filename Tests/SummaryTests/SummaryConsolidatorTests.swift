import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class SummaryConsolidatorTests: XCTestCase {
    func testSelectionRetainsFullTextEvidenceAndProvenanceWhenRankingUsesAPreview() async throws {
        let fixture = consolidationFixture()
        let calls = ConsolidationBoundary(response: #"{"keep":[0,0]}"#)
        let result = try await SummaryConsolidator(tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, $1, $2) }, contextTokenLimit: 4_096, report: nil)
            .combine([fixture.map], meetingID: fixture.source.meetingID, source: fixture.source)
        XCTAssertEqual(result.summaryPoints, Array(fixture.map.summaryPoints.prefix(1)))
        XCTAssertGreaterThan(try XCTUnwrap(result.summaryPoints.first).text.count, 160)
        let prompts = await calls.prompts
        XCTAssertEqual(prompts.count, 1)
        XCTAssertFalse(prompts[0].contains(fixture.source.segments[0].text), "Ranking uses a preview; selected output keeps the full original")
    }

    func testInvalidReferencesCannotInventOrReplaceGroundedFindings() async throws {
        for response in [#"{"keep":[-1]}"#, #"{"keep":[100]}"#, #"{"keep":[true]}"#,
                         #"{"keep":[0],"text":"invented"}"#] {
            let fixture = consolidationFixture()
            let calls = ConsolidationBoundary(response: response)
            do {
                _ = try await SummaryConsolidator(tokenizer: { _ in 20 }, generator: { try await calls.generate($0, $1, $2) },
                    contextTokenLimit: 4_096, report: nil)
                    .combine([fixture.map], meetingID: fixture.source.meetingID, source: fixture.source)
                XCTFail("Invalid final references must not publish a summary")
            } catch { XCTAssertEqual(error as? GroundedSummaryError, .invalidJSON) }
        }
    }

    func testUnsupportedIntermediateClaimsFailBeforeAnyFinalModelRequest() async throws {
        let fixture = consolidationFixture()
        let original = try XCTUnwrap(fixture.map.summaryPoints.first)
        let altered = GroundedSummaryPoint(text: "An unsupported conclusion.", evidence: original.evidence, provenance: original.provenance)
        let invalid = GroundedSummary(meetingID: fixture.source.meetingID, summaryPoints: [altered], decisions: [], actions: [])
        let calls = ConsolidationBoundary(response: #"{"keep":[0]}"#)
        do {
            _ = try await SummaryConsolidator(tokenizer: { _ in 20 }, generator: { try await calls.generate($0, $1, $2) },
                contextTokenLimit: 4_096, report: nil).combine([invalid], meetingID: fixture.source.meetingID, source: fixture.source)
            XCTFail("Unvalidated input must not reach final consolidation")
        } catch { XCTAssertEqual(error as? GroundedSummaryError, .unsupportedClaim) }
        let prompts = await calls.prompts
        XCTAssertTrue(prompts.isEmpty)
    }

    private func consolidationFixture() -> (source: GroundedSummarySource, map: GroundedSummary) {
        let meeting = UUID()
        let text = "The complete original finding preserves its final details: " + String(repeating: "cafe\u{301} 📝 ", count: 28) + "and its unchanged ending."
        let second = "A separate exact meeting finding."
        let source = GroundedSummarySource(meetingID: meeting,
            segments: [.init(id: "original", startSample: 32_000, endSample: 80_000, text: text),
                       .init(id: "second", startSample: 80_000, endSample: 96_000, text: second)], originalManualNotes: "")
        let point = GroundedSummaryPoint(text: text,
            evidence: [.init(sourceID: "original", startSample: 32_000, endSample: 80_000, quote: text)],
            provenance: [.init(modelRevision: String(repeating: "a", count: 40), promptVersion: SummaryPipeline.currentPromptVersion, mapIndex: 0)])
        let other = GroundedSummaryPoint(text: second,
            evidence: [.init(sourceID: "second", startSample: 80_000, endSample: 96_000, quote: second)],
            provenance: point.provenance)
        return (source, .init(meetingID: meeting, summaryPoints: [point, other], decisions: [], actions: []))
    }
}

private actor ConsolidationBoundary {
    let response: String
    private(set) var prompts: [String] = []
    init(response: String) { self.response = response }
    func generate(_ prompt: String, _ schema: StructuredJSONSchema, _ maximum: Int) -> String {
        prompts.append(prompt); return response
    }
}
