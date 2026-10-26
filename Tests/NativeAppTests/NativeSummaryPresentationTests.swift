#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

final class NativeSummaryPresentationTests: XCTestCase {
    func testOriginalSummaryGroupsActualDecisionsAndActions() throws {
        let document = try fixture()
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.map(\.title), ["Overview", "Decisions", "Next steps"])
        XCTAssertEqual(presentation.sections[1].items, ["Review on Friday."])
        XCTAssertEqual(presentation.sections[2].items, ["Share checklist — Maya (Friday)"])
    }

    func testEditedOrUnsavedDisplayCopyNeverGetsReplacedByOriginalStructuredContent() throws {
        let edited = try fixture(editRevision: 1)
        XCTAssertNil(SummaryPresentation(document: edited, text: edited.editedText))
        let original = try fixture()
        XCTAssertNil(SummaryPresentation(document: original, text: "My unsaved rewrite."))
    }

    func testForeignMeetingPayloadFallsBackToActualDisplayCopy() throws {
        let document = try fixture(payloadMeeting: UUID())
        XCTAssertNil(SummaryPresentation(document: document, text: document.editedText))
    }

    private func fixture(editRevision: Int64 = 0, payloadMeeting: UUID? = nil) throws -> StoredGeneratedDocument {
        let meeting = UUID()
        let json = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "meeting_id": (payloadMeeting ?? meeting).uuidString,
            "summary_points": [["text": "Discussed launch."]],
            "decisions": [["text": "Review on Friday."]],
            "actions": [["task": "Share checklist", "owner": "Maya", "due": "Friday"]]
        ])
        return StoredGeneratedDocument(id: UUID(), meetingID: meeting, kind: .summary, originalJSON: json,
            question: nil, editedText: "Stored display copy.", editRevision: editRevision,
            modelRevision: "fixture", promptVersion: "fixture", createdAt: Date(), modifiedAt: Date())
    }
}
#endif
