import Foundation
import XCTest
@testable import LocalMinutesSummary

final class RepeatedSummaryItemsTests: XCTestCase {
    func testRepeatedValidModelItemsMergeButEveryClaimStillMustBeGrounded() throws {
        let meeting = UUID()
        let text = "Leo: I will write the guide by Thursday."
        let source = GroundedSummarySource(meetingID: meeting, segments: [
            .init(id: "source", startSample: 0, endSample: 16_000, text: text)
        ], originalManualNotes: "")
        let evidence: [[String: Any]] = [["source_id": "source", "start_sample": 0,
                                        "end_sample": 16_000, "quote": text]]
        let point: [String: Any] = ["text": text, "evidence": evidence]
        let action: [String: Any] = ["task": text, "evidence": evidence, "owner": "Leo", "due": "Thursday"]
        func decode(_ second: [String: Any]) throws -> GroundedSummary {
            let bytes = try JSONSerialization.data(withJSONObject: ["meeting_id": meeting.uuidString,
                "summary_points": [point, point], "decisions": [], "actions": [action, second]])
            return try GroundedSummaryDecoder.decode(bytes, selectedMeetingID: meeting, source: source,
                provenance: .init(modelRevision: String(repeating: "a", count: 40),
                    promptVersion: SummaryPipeline.currentPromptVersion, mapIndex: 0), mergingRepeatedItems: true)
        }
        let result = try decode(action)
        XCTAssertEqual(result.summaryPoints.count, 1)
        XCTAssertEqual(result.actions.count, 1)
        XCTAssertEqual(result.actions[0].owner, "Leo")
        XCTAssertEqual(result.actions[0].due, "Thursday")

        var unsupported = action
        unsupported["owner"] = "Invented owner"
        XCTAssertThrowsError(try decode(unsupported)) {
            XCTAssertEqual($0 as? GroundedSummaryError, .unsupportedClaim)
        }
        var conflicting = action
        conflicting["owner"] = NSNull()
        XCTAssertThrowsError(try decode(conflicting)) {
            XCTAssertEqual($0 as? GroundedSummaryError, .conflictingClaim)
        }
        var unrelated = action
        unrelated["evidence"] = [["source_id": "another-meeting", "start_sample": 0,
                                  "end_sample": 16_000, "quote": text]]
        XCTAssertThrowsError(try decode(unrelated)) {
            XCTAssertEqual($0 as? GroundedSummaryError, .unknownSourceID)
        }
    }
}
