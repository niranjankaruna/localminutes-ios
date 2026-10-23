import Foundation
import XCTest
@testable import LocalMinutes

/// Actual ActivityKit value/serialization contract, not OS presentation evidence.
@MainActor
final class RecordingActivityContentTests: XCTestCase {
    func testActivityTimerStartsOnlyAtRecordingAndDoesNotResetOnUpdates() throws {
        let admittedAt = Date(timeIntervalSince1970: 1_000)
        let initial = RecordingActivityAttributes.ContentState(status: "preparing")
        XCTAssertNil(initial.recordingStartedAt)
        XCTAssertNil(initial.recordingEndedAt)
        let recording = initial.updating(status: "recording", at: admittedAt)
        XCTAssertEqual(recording.status, "recording")
        XCTAssertEqual(recording.recordingStartedAt, admittedAt)
        XCTAssertNil(recording.recordingEndedAt)
        let repeated = recording.updating(status: "recording", at: admittedAt.addingTimeInterval(100))
        XCTAssertEqual(repeated.recordingStartedAt, admittedAt)
        XCTAssertNil(repeated.recordingEndedAt)
        let data = try JSONEncoder().encode(repeated)
        XCTAssertEqual(try JSONDecoder().decode(
            RecordingActivityAttributes.ContentState.self, from: data), repeated)
    }

    func testActivityTerminalTimerRemainsFixedAndCannotEndBeforeItsStart() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let recording = RecordingActivityAttributes.ContentState(status: "preparing")
            .updating(status: "recording", at: start)
        let end = start.addingTimeInterval(65)
        let finished = recording.updating(status: "finished", at: end)
        XCTAssertEqual(finished.status, "finished")
        XCTAssertEqual(finished.recordingStartedAt, start)
        XCTAssertEqual(finished.recordingEndedAt, end)
        let repeated = finished.updating(status: "finished", at: end.addingTimeInterval(500))
        XCTAssertEqual(repeated.recordingEndedAt, end)
        let clockMovedBack = recording.updating(status: "failed", at: start.addingTimeInterval(-10))
        XCTAssertEqual(clockMovedBack.recordingEndedAt, start)
    }

    func testFailedPreparationHasNoRecordingTimerAndDefaultPayloadContainsNoMeetingText() throws {
        let failed = RecordingActivityAttributes.ContentState(status: "preparing")
            .updating(status: "failed", at: Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(failed.status, "failed")
        XCTAssertNil(failed.recordingStartedAt)
        XCTAssertNil(failed.recordingEndedAt)
        let data = try JSONEncoder().encode(failed)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["status"])
        let attributes = RecordingActivityAttributes(meetingID: UUID())
        let attributeData = try JSONEncoder().encode(attributes)
        XCTAssertLessThan(data.count + attributeData.count, 4_096)
        let attributeFields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: attributeData) as? [String: Any])
        XCTAssertEqual(Set(attributeFields.keys), ["meetingID"])
    }
}
