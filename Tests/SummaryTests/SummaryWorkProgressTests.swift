import XCTest
@testable import LocalMinutesSummary

final class SummaryWorkProgressTests: XCTestCase {
    func testSingleTranscriptPartDoesNotLookLikeOneDiscoveredTopic() {
        let progress = SummaryWorkProgress(phase: .indexing, completedFraction: 0, operationFraction: 0.25,
            item: 1, totalItems: 1)
        XCTAssertEqual(progress.message, "Reading transcript")
        XCTAssertFalse(progress.message.contains("1 of 1"))
        XCTAssertEqual(progress.counterText, "Part 1 of 1")
        XCTAssertFalse(progress.message.contains("…"))
        XCTAssertTrue(progress.explanation.contains("not a count of topics"))
    }

    func testMultiplePartsRetryAndCheckpointSavingHaveDistinctPlainStatuses() {
        let reading = SummaryWorkProgress(phase: .indexing, completedFraction: 0.1, operationFraction: 0.1,
            item: 2, totalItems: 3)
        XCTAssertEqual(reading.message, "Reading transcript · part 2 of 3")
        XCTAssertEqual(reading.title, "Reading transcript")
        XCTAssertEqual(reading.counterText, "Part 2 of 3")
        let retry = SummaryWorkProgress(phase: .indexing, completedFraction: 0.1, operationFraction: 0.1,
            item: 2, totalItems: 3, isRetry: true)
        XCTAssertTrue(retry.message.contains("smaller transcript part"))
        XCTAssertTrue(retry.explanation.contains("Retrying smaller parts"))
        let saving = SummaryWorkProgress(phase: .checkpointing, completedFraction: 0.25, operationFraction: 0)
        XCTAssertEqual(saving.message, "Saving reading progress")
    }

    func testCounterKeepsTheEntireTotalSeparateFromLongPhaseText() {
        for total in [1, 10, 19, 1_024] {
            let progress = SummaryWorkProgress(phase: .indexing, completedFraction: 0, operationFraction: 0.1,
                item: 1, totalItems: total, isRetry: true)
            XCTAssertEqual(progress.title, "Reading a smaller transcript part")
            XCTAssertEqual(progress.counterText, "Part 1 of \(total)")
        }
    }
}
