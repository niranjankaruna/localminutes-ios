import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import LocalMinutesMeetingLibrary
import LocalMinutesPersistence
#else
@testable import LocalMinutes
#endif

final class MeetingTextExporterTests: XCTestCase {
    func testMarkdownExportIncludesOriginalNotesOrderedTimedTranscriptAndModelProvenance() throws {
        let meeting = exportFixtureMeeting()
        let note = StoredManualNote(meetingID: meeting.id, text: "Original synthetic manual note",
            editRevision: 2, modifiedAt: Date(timeIntervalSince1970: 2_000))
        let first = exportFixtureSegment(10, meetingID: meeting.id, sequence: 0,
            start: 20_000, end: 40_000, text: "First synthetic source.")
        let second = exportFixtureSegment(11, meetingID: meeting.id, sequence: 1,
            start: 64_000, end: 80_000, text: "Second synthetic source.")
        let output = try MeetingTextExporter.markdown(MeetingExportDocument(
            meeting: meeting, manualNote: note, transcript: [second, first]))
        XCTAssertTrue(output.contains("# Synthetic meeting"))
        XCTAssertTrue(output.contains("1970-01-01T00:16:40Z"), "Export dates are UTC")
        XCTAssertTrue(output.contains("## Manual notes"))
        XCTAssertTrue(output.contains(note.text))
        XCTAssertTrue(output.contains("## Transcript"))
        XCTAssertTrue(output.contains("00:00:01.250"))
        XCTAssertTrue(output.contains("00:00:02.500"))
        XCTAssertTrue(output.contains("utterance"), "Do not present utterance timing as word timing")
        XCTAssertTrue(output.contains("synthetic-model-revision"))
        let firstRange = output.range(of: first.text)
        let secondRange = output.range(of: second.text)
        XCTAssertNotNil(firstRange)
        XCTAssertNotNil(secondRange)
        if let firstRange, let secondRange {
            XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
        }
    }

    func testPlainTextExportPreservesUnicodeAndLabelsUnavailableTranscriptHonestly() throws {
        let meeting = exportFixtureMeeting()
        let original = "Original manual note — Café 📝\nA second line."
        let document = MeetingExportDocument(meeting: meeting,
            manualNote: StoredManualNote(meetingID: meeting.id, text: original,
                editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 2_000)), transcript: [])
        let output = try MeetingTextExporter.plainText(document)
        XCTAssertTrue(output.contains(meeting.title))
        XCTAssertTrue(output.contains(original))
        XCTAssertTrue(output.contains("No finalized transcript"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("summary generated"))
        XCTAssertFalse(output.contains("file://"))
        XCTAssertFalse(output.contains(".sqlite"))
    }

    func testExportsRejectCrossMeetingNoteOrTranscriptInsteadOfLeakingOtherContent() throws {
        let meeting = exportFixtureMeeting()
        let otherID = UUID()
        let wrongNote = StoredManualNote(meetingID: otherID, text: "Synthetic other meeting note",
            editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 2_000))
        let wrongSegment = exportFixtureSegment(10, meetingID: otherID, sequence: 0,
            start: 0, end: 16_000, text: "Synthetic other meeting transcript")
        for document in [
            MeetingExportDocument(meeting: meeting, manualNote: wrongNote, transcript: []),
            MeetingExportDocument(meeting: meeting, manualNote: nil, transcript: [wrongSegment])
        ] {
            XCTAssertThrowsError(try MeetingTextExporter.markdown(document)) {
                XCTAssertEqual($0 as? MeetingExportError, .crossMeetingContent)
            }
            XCTAssertThrowsError(try MeetingTextExporter.plainText(document)) {
                XCTAssertEqual($0 as? MeetingExportError, .crossMeetingContent)
            }
        }
    }

    func testMarkdownTreatsMeetingMarkupAsTextAndPlainTextRetainsTheOriginal() throws {
        let meeting = exportFixtureMeeting()
        let original = "<script>alert('synthetic')</script> ![beacon](https://example.invalid/synthetic)"
        let document = MeetingExportDocument(meeting: meeting, manualNote: nil,
            transcript: [exportFixtureSegment(10, meetingID: meeting.id, sequence: 0,
                start: 0, end: 16_000, text: original)])
        let markdown = try MeetingTextExporter.markdown(document)
        XCTAssertFalse(markdown.contains("<script>"))
        XCTAssertFalse(markdown.contains("![beacon]"))
        XCTAssertFalse(markdown.contains("](https://"))
        XCTAssertTrue(markdown.contains("&lt;script&gt;"))
        XCTAssertTrue(markdown.contains("example.invalid/synthetic"))
        let plain = try MeetingTextExporter.plainText(document)
        XCTAssertTrue(plain.contains(original), "User content must not be rewritten in plain text")
    }
}

private func exportFixtureMeeting() -> MeetingRecord {
    MeetingRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Synthetic meeting", createdAt: Date(timeIntervalSince1970: 1_000),
        recordingState: .completed, capturedSampleCount: 80_000)
}

private func exportFixtureSegment(_ number: Int, meetingID: UUID, sequence: Int,
                                  start: Int64, end: Int64, text: String) -> StoredTranscriptSegment {
    StoredTranscriptSegment(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
        meetingID: meetingID, sequence: sequence, startSample: start, endSample: end,
        text: text, modelRevision: "synthetic-model-revision")
}
