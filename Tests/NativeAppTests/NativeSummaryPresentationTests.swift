#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

final class NativeSummaryPresentationTests: XCTestCase {
    func testNarrativeSummaryDisplaysOverviewAndRealBulletsWithoutLegacyCategories() throws {
        let document = try narrativeFixture()
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.map(\.title), ["Overview", ""])
        XCTAssertEqual(presentation.sections.map(\.isBulleted), [false, true])
        XCTAssertEqual(presentation.sections[0].items, ["The team prepared the next release."])
        XCTAssertEqual(presentation.sections[1].items, ["Maya will share the checklist before Friday's review."])
        XCTAssertFalse(presentation.sections.contains { ["Decisions", "Next steps", "Actions"].contains($0.title) })
    }

    func testNarrativeWithoutOverviewStillHasBulletsAndEditedCopyFallsBack() throws {
        let document = try narrativeFixture(overview: false)
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.count, 1)
        XCTAssertTrue(presentation.sections[0].isBulleted)
        let edited = try narrativeFixture(editRevision: 1)
        XCTAssertNil(SummaryPresentation(document: edited, text: edited.editedText))
        XCTAssertNil(SummaryPresentation(document: document, text: "An unsaved rewrite."))
    }

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

    private func narrativeFixture(overview: Bool = true, editRevision: Int64 = 0) throws -> StoredGeneratedDocument {
        let meeting = UUID()
        let json = try JSONSerialization.data(withJSONObject: [
            "schema_version": 2, "meeting_id": meeting.uuidString,
            "overview": overview ? ["text": "The team prepared the next release.", "evidence": []] as Any : NSNull(),
            "bullets": [["text": "Maya will share the checklist before Friday's review.", "evidence": []]]
        ])
        return StoredGeneratedDocument(id: UUID(), meetingID: meeting, kind: .summary, originalJSON: json,
            question: nil, editedText: "Overview\nThe team prepared the next release.\n\n• Maya will share the checklist before Friday's review.",
            editRevision: editRevision, modelRevision: "fixture", promptVersion: "narrative-v1", createdAt: Date(), modifiedAt: Date())
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
