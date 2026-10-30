import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesMeetingLibrary

@MainActor
final class MeetingLibraryControllerTests: XCTestCase {
    func testHistoryAndSelectedMeetingLoadActualStoredContentWithoutCrossMeetingText() async throws {
        try await withLibrary { store, first, second in
            let screen = MeetingLibraryController(store: store)
            await screen.refresh()
            XCTAssertEqual(screen.meetings.map(\.id), [second, first])
            await screen.open(id: first)
            XCTAssertEqual(screen.selected?.id, first)
            XCTAssertEqual(screen.transcript.map(\.text), ["First selected source"])
            XCTAssertFalse(screen.transcript.contains { $0.meetingID == second })
            XCTAssertNil(screen.errorMessage)
        }
    }

    func testNotesAutosaveReopensFromDurableRevisionAndRenameKeepsTheSameMeeting() async throws {
        try await withLibrary { store, first, _ in
            let initial = StoredManualNote(meetingID: first, text: "Earlier edit", editRevision: 40,
                                           modifiedAt: Date(timeIntervalSince1970: 4))
            try await store.saveManualNote(initial)
            let screen = MeetingLibraryController(store: store)
            await screen.open(id: first)
            await screen.saveNotes("New original notes 📝")
            await screen.rename("Renamed meeting")
            let reopenedScreen = MeetingLibraryController(store: store)
            await reopenedScreen.open(id: first)
            XCTAssertEqual(reopenedScreen.note?.text, "New original notes 📝")
            XCTAssertEqual(reopenedScreen.note?.editRevision, 41)
            XCTAssertEqual(reopenedScreen.selected?.id, first)
            XCTAssertEqual(reopenedScreen.selected?.title, "Renamed meeting")
            XCTAssertNil(screen.errorMessage)
        }
    }

    func testSearchAndExportUseOnlySelectionAndDeleteClearsItsVisibleContent() async throws {
        try await withLibrary { store, first, second in
            let screen = MeetingLibraryController(store: store)
            await screen.open(id: first)
            await screen.search("source")
            XCTAssertEqual(screen.matches.map(\.text), ["First selected source"])
            do {
                let output = try screen.export(markdown: false)
                XCTAssertTrue(output.contains("First selected source"))
                XCTAssertFalse(output.contains("Other meeting source"))
            } catch { XCTFail("A selected durable meeting must export") }
            await screen.deleteSelected()
            XCTAssertNil(screen.selected)
            XCTAssertTrue(screen.transcript.isEmpty)
            XCTAssertTrue(screen.matches.isEmpty)
            let deleted = try await store.meeting(id: first)
            let retained = try await store.meeting(id: second)
            XCTAssertNil(deleted)
            XCTAssertNotNil(retained)
            XCTAssertEqual(screen.meetings.map(\.id), [second])
        }
    }

    private func withLibrary(_ body: (SQLiteMeetingStore, UUID, UUID) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-library-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        let first = UUID(), second = UUID()
        for (id, date, text) in [(first, 1.0, "First selected source"), (second, 2.0, "Other meeting source")] {
            try await store.createMeeting(.init(id: id, title: "Synthetic meeting", createdAt: Date(timeIntervalSince1970: date), recordingState: .completed))
            try await store.appendFinalizedSegments([.init(id: UUID(), meetingID: id, sequence: 0,
                startSample: 0, endSample: 16_000, text: text, modelRevision: "fixture-revision")], to: id)
        }
        do { try await body(store, first, second) }
        catch { try? await store.close(); try? FileManager.default.removeItem(at: root); throw error }
        try await store.close()
        guard root.lastPathComponent.hasPrefix("localminutes-library-test-"),
              root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
            XCTFail("Unsafe test fixture cleanup"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
