#if os(iOS)
import Foundation
import XCTest
import UIKit
@testable import LocalMinutes

@MainActor
final class NativeSummaryPresentationTests: XCTestCase {
    func testNarrativeSummaryDisplaysOverviewAndRealBulletsWithoutLegacyCategories() throws {
        let document = try narrativeFixture()
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.map(\.title), ["Overview", "Minutes of Meetings"])
        XCTAssertEqual(presentation.sections.map(\.isBulleted), [true, true])
        XCTAssertEqual(presentation.sections[0].items, ["The team prepared the next release."])
        XCTAssertEqual(presentation.sections[1].items, ["Maya will share the checklist before Friday's review."])
        XCTAssertFalse(presentation.sections.contains { ["Decisions", "Next steps", "Actions"].contains($0.title) })
    }

    func testNarrativeWithoutOverviewStillHasBulletsAndEditedCopyFallsBack() throws {
        let document = try narrativeFixture(overview: false)
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.count, 2)
        XCTAssertTrue(presentation.sections[0].isBulleted)
        let edited = try narrativeFixture(editRevision: 1)
        XCTAssertNil(SummaryPresentation(document: edited, text: edited.editedText))
        XCTAssertNil(SummaryPresentation(document: document, text: "An unsaved rewrite."))
    }

    func testOriginalSummaryGroupsActualDecisionsAndActions() throws {
        let document = try fixture()
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText))
        XCTAssertEqual(presentation.sections.map(\.title), ["Overview", "Minutes of Meetings"])
        XCTAssertEqual(presentation.sections[1].items, ["Review on Friday.", "Share checklist — Maya (Friday)"])
        XCTAssertTrue(presentation.sections.allSatisfy(\.isBulleted))
    }

    func testOverviewLinesBecomeSeparateBulletsWithActualMeetingDateAndTime() throws {
        let document = try narrativeFixture(overviewText: "Discussed the next release.\nAgreed to review on Friday.")
        let meetingStart = Date(timeIntervalSince1970: 1_700_000_000)
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText,
            meetingStartedAt: meetingStart))
        XCTAssertEqual(presentation.sections[0].items,
            SummaryOverviewFormatting.meetingDetails(startedAt: meetingStart)
                + ["Discussed the next release.", "Agreed to review on Friday."])
        XCTAssertNotEqual(meetingStart, document.createdAt, "Use meeting time, not summary generation time")
    }

    func testStoredOverviewItemsMatchTheSavedDisplayCopyWithoutDuplicateMetadata() throws {
        let items = ["Date: 29 October 2026", "Time: 10:30 (GMT)", "Discussed release readiness."]
        let document = try narrativeFixture(overviewItems: items)
        let presentation = try XCTUnwrap(SummaryPresentation(document: document, text: document.editedText,
            meetingStartedAt: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(presentation.sections[0].items, items)
    }

    func testSummaryTextUsesRealJustificationAndScalableHangingBullets() throws {
        for size: CGFloat in [17, 34] {
            let font = UIFont.systemFont(ofSize: size)
            for bulleted in [false, true] {
                let text = JustifiedSummaryText.attributedText("A discussion point that can wrap onto several lines.",
                    font: font, bulleted: bulleted)
                let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(style.alignment, .justified)
                XCTAssertEqual(style.headIndent, bulleted ? size * 1.25 : 0)
                XCTAssertEqual(text.string.hasPrefix("•\t"), bulleted)
            }
        }
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

    private func narrativeFixture(overview: Bool = true, editRevision: Int64 = 0,
                                  overviewText: String = "The team prepared the next release.",
                                  overviewItems: [String]? = nil) throws -> StoredGeneratedDocument {
        let meeting = UUID()
        var payload: [String: Any] = [
            "schema_version": 2, "meeting_id": meeting.uuidString,
            "overview": overview ? ["text": overviewText, "evidence": []] as Any : NSNull(),
            "bullets": [["text": "Maya will share the checklist before Friday's review.", "evidence": []]]
        ]
        if let overviewItems { payload["overview_items"] = overviewItems }
        let json = try JSONSerialization.data(withJSONObject: payload)
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
