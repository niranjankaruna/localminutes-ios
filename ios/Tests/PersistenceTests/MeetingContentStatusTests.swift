import Foundation
import XCTest
import LocalMinutesPersistence

@MainActor
final class MeetingContentStatusTests: XCTestCase {
    func testActualSQLiteStatusDistinguishesEachMeetingsTranscriptAndSummaryAndRemainsUnknownWhenUnreadable() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-content-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        do {
            let transcriptOnly = UUID(), summaryOnly = UUID(), empty = UUID()
            for id in [transcriptOnly, summaryOnly, empty] {
                try await store.createMeeting(.init(id: id, title: "Synthetic content status", createdAt: Date(timeIntervalSince1970: 1),
                    recordingState: .completed, capturedSampleCount: 16_000))
            }
            try await store.appendFinalizedSegments([.init(id: UUID(), meetingID: transcriptOnly, sequence: 0,
                startSample: 0, endSample: 16_000, text: "Synthetic finalized content.", modelRevision: "synthetic-asr")], to: transcriptOnly)
            try await store.createGeneratedDocument(.init(id: UUID(), meetingID: summaryOnly, kind: .summary,
                originalJSON: Data(#"{"synthetic":"previous generated document"}"#.utf8), question: nil,
                editedText: "Synthetic prior summary.", modelRevision: "synthetic-model", promptVersion: "synthetic-prompt",
                createdAt: Date(timeIntervalSince1970: 2), modifiedAt: Date(timeIntervalSince1970: 2)))
            // A saved answer is not a summary, and audio/capture completion is
            // not evidence that any finalized transcript was persisted.
            try await store.createGeneratedDocument(.init(id: UUID(), meetingID: empty, kind: .questionAnswer,
                originalJSON: Data(#"{"synthetic":"previous generated answer"}"#.utf8), question: "Synthetic question?",
                editedText: "Synthetic prior answer.", modelRevision: "synthetic-model", promptVersion: "synthetic-prompt",
                createdAt: Date(timeIntervalSince1970: 2), modifiedAt: Date(timeIntervalSince1970: 2)))
            let first = await store.contentStatus(meetingID: transcriptOnly)
            let second = await store.contentStatus(meetingID: summaryOnly)
            let third = await store.contentStatus(meetingID: empty)
            XCTAssertEqual(first, .init(transcript: .available, summary: .absent))
            XCTAssertEqual(second, .init(transcript: .absent, summary: .available))
            XCTAssertEqual(third, .init(transcript: .absent, summary: .absent))
            let missing = await store.contentStatus(meetingID: UUID())
            XCTAssertEqual(missing, .unknown, "A missing meeting cannot be reported as having a verified empty inventory")
            try await store.close()
            let unreadable = await store.contentStatus(meetingID: transcriptOnly)
            XCTAssertEqual(unreadable, .unknown, "An unreadable database must not falsely claim no content")
        } catch {
            try? await store.close()
            throw error
        }
        guard root.deletingLastPathComponent() == parent,
              root.lastPathComponent.hasPrefix("localminutes-content-status-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            return XCTFail("Content-status fixture ownership mismatch")
        }
        try FileManager.default.removeItem(at: root)
    }
}
