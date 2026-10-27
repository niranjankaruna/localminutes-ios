import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class SummaryProgressTests: XCTestCase {
    func testProgressAdvancesOnlyAfterTheMapPassesEvidenceValidation() async throws {
        let meeting = UUID()
        let text = "The release is scheduled for Friday."
        let source = GroundedSummarySource(meetingID: meeting, segments: [
            .init(id: "source", startSample: 0, endSample: 16_000, text: text)
        ], originalManualNotes: "")
        let payload: [String: Any] = ["meeting_id": meeting.uuidString,
            "summary_points": [["text": text, "evidence": [["source_id": "source",
                "start_sample": 0, "end_sample": 16_000, "quote": text]]]],
            "decisions": [], "actions": []]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        for valid in [true, false] {
            let progress = SummaryProgressEvents()
            let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 10 },
                generator: { _, _, _ in valid ? json : "{}" },
                mapProgress: { progress.record($0, $1) })
            do {
                _ = try await pipeline.summarize(selectedMeetingID: meeting, source: source)
                XCTAssertTrue(valid)
            } catch { if valid { throw error } }
            XCTAssertEqual(progress.values, valid ? [[0, 1], [1, 1]] : [[0, 1]])
        }
    }
}

private final class SummaryProgressEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [[Int]] = []
    func record(_ completed: Int, _ total: Int) { lock.withLock { events.append([completed, total]) } }
    var values: [[Int]] { lock.withLock { events } }
}
