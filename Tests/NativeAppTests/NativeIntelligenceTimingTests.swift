#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

@MainActor
final class NativeIntelligenceTimingTests: XCTestCase {
    func testDirectSummaryDoesNotJumpToNinetyBeforeWritingAndReviewsAdvanceSeparately() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryWork(.init(phase: .writing, completedFraction: 0, operationFraction: 0)), at: start)
        tracker.report(.summaryChunks(completed: 0, total: 1), at: start)
        tracker.report(.summaryChunks(completed: 1, total: 1), at: start)
        tracker.report(.consolidatingSummary(completed: 0, total: 1), at: start)
        XCTAssertEqual(tracker.display(at: start).percentage, 10)
        tracker.report(.summaryWork(.init(phase: .writing, completedFraction: 0, operationFraction: 0.45)), at: start)
        tracker.report(.generationStarted, at: start)
        tracker.report(.generating(.responseTokens(completed: 1_000, limit: 1_000)), at: start.advanced(by: .seconds(30)))
        XCTAssertLessThan(tracker.display(at: start).percentage, 50)
        tracker.report(.summaryWork(.init(phase: .checking, completedFraction: 0.45, operationFraction: 0.2)),
            at: start.advanced(by: .seconds(31)))
        let checking = tracker.progress.completedUnitCount
        tracker.report(.generationStarted, at: start.advanced(by: .seconds(31)))
        tracker.report(.generating(.promptTokens(completed: 200, total: 400)), at: start.advanced(by: .seconds(32)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, checking)
        XCTAssertEqual(tracker.detail, "Checking facts and sources…")
        tracker.report(.summaryWork(.init(phase: .checking, completedFraction: 1, operationFraction: 0)),
            at: start.advanced(by: .seconds(60)))
        XCTAssertEqual(tracker.display(at: start).percentage, 98)
        tracker.report(.saving, at: start.advanced(by: .seconds(61)))
        XCTAssertEqual(tracker.display(at: start).percentage, 99)
        tracker.finish(success: true, at: start.advanced(by: .seconds(62)))
        XCTAssertEqual(tracker.display(at: start).percentage, 100)
    }

    func testSummaryEstimateUsesWholeCallsAndDoesNotLearnFromRecoveredCheckpoints() throws {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryWork(.init(phase: .indexing, completedFraction: 0.25, operationFraction: 0)), at: start)
        XCTAssertNil(tracker.display(at: start).remainingSeconds)
        tracker.report(.summaryWork(.init(phase: .writing, completedFraction: 0.3, operationFraction: 0.1)), at: start)
        tracker.report(.generating(.promptTokens(completed: 0, total: 100)), at: start)
        tracker.report(.generating(.promptTokens(completed: 100, total: 100)), at: start.advanced(by: .seconds(4)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(4))).remainingSeconds)
        tracker.report(.summaryWork(.init(phase: .checking, completedFraction: 0.4, operationFraction: 0.1)),
            at: start.advanced(by: .seconds(20)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(20))).remainingSeconds,
            "One completed call is too little evidence for a whole-meeting ETA")
        tracker.report(.summaryWork(.init(phase: .checking, completedFraction: 0.5, operationFraction: 0.1)),
            at: start.advanced(by: .seconds(40)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(40))).remainingSeconds)
        tracker.report(.summaryWork(.init(phase: .writing, completedFraction: 0.6, operationFraction: 0.1)),
            at: start.advanced(by: .seconds(60)))
        let estimate = try XCTUnwrap(tracker.display(at: start.advanced(by: .seconds(60))).remainingSeconds)
        XCTAssertLessThanOrEqual(abs(estimate - 83), 1)
        let later = try XCTUnwrap(tracker.display(at: start.advanced(by: .seconds(65))).remainingSeconds)
        XCTAssertEqual(later, estimate - 5, "A calibrated deadline counts down steadily")
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(80))).remainingSeconds,
            "Stale native work must not continue promising a countdown")
    }

    func testTokenBurstsDoNotProduceHoursOfEstimatedTimeOrChangeCalibratedDeadline() throws {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryWork(.init(phase: .indexing, completedFraction: 0, operationFraction: 0.001,
            item: 1, totalItems: 20)), at: start)
        tracker.report(.generating(.responseTokens(completed: 1, limit: 1_024)), at: start.advanced(by: .seconds(1)))
        tracker.report(.generating(.responseTokens(completed: 4, limit: 1_024)), at: start.advanced(by: .seconds(12)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(12))).remainingSeconds)
        XCTAssertEqual(tracker.detail, "Finding meeting topics — section 1 of 20…")

        let calibrated = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        for index in 0...3 {
            calibrated.report(.summaryWork(.init(phase: .writing, completedFraction: Double(index) / 10,
                operationFraction: 0.1)), at: start.advanced(by: .seconds(index * 10)))
        }
        let before = try XCTUnwrap(calibrated.display(at: start.advanced(by: .seconds(30))).remainingSeconds)
        calibrated.report(.generating(.responseTokens(completed: 1, limit: 1_024)), at: start.advanced(by: .seconds(31)))
        calibrated.report(.generating(.responseTokens(completed: 900, limit: 1_024)), at: start.advanced(by: .seconds(35)))
        let after = try XCTUnwrap(calibrated.display(at: start.advanced(by: .seconds(35))).remainingSeconds)
        XCTAssertEqual(after, before - 5, "Output token bursts must not recalculate the whole-meeting estimate")
    }

    func testMajorSlowdownRecalibratesInsteadOfJumpingOrStallingAtOneSecond() throws {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        for index in 0...3 {
            tracker.report(.summaryWork(.init(phase: .writing, completedFraction: Double(index) / 10,
                operationFraction: 0.1)), at: start.advanced(by: .seconds(index * 10)))
        }
        XCTAssertNotNil(tracker.display(at: start.advanced(by: .seconds(30))).remainingSeconds)
        tracker.report(.summaryWork(.init(phase: .checking, completedFraction: 0.4, operationFraction: 0.1)),
            at: start.advanced(by: .seconds(90)))
        let revised = tracker.display(at: start.advanced(by: .seconds(90)))
        XCTAssertNil(revised.remainingSeconds)
        XCTAssertEqual(revised.remainingText, "Re-estimating…")
        tracker.finish(success: false, at: start.advanced(by: .seconds(92)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(100))).remainingSeconds)
    }

    func testPlanningAndFinalPassAdvanceWhileGenerationRemainsBelowCompletion() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.loadingModel(completedBytes: 1_024, totalBytes: 1_024), at: start)
        let loaded = tracker.progress.completedUnitCount
        tracker.report(.planningSummary(completed: 720, total: 1_440, pass: 1), at: start.advanced(by: .seconds(1)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, loaded)
        tracker.report(.planningSummary(completed: 1_440, total: 1_440, pass: 2), at: start.advanced(by: .seconds(2)))
        tracker.report(.summaryChunks(completed: 360, total: 360), at: start.advanced(by: .seconds(90)))
        let mapped = tracker.progress.completedUnitCount
        tracker.report(.consolidatingSummary(completed: 0, total: 40), at: start.advanced(by: .seconds(91)))
        tracker.report(.generationStarted, at: start.advanced(by: .seconds(91)))
        tracker.report(.generating(.promptTokens(completed: 256, total: 512)), at: start.advanced(by: .seconds(92)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, mapped)
        let reading = tracker.progress.completedUnitCount
        tracker.report(.generating(.responseTokens(completed: 12, limit: 256)), at: start.advanced(by: .seconds(93)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, reading)
        XCTAssertEqual(tracker.detail, IntelligenceProgress.consolidatingSummary(completed: 0, total: 1).message)
        tracker.report(.consolidatingSummary(completed: 1, total: 40), at: start.advanced(by: .seconds(94)))
        XCTAssertLessThan(tracker.display(at: start.advanced(by: .seconds(94))).percentage, 100)
        tracker.report(.saving, at: start.advanced(by: .seconds(95)))
        tracker.finish(success: true, at: start.advanced(by: .seconds(96)))
        XCTAssertEqual(tracker.display(at: start.advanced(by: .seconds(100))).percentage, 100)
    }

    func testElapsedIncludesWaitingAndLockedTimeWithoutInventingProgress() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        let before = tracker.display(at: start)
        let after = tracker.display(at: start.advanced(by: .seconds(247)))
        XCTAssertEqual(before.percentage, 0)
        XCTAssertEqual(after.percentage, 0)
        XCTAssertEqual(after.elapsedSeconds, 247)
        XCTAssertEqual(after.elapsedText, "04:07")
        XCTAssertNil(after.remainingSeconds)
        XCTAssertTrue(after.notificationSubtitle.contains("0%"))
        XCTAssertTrue(after.notificationSubtitle.contains("04:07 elapsed"))
        XCTAssertTrue(after.notificationSubtitle.contains("Estimating"))
        XCTAssertEqual(tracker.title, "Summary")
    }

    func testEstimateRequiresMeasuredGenerationAndRecalibratesWhenWorkChanges() throws {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.loadingModel(completedBytes: 1_024, totalBytes: 1_024), at: start.advanced(by: .seconds(1)))
        tracker.report(.summaryChunks(completed: 0, total: 2), at: start.advanced(by: .seconds(2)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(3))).remainingSeconds,
                     "Fast verification and restored maps must not predict generation speed")
        tracker.report(.generating(.promptTokens(completed: 0, total: 512)), at: start.advanced(by: .seconds(3)))
        tracker.report(.generating(.promptTokens(completed: 128, total: 512)), at: start.advanced(by: .seconds(4)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(4))).remainingSeconds)
        tracker.report(.generating(.promptTokens(completed: 512, total: 512)), at: start.advanced(by: .seconds(7)))
        let reading = tracker.display(at: start.advanced(by: .seconds(7)))
        XCTAssertGreaterThan(try XCTUnwrap(reading.remainingSeconds), 0)
        XCTAssertTrue(reading.notificationSubtitle.contains("~"))
        tracker.report(.generating(.responseTokens(completed: 1, limit: 1_024)), at: start.advanced(by: .seconds(8)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(8))).remainingSeconds,
                     "Output generation must measure its own slower rate")
        tracker.report(.generating(.responseTokens(completed: 100, limit: 1_024)), at: start.advanced(by: .seconds(12)))
        XCTAssertNotNil(tracker.display(at: start.advanced(by: .seconds(12))).remainingSeconds)
        let stalled = tracker.display(at: start.advanced(by: .seconds(40)))
        XCTAssertNil(stalled.remainingSeconds, "An old estimate must not count down to zero during a stall")
        tracker.report(.summaryChunks(completed: 1, total: 2), at: start.advanced(by: .seconds(41)))
        XCTAssertNil(tracker.display(at: start.advanced(by: .seconds(41))).remainingSeconds)
    }

    func testSuccessAloneShowsOneHundredPercentAndFreezesElapsed() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryChunks(completed: 1, total: 1), at: start.advanced(by: .seconds(10)))
        tracker.report(.saving, at: start.advanced(by: .seconds(11)))
        XCTAssertLessThan(tracker.display(at: start.advanced(by: .seconds(12))).percentage, 100)
        tracker.finish(success: true, at: start.advanced(by: .seconds(13)))
        tracker.finish(success: false, at: start.advanced(by: .seconds(99)))
        let saved = tracker.display(at: start.advanced(by: .seconds(120)))
        XCTAssertEqual(saved.percentage, 100)
        XCTAssertEqual(saved.elapsedSeconds, 13)
        XCTAssertNil(saved.remainingSeconds)
        XCTAssertTrue(saved.notificationSubtitle.contains("Complete"))
        XCTAssertFalse(saved.notificationSubtitle.contains("Estimating"))
        XCTAssertFalse(tracker.report(.preparing, at: start.advanced(by: .seconds(121))))
    }

    func testCancellationFreezesElapsedAndNewAttemptsStartTheirOwnClock() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryChunks(completed: 0, total: 2), at: start)
        tracker.report(.generating(.responseTokens(completed: 512, limit: 1_024)), at: start.advanced(by: .seconds(40)))
        let prior = tracker.display(at: start.advanced(by: .seconds(40)))
        tracker.finish(success: false, at: start.advanced(by: .seconds(41)))
        let stopped = tracker.display(at: start.advanced(by: .seconds(100)))
        XCTAssertEqual(stopped.percentage, prior.percentage)
        XCTAssertLessThan(stopped.percentage, 100)
        XCTAssertEqual(stopped.elapsedSeconds, 41)
        XCTAssertTrue(stopped.notificationSubtitle.contains("Stopped"))
        let resumed = IntelligenceProgressTracker(operation: .summary, startedAt: start.advanced(by: .seconds(100)))
        XCTAssertEqual(resumed.display(at: start.advanced(by: .seconds(101))).elapsedSeconds, 1)
        XCTAssertNil(resumed.display(at: start.advanced(by: .seconds(101))).remainingSeconds)
    }

    func testAnotherGenerationStageContinuesWithoutMovingPercentageBackward() {
        let start = ContinuousClock.now
        let tracker = IntelligenceProgressTracker(operation: .summary, startedAt: start)
        tracker.report(.summaryChunks(completed: 0, total: 2), at: start)
        tracker.report(.generating(.responseTokens(completed: 1_024, limit: 1_024)), at: start.advanced(by: .seconds(40)))
        let before = tracker.progress.completedUnitCount
        tracker.report(.generationStarted, at: start.advanced(by: .seconds(41)))
        tracker.report(.generating(.promptTokens(completed: 256, total: 512)), at: start.advanced(by: .seconds(42)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, before)
        let reading = tracker.progress.completedUnitCount
        tracker.report(.generating(.responseTokens(completed: 40, limit: 256)), at: start.advanced(by: .seconds(45)))
        XCTAssertGreaterThan(tracker.progress.completedUnitCount, reading)
        XCTAssertLessThan(tracker.display(at: start.advanced(by: .seconds(45))).percentage, 50)
    }
}
#endif
