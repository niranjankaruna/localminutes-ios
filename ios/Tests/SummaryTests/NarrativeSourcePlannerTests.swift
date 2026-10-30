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

    func testBudgetUsesSelectedContextAndScalesOutputWithActualPromptTokens() async throws {
        for context in [4_096, 32_768, 131_072, 262_144] {
            let budget = try NarrativeSummaryBudget(contextTokenLimit: context, outputTokenLimit: min(context / 2, 16_384))
            XCTAssertEqual(budget.contextTokens, context)
        }
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 32_768, outputTokenLimit: 16_384)
        let short = try await budget.outputTokens(prompt: "short", tokenizer: { _ in 500 })
        let hour = try await budget.outputTokens(prompt: "hour", tokenizer: { _ in 14_000 })
        XCTAssertEqual(short, 512)
        XCTAssertEqual(hour, 3_500)
        let limited = try NarrativeSummaryBudget(contextTokenLimit: 32_768, outputTokenLimit: 2_048)
        let capped = try await limited.outputTokens(prompt: "hour", tokenizer: { _ in 14_000 })
        XCTAssertEqual(capped, 2_048)
    }

    func testExactTokenBoundaryIncludesOutputAndSafetyAllowance() async throws {
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 512)
        let maximumInput = budget.contextTokens - budget.outputTokenLimit - budget.safetyTokens
        let accepted = try await budget.outputTokens(prompt: "x", tokenizer: { _ in maximumInput - 1 })
        XCTAssertEqual(accepted, 512)
        for count in [maximumInput, 4_096, Int.max] {
            do {
                _ = try await budget.outputTokens(prompt: "x", tokenizer: { _ in count })
                XCTFail("Do not truncate input or output to squeeze a request into the window")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .contextExceeded) }
        }
        for count in [0, -1] {
            do {
                _ = try await budget.outputTokens(prompt: "x", tokenizer: { _ in count })
                XCTFail("Token counts must be positive")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidTokenCount) }
        }
    }

    func testInvalidSelectedModelLimitsAreRejected() {
        for (context, output) in [(0, 1), (4_096, 0), (4_096, 4_096), (32_768, 32_768)] {
            XCTAssertThrowsError(try NarrativeSummaryBudget(contextTokenLimit: context, outputTokenLimit: output)) {
                XCTAssertEqual($0 as? NarrativeSummaryError, .invalidConfiguration)
            }
        }
    }
}
