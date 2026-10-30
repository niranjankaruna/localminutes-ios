import Foundation
import SQLite3
import XCTest
#if SWIFT_PACKAGE
@testable import LocalMinutesPersistence
#else
@testable import LocalMinutes
#endif

@MainActor
final class ManualNotePersistenceTests: XCTestCase {
    func testManualNoteAutosaveMigratesVersionOneAndPersistsExactUnicodeTextAcrossReopen() async throws {
        try await withNoteDatabase { url in
            let meeting = noteFixtureMeeting(1)
            try createVersionOneNoteFixtureDatabase(url)
            let expected = StoredManualNote(meetingID: meeting.id,
                text: "Original manual note — Café 📝\nKeep this separate from generated text.",
                editRevision: 7, modifiedAt: Date(timeIntervalSince1970: 10_000))
            let store = try SQLiteMeetingStore(databaseURL: url)
            let preserved = try await store.meeting(id: meeting.id)
            XCTAssertEqual(preserved, meeting, "Adding notes must preserve existing version-one meetings")
            XCTAssertEqual(try noteFixtureSchemaVersion(url), 6, "The original version-one fixture migrates through notes, indexing and generated storage to capture-model provenance")
            try await store.saveManualNote(expected)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.manualNote(meetingID: meeting.id)
            XCTAssertEqual(actual, expected)
            try await reopened.close()
        }
    }

    func testClearingManualNoteAutosavesAnEmptyValueInsteadOfRestoringOldText() async throws {
        try await withNoteDatabase { url in
            let meeting = noteFixtureMeeting(1)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            try await store.saveManualNote(noteFixture(meeting.id, text: "Synthetic old note", revision: 1))
            let cleared = noteFixture(meeting.id, text: "", revision: 2)
            try await store.saveManualNote(cleared)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.manualNote(meetingID: meeting.id)
            XCTAssertEqual(actual, cleared)
            try await reopened.close()
        }
    }

    func testDelayedAutosaveCannotOverwriteANewerDurableManualEdit() async throws {
        try await withNoteDatabase { url in
            let meeting = noteFixtureMeeting(1)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            let newer = noteFixture(meeting.id, text: "Synthetic newer edit", revision: 8)
            try await store.saveManualNote(newer)
            do {
                try await store.saveManualNote(noteFixture(meeting.id, text: "Synthetic delayed edit", revision: 7))
                XCTFail("An older revision must not silently replace newer manual work")
            } catch {
                XCTAssertEqual(error as? ManualNoteStoreError, .staleRevision)
            }
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let actual = try await reopened.manualNote(meetingID: meeting.id)
            XCTAssertEqual(actual, newer)
            try await reopened.close()
        }
    }

    func testManualNoteReplayIsIdempotentButConflictingSameRevisionIsRejected() async throws {
        try await withNoteDatabase { url in
            let meeting = noteFixtureMeeting(1)
            let store = try SQLiteMeetingStore(databaseURL: url)
            try await store.createMeeting(meeting)
            let original = noteFixture(meeting.id, text: "Synthetic original manual note", revision: 3)
            try await store.saveManualNote(original)
            try await store.saveManualNote(original)
            do {
                try await store.saveManualNote(noteFixture(meeting.id, text: "Same revision overwrite", revision: 3))
                XCTFail("Conflicting retry data must not rewrite an accepted revision")
            } catch {
                XCTAssertEqual(error as? ManualNoteStoreError, .revisionConflict)
            }
            let actual = try await store.manualNote(meetingID: meeting.id)
            XCTAssertEqual(actual, original)
            try await store.close()
        }
    }

    func testManualNotesRequireAnOwnedMeetingAndDeleteOnlyWithThatMeeting() async throws {
        try await withNoteDatabase { url in
            let first = noteFixtureMeeting(1)
            let second = noteFixtureMeeting(2)
            let store = try SQLiteMeetingStore(databaseURL: url)
            let firstNote = noteFixture(first.id, text: "Synthetic first note", revision: 1)
            do {
                try await store.saveManualNote(firstNote)
                XCTFail("A manual note must not create an orphan meeting")
            } catch { XCTAssertEqual(error as? MeetingStoreError, .notFound) }
            try await store.createMeeting(first)
            try await store.createMeeting(second)
            let secondNote = noteFixture(second.id, text: "Synthetic second note", revision: 1)
            try await store.saveManualNote(firstNote)
            try await store.saveManualNote(secondNote)
            try await store.renameMeeting(id: second.id, title: "Renamed synthetic meeting")
            try await store.deleteMeeting(id: first.id)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: url)
            let removed = try await reopened.manualNote(meetingID: first.id)
            let remaining = try await reopened.manualNote(meetingID: second.id)
            XCTAssertNil(removed)
            XCTAssertEqual(remaining, secondNote)
            try await reopened.close()
        }
    }
}

@MainActor
private func withNoteDatabase(_ body: @MainActor (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalMinutes-NoteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory.appendingPathComponent("notes.sqlite"))
}

private func noteFixtureMeeting(_ number: Int) -> MeetingRecord {
    MeetingRecord(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!,
        title: "Synthetic meeting", createdAt: Date(timeIntervalSince1970: 1_000),
        recordingState: .completed, capturedSampleCount: 64_000)
}

private func noteFixture(_ meetingID: UUID, text: String, revision: Int64) -> StoredManualNote {
    StoredManualNote(meetingID: meetingID, text: text, editRevision: revision,
                     modifiedAt: Date(timeIntervalSince1970: Double(revision) + 1_000))
}

private enum NoteFixtureError: Error { case sqlite }

private func createVersionOneNoteFixtureDatabase(_ url: URL) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
        if let handle { sqlite3_close(handle) }
        throw NoteFixtureError.sqlite
    }
    defer { sqlite3_close(handle) }
    // Version-one schema and fixed synthetic values only. This is
    // not generated through a new-version adapter that could hide migration loss.
    let sql = """
        CREATE TABLE meetings(id TEXT NOT NULL PRIMARY KEY,title TEXT NOT NULL,
            created_at REAL NOT NULL,recording_state TEXT NOT NULL
                CHECK(recording_state IN ('recording','completed','interrupted','recovered','failed')),
            captured_sample_count INTEGER NOT NULL CHECK(captured_sample_count>=0));
        CREATE TABLE transcript_segments(id TEXT NOT NULL PRIMARY KEY,
            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
            sequence INTEGER NOT NULL CHECK(sequence>=0),
            start_sample INTEGER NOT NULL CHECK(start_sample>=0),
            end_sample INTEGER NOT NULL CHECK(end_sample>=start_sample),
            text TEXT NOT NULL,model_revision TEXT NOT NULL,UNIQUE(meeting_id,sequence));
        CREATE INDEX meetings_history ON meetings(created_at DESC,id ASC);
        INSERT INTO meetings VALUES('00000000-0000-0000-0000-000000000001',
            'Synthetic meeting',1000,'completed',64000);
        PRAGMA user_version=1;
        """
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw NoteFixtureError.sqlite }
}

private func noteFixtureSchemaVersion(_ url: URL) throws -> Int32 {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          let handle else {
        if let handle { sqlite3_close(handle) }
        throw NoteFixtureError.sqlite
    }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
        throw NoteFixtureError.sqlite
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw NoteFixtureError.sqlite }
    return sqlite3_column_int(statement, 0)
}
