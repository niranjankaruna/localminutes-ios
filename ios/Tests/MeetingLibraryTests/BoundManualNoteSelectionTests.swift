import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesMeetingLibrary

@MainActor
final class BoundManualNoteSelectionTests: XCTestCase {
    func testADebouncedEditRetainsItsOriginalMeetingAfterSelectionChanges() async throws {
        try await withBoundNotes { store, first, second in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: first)
            let captured = try XCTUnwrap(controller.note)
            let delayed = StoredManualNote(meetingID: first, text: "Synthetic delayed edit for first",
                editRevision: captured.editRevision + 1, modifiedAt: Date(timeIntervalSince1970: 5_000))
            await controller.open(id: second)
            let visibleBefore = controller.note
            try await controller.saveNotes(delayed)
            let firstSaved = try await store.manualNote(meetingID: first)
            let secondSaved = try await store.manualNote(meetingID: second)
            XCTAssertEqual(firstSaved, delayed)
            XCTAssertEqual(secondSaved, visibleBefore)
            XCTAssertEqual(controller.selected?.id, second)
            XCTAssertEqual(controller.note, visibleBefore)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testFailedLateAutosaveDoesNotReplaceAnotherMeetingsVisibleNotesOrErrorState() async throws {
        try await withBoundNotes { store, first, second in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: first)
            let captured = try XCTUnwrap(controller.note)
            let delayed = StoredManualNote(meetingID: first, text: "Synthetic unsaved first edit",
                editRevision: captured.editRevision + 1, modifiedAt: Date(timeIntervalSince1970: 5_000))
            await controller.open(id: second)
            let visibleBefore = controller.note
            try await store.close()
            do {
                try await controller.saveNotes(delayed)
                XCTFail("The originating editor must receive the real storage failure")
            } catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
            XCTAssertEqual(controller.selected?.id, second)
            XCTAssertEqual(controller.note, visibleBefore)
            XCTAssertNil(controller.errorMessage, "A's save failure must not be attributed to selected meeting B")
        }
    }
}

@MainActor
private func withBoundNotes(_ body: @MainActor (SQLiteMeetingStore, UUID, UUID) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-bound-note-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("notes.sqlite"))
    let first = UUID(), second = UUID()
    for (id, revision) in [(first, Int64(4)), (second, Int64(7))] {
        try await store.createMeeting(MeetingRecord(id: id, title: "Synthetic meeting",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
        try await store.saveManualNote(StoredManualNote(meetingID: id,
            text: id == first ? "Synthetic first note" : "Synthetic second note",
            editRevision: revision, modifiedAt: Date(timeIntervalSince1970: 1_000)))
    }
    do { try await body(store, first, second) }
    catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
    try? await store.close()
    guard root.lastPathComponent.hasPrefix("localminutes-bound-note-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}
