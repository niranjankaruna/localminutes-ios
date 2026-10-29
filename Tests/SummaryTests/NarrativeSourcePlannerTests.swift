import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class NarrativeSourcePlannerTests: XCTestCase {
    func testAdjacentASRFragmentsCanBeReadTogetherWithoutChangingTheirEvidence() throws {
        let source = GroundedSummarySource(meetingID: UUID(), segments: [
            .init(id: "first", startSample: 0, endSample: 80_000, text: "We agreed to move the release"),
            .init(id: "second", startSample: 80_000, endSample: 160_000, text: "to Friday, provided security approves.")
        ], originalManualNotes: "")
        let units = try NarrativeSourcePlanner.units(source: source)
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].text, "We agreed to move the release to Friday, provided security approves.")
        XCTAssertEqual(units[0].segments, source.segments)
        XCTAssertEqual(units[0].evidence.map(\.quote), source.segments.map(\.text))
        XCTAssertEqual(units[0].evidence.map(\.startSample), [0, 80_000])
    }

    func testOversizedUnicodeSpeechPreservesEveryOriginalByteAndRange() throws {
        let text = String(repeating: "Café 📝 東京 — Keep this condition intact. ", count: 80)
        let source = GroundedSummarySource(meetingID: UUID(), segments: [
            .init(id: "long", startSample: 32_000, endSample: 960_000, text: text)
        ], originalManualNotes: "")
        let units = try NarrativeSourcePlanner.units(source: source, maximumUnitBytes: 256)
        XCTAssertGreaterThan(units.count, 1)
        XCTAssertEqual(units.map(\.id), Array(units.indices))
        let fragments = units.flatMap(\.segments)
        XCTAssertEqual(Data(fragments.map(\.text).joined().utf8), Data(text.utf8))
        XCTAssertTrue(units.allSatisfy { $0.text.utf8.count <= 256 })
        XCTAssertTrue(fragments.allSatisfy { $0.id == "long" && $0.startSample == 32_000 && $0.endSample == 960_000 })
        XCTAssertTrue(fragments.allSatisfy { Data(text.utf8).range(of: Data($0.text.utf8)) != nil })
    }

    func testLongSilenceDoesNotJoinUnrelatedUtterances() throws {
        let source = GroundedSummarySource(meetingID: UUID(), segments: [
            .init(id: "opening", startSample: 0, endSample: 80_000, text: "The opening discussion ended."),
            .init(id: "later", startSample: 400_000, endSample: 480_000, text: "A different subject follows.")
        ], originalManualNotes: "")
        let units = try NarrativeSourcePlanner.units(source: source)
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units.flatMap(\.segments), source.segments)
    }

    func testInvalidSourceIdentityOrderingAndWhitespaceFailBeforePlanning() throws {
        let meeting = UUID()
        for segments: [SummaryEvidenceSegment] in [
            [.init(id: "same", startSample: 0, endSample: 10, text: "One."),
             .init(id: "same", startSample: 10, endSample: 20, text: "Two.")],
            [.init(id: "one", startSample: 10, endSample: 20, text: "One."),
             .init(id: "two", startSample: 19, endSample: 30, text: "Two.")],
            [.init(id: "empty", startSample: 0, endSample: 10, text: " \n\t")]
        ] {
            XCTAssertThrowsError(try NarrativeSourcePlanner.units(source: .init(meetingID: meeting,
                segments: segments, originalManualNotes: ""))) {
                XCTAssertEqual($0 as? GroundedSummaryError, .invalidSource)
            }
        }
        let source = GroundedSummarySource(meetingID: meeting, segments: [], originalManualNotes: "")
        XCTAssertThrowsError(try SummarySourceValidation(selectedMeetingID: UUID(), source: source, limits: .init())) {
            XCTAssertEqual($0 as? GroundedSummaryError, .meetingMismatch)
        }
    }

    func testBudgetUsesCanonicalTokensAndIndependentStageAllowances() async throws {
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 32_768, outputTokenLimit: 8_192)
        XCTAssertLessThan(budget.writingTokens, 8_192, "Do not reserve the model's entire response ceiling for every stage")
        XCTAssertLessThan(budget.checkingTokens, budget.writingTokens)
        let maximumInput = budget.contextTokens - budget.writingTokens - budget.safetyTokens
        let fits = try await budget.fits(prompt: "short text with a large canonical envelope",
            outputTokens: budget.writingTokens, tokenizer: { _ in maximumInput - 1 })
        let full = try await budget.fits(prompt: "x", outputTokens: budget.writingTokens, tokenizer: { _ in maximumInput })
        XCTAssertTrue(fits)
        XCTAssertFalse(full, "Admission must use the real framed token count, not characters")
        do {
            _ = try await budget.fits(prompt: "x", outputTokens: budget.writingTokens, tokenizer: { _ in 0 })
            XCTFail("An invalid tokenizer count must not admit a request")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidTokenCount) }
        let small = try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 512)
        XCTAssertLessThanOrEqual(small.writingTokens, 512)
        XCTAssertLessThanOrEqual(small.readingTokens, 512)
        XCTAssertLessThanOrEqual(small.checkingTokens, 512)
    }

    func testWorkingContextPolicyCannotExceedTheSelectedModel() throws {
        XCTAssertThrowsError(try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 512,
            workingContextTokenLimit: 8_192))
        XCTAssertThrowsError(try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 4_096))
        let tuned = try NarrativeSummaryBudget(contextTokenLimit: 32_768, outputTokenLimit: 8_192,
            workingContextTokenLimit: 16_384)
        XCTAssertEqual(tuned.contextTokens, 16_384)
    }
}
