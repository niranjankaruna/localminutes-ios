import Foundation
import SQLite3
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesMeetingLibrary

@MainActor
final class ManualNoteEditReservationTests: XCTestCase {
    func testSynchronousReservationBindsTheOriginalMeetingBeforeDebounceAndSelectionChange() async throws {
        try await withReservationStore { store, first, second, _ in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: first)
            let original = try await store.manualNote(meetingID: first)
            let reserved = controller.reserveManualNoteEdit("Synthetic edit captured for first")
            XCTAssertNotNil(reserved, "A changed loaded note must produce an immutable edit before any await")
            guard let reserved else { return }
            XCTAssertEqual(reserved.meetingID, first)
            XCTAssertEqual(reserved.editRevision, 5)
            XCTAssertEqual(reserved.text, "Synthetic edit captured for first")
            XCTAssertTrue(reserved.modifiedAt.timeIntervalSince1970.isFinite)
            let beforeSave = try await store.manualNote(meetingID: first)
            XCTAssertEqual(beforeSave, original, "Reservation alone must not claim a SQLite autosave")
            await controller.open(id: second)
            let visibleSecond = controller.note
            try await controller.saveNotes(reserved)
            let savedFirst = try await store.manualNote(meetingID: first)
            let savedSecond = try await store.manualNote(meetingID: second)
            XCTAssertEqual(savedFirst, reserved)
            XCTAssertEqual(savedSecond, visibleSecond)
            XCTAssertEqual(controller.selected?.id, second)
            XCTAssertEqual(controller.note, visibleSecond)
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testRapidReservationsIncreaseRevisionsBeforeAwaitAndReversedCommitsKeepTheLatestEdit() async throws {
        try await withReservationStore { store, first, _, database in
            let controller = MeetingLibraryController(store: store)
            await controller.open(id: first)
            // Both reservations occur synchronously on the UI actor. No save,
            // actor hop or SQLite call may be needed to distinguish revisions.
            let earlier = controller.reserveManualNoteEdit("Synthetic earlier user edit")
            let latest = controller.reserveManualNoteEdit("Synthetic latest user edit")
            XCTAssertNotNil(earlier)
            XCTAssertNotNil(latest)
            guard let earlier, let latest else { return }
            XCTAssertEqual(earlier.meetingID, first)
            XCTAssertEqual(latest.meetingID, first)
            XCTAssertEqual(earlier.editRevision, 5)
            XCTAssertEqual(latest.editRevision, 6)
            XCTAssertGreaterThan(latest.editRevision, earlier.editRevision)
            let unchanged = try await store.manualNote(meetingID: first)
            XCTAssertEqual(unchanged?.editRevision, 4)
            XCTAssertEqual(unchanged?.text, "Synthetic original first note")
            try await controller.saveNotes(latest)
            do {
                try await controller.saveNotes(earlier)
                XCTFail("A delayed earlier reservation cannot replace the latest committed user edit")
            } catch { XCTAssertEqual(error as? ManualNoteStoreError, .staleRevision) }
            let actual = try await store.manualNote(meetingID: first)
            XCTAssertEqual(actual, latest)
            XCTAssertEqual(controller.note, latest)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            let durable = try await reopened.manualNote(meetingID: first)
            XCTAssertEqual(durable, latest)
            try await reopened.close()
        }
    }

    func testLoadedUnchangedTextAndNilSelectionProduceNoEditOrSQLiteWrite() async throws {
        try await withReservationStore { store, first, second, database in
            let observer = try ReservationDatabaseObserver(database)
            let versionBefore = try observer.dataVersion()
            let originalFirst = try await store.manualNote(meetingID: first)
            let originalSecond = try await store.manualNote(meetingID: second)
            let controller = MeetingLibraryController(store: store)
            XCTAssertNil(controller.reserveManualNoteEdit("Synthetic text without a selection"))
            await controller.open(id: first)
            let loaded = try XCTUnwrap(controller.note)
            XCTAssertNil(controller.reserveManualNoteEdit(loaded.text))
            XCTAssertNil(controller.reserveManualNoteEdit(loaded.text))
            XCTAssertEqual(controller.note, loaded)
            await controller.open(id: UUID())
            XCTAssertNil(controller.selected)
            let expectedError = controller.errorMessage
            XCTAssertNil(controller.reserveManualNoteEdit("Synthetic unowned draft"))
            XCTAssertEqual(controller.errorMessage, expectedError)
            let persistedFirst = try await store.manualNote(meetingID: first)
            let persistedSecond = try await store.manualNote(meetingID: second)
            let meetings = try await store.history()
            XCTAssertEqual(persistedFirst, originalFirst)
            XCTAssertEqual(persistedSecond, originalSecond)
            XCTAssertEqual(Set(meetings.map(\.id)), Set([first, second]))
            XCTAssertEqual(try observer.dataVersion(), versionBefore,
                           "The actual observer connection must see no database commit from a non-edit")
        }
    }
}

private enum ReservationFixtureError: Error { case sqlite }

/// A read-only second SQLite connection observes database commits. It is not a
/// mocked write counter or a database implementation used by the controller.
private final class ReservationDatabaseObserver {
    private let handle: OpaquePointer
    init(_ url: URL) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let opened else {
            if let opened { sqlite3_close(opened) }
            throw ReservationFixtureError.sqlite
        }
        handle = opened
    }
    deinit { sqlite3_close(handle) }
    func dataVersion() throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA data_version", -1, &statement, nil) == SQLITE_OK else {
            throw ReservationFixtureError.sqlite
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ReservationFixtureError.sqlite }
        return sqlite3_column_int(statement, 0)
    }
}

@MainActor
private func withReservationStore(_ body: @MainActor (SQLiteMeetingStore, UUID, UUID, URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-note-reservation-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let database = root.appendingPathComponent("meetings.sqlite")
    let store = try SQLiteMeetingStore(databaseURL: database)
    let first = UUID(), second = UUID()
    for (id, revision) in [(first, Int64(4)), (second, Int64(7))] {
        try await store.createMeeting(MeetingRecord(id: id, title: "Synthetic meeting",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
        try await store.saveManualNote(StoredManualNote(meetingID: id,
            text: id == first ? "Synthetic original first note" : "Synthetic original second note",
            editRevision: revision, modifiedAt: Date(timeIntervalSince1970: 1_000)))
    }
    do { try await body(store, first, second, database) }
    catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
    try? await store.close()
    guard root.lastPathComponent.hasPrefix("localminutes-note-reservation-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}
