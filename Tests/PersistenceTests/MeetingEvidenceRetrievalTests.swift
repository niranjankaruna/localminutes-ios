import Foundation
import SQLite3
import XCTest
@testable import LocalMinutesPersistence

@MainActor
final class MeetingEvidenceRetrievalTests: XCTestCase {
    func testVersionTwoMigrationBuildsActualFTS5WithoutChangingOriginalMetadataNotesOrSource() async throws {
        try await withEvidenceDirectory { root in
            // Prove that this actual native SQLite can execute FTS5; a missing
            // native module must not be confused with app assertion RED.
            try withEvidenceSQLite(root.appendingPathComponent("probe.sqlite"), create: true) { db in
                try evidenceSQL(db, "CREATE VIRTUAL TABLE probe USING fts5(text); INSERT INTO probe VALUES('synthetic probe');")
                XCTAssertEqual(try evidenceScalar(db, "SELECT count(*) FROM probe WHERE probe MATCH 'probe'"), 1)
            }
            let database = root.appendingPathComponent("legacy.sqlite")
            try createVersionTwoEvidenceFixture(database)
            let store = try SQLiteMeetingStore(databaseURL: database)
            let original = evidenceSegment(10, meeting: 1, sequence: 0,
                start: 16_000, end: 32_000, text: "Original café evidence — planning 原文 📝.")
            let row = try await store.meeting(id: evidenceUUID(1))
            let note = try await store.manualNote(meetingID: evidenceUUID(1))
            let source = try await store.transcript(meetingID: evidenceUUID(1))
            XCTAssertEqual(row, MeetingRecord(id: evidenceUUID(1), title: "Original version-two meeting",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed, capturedSampleCount: 32_000))
            XCTAssertEqual(note, StoredManualNote(meetingID: evidenceUUID(1),
                text: "Original manual note — preserved", editRevision: 7, modifiedAt: Date(timeIntervalSince1970: 2_000)))
            XCTAssertEqual(source, [original])
            let found = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "cafe")
            XCTAssertEqual(found, [original], "Unicode token normalization must retain the exact original source value")
            try await store.close()
            try withEvidenceSQLite(database) { db in
                XCTAssertEqual(try evidenceScalar(db, "PRAGMA user_version"), 5)
                let sql = try evidenceText(db, "SELECT sql FROM sqlite_master WHERE name='transcript_fts'")
                XCTAssertNotNil(sql, "The actual on-disk FTS5 index must exist after migration")
                guard let sql else { return }
                let normalized = sql.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
                XCTAssertTrue(normalized.contains("create virtual table"))
                XCTAssertTrue(normalized.contains("using fts5"))
                XCTAssertEqual(try evidenceMatchCount(db, query: "cafe"), 1)
            }
        }
    }

    func testEvidenceQueriesKeepSelectedMeetingIsolationAndTreatOperatorsAndQuotesAsTerms() async throws {
        try await withEvidenceStore { store, _ in
            try await seedEvidenceMeeting(store, number: 1)
            try await seedEvidenceMeeting(store, number: 2)
            let selected = [
                evidenceSegment(10, meeting: 1, sequence: 0, text: "Synthetic example alpha OR beta remains original data."),
                evidenceSegment(11, meeting: 1, sequence: 1, text: "Synthetic phrase ' OR 1=1 -- is only data."),
                evidenceSegment(12, meeting: 1, sequence: 2, text: "Synthetic text NEAR(alpha beta) remains literal."),
                evidenceSegment(13, meeting: 1, sequence: 3, text: "Synthetic alpha details."),
                evidenceSegment(14, meeting: 1, sequence: 4, text: "Synthetic beta details.")
            ]
            try await store.appendFinalizedSegments(selected, to: evidenceUUID(1))
            let other = evidenceSegment(20, meeting: 2, sequence: 0,
                text: "Synthetic example alpha OR beta; NEAR(alpha beta); ' OR 1=1 -- is other meeting data.")
            try await store.appendFinalizedSegments([other], to: evidenceUUID(2))
            for (query, expected) in [("alpha OR beta", selected[0]),
                                      ("\"alpha\" OR \"beta\"", selected[0]),
                                      ("' OR 1=1 --", selected[1]),
                                      ("NEAR(alpha beta)", selected[2])] {
                let result = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: query)
                XCTAssertEqual(result, [expected], "User input is a conjunction of literal lexical terms, not FTS/SQL commands")
                XCTAssertTrue(result.allSatisfy { $0.meetingID == evidenceUUID(1) })
            }
            let missing = try await store.retrieveEvidence(meetingID: evidenceUUID(999), query: "alpha")
            XCTAssertTrue(missing.isEmpty)
            let preserved = try await store.meeting(id: evidenceUUID(2))
            XCTAssertNotNil(preserved)
        }
    }

    func testMultiwordEvidenceUsesUsefulRankAndSequenceTieBreakInsteadOfArrivalOrder() async throws {
        try await withEvidenceStore { store, _ in
            try await seedEvidenceMeeting(store, number: 1)
            let longText = "budget synthetic planning context notes with many unrelated words across the original meeting before the final launch"
            let firstTie = evidenceSegment(10, meeting: 1, sequence: 0, text: longText)
            let secondTie = evidenceSegment(11, meeting: 1, sequence: 1, text: longText)
            let strongest = evidenceSegment(12, meeting: 1, sequence: 2, text: "budget launch budget launch budget launch")
            let incomplete = evidenceSegment(13, meeting: 1, sequence: 3, text: "budget only")
            try await store.appendFinalizedSegments([secondTie, incomplete, strongest, firstTie], to: evidenceUUID(1))
            let found = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "budget launch")
            XCTAssertEqual(found, [strongest, firstTie, secondTie])
            let repeatQuery = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "BUDGET launch")
            XCTAssertEqual(repeatQuery, found)
        }
    }

    func testEvidenceLimitsAreBoundedAndEmptyOrPunctuationInputNeverReturnsAllRows() async throws {
        try await withEvidenceStore { store, _ in
            try await seedEvidenceMeeting(store, number: 1)
            let rows = (0..<21).map { evidenceSegment(100 + $0, meeting: 1, sequence: $0, text: "identical evidence anchor") }
            try await store.appendFinalizedSegments(Array(rows.reversed()), to: evidenceUUID(1))
            let defaultResult = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "anchor")
            let minimum = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "anchor", limit: 1)
            let maximum = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "anchor", limit: 20)
            XCTAssertEqual(defaultResult, Array(rows.prefix(8)))
            XCTAssertEqual(minimum, Array(rows.prefix(1)))
            XCTAssertEqual(maximum, Array(rows.prefix(20)))
            for query in ["", "  \n\t ", "\"'()[]{}*+-:^", "-- !!"] {
                let empty = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: query)
                XCTAssertTrue(empty.isEmpty)
            }
            for invalid in [-1, 0, 21, Int.max] {
                do {
                    _ = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "anchor", limit: invalid)
                    XCTFail("Out-of-range evidence limits must be rejected, not silently expanded")
                } catch { XCTAssertEqual(error as? MeetingStoreError, .invalidInput) }
            }
        }
    }

    func testFinalizedAppendIdempotenceAndReopenRetainExactUTF8EvidenceAndProvenance() async throws {
        try await withEvidenceStore { store, database in
            try await seedEvidenceMeeting(store, number: 1)
            let first = evidenceSegment(10, meeting: 1, sequence: 0, start: 20_000, end: 40_000,
                text: "Original café source 原文 📝.")
            let second = evidenceSegment(11, meeting: 1, sequence: 1, start: 64_000, end: 80_000,
                text: first.text)
            try await store.appendFinalizedSegments([first], to: evidenceUUID(1))
            let beforeAppend = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "cafe")
            XCTAssertEqual(beforeAppend, [first])
            try await store.appendFinalizedSegments([second, first], to: evidenceUUID(1))
            try await store.renameMeeting(id: evidenceUUID(1), title: "Renamed original meeting")
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            do {
                let actual = try await reopened.retrieveEvidence(meetingID: evidenceUUID(1), query: "CAFÉ")
                XCTAssertEqual(actual, [first, second])
                XCTAssertEqual(actual.map(\.id), [first.id, second.id])
                XCTAssertEqual(actual.map(\.startSample), [20_000, 64_000])
                XCTAssertEqual(actual.map(\.endSample), [40_000, 80_000])
                XCTAssertEqual(actual.map(\.modelRevision), [first.modelRevision, second.modelRevision])
                let note = try await reopened.manualNote(meetingID: evidenceUUID(1))
                XCTAssertEqual(note?.text, "Original synthetic manual note")
                let title = try await reopened.meeting(id: evidenceUUID(1))
                XCTAssertEqual(title?.title, "Renamed original meeting")
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }

    func testMeetingDeletionRemovesItsActualFTSIndexEntriesAndKeepsOtherEvidenceAfterReopen() async throws {
        try await withEvidenceStore { store, database in
            try await seedEvidenceMeeting(store, number: 1)
            try await seedEvidenceMeeting(store, number: 2)
            let first = evidenceSegment(10, meeting: 1, sequence: 0, text: "isolation survivor")
            let other = evidenceSegment(20, meeting: 2, sequence: 0, text: first.text)
            try await store.appendFinalizedSegments([first], to: evidenceUUID(1))
            try await store.appendFinalizedSegments([other], to: evidenceUUID(2))
            let selected = try await store.retrieveEvidence(meetingID: evidenceUUID(1), query: "isolation")
            XCTAssertEqual(selected, [first])
            try await store.deleteMeeting(id: evidenceUUID(1))
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            do {
                let removed = try await reopened.retrieveEvidence(meetingID: evidenceUUID(1), query: "isolation")
                let retained = try await reopened.retrieveEvidence(meetingID: evidenceUUID(2), query: "isolation")
                XCTAssertTrue(removed.isEmpty)
                XCTAssertEqual(retained, [other])
                let deletedNote = try await reopened.manualNote(meetingID: evidenceUUID(1))
                XCTAssertNil(deletedNote)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
            try withEvidenceSQLite(database) { db in
                XCTAssertEqual(try evidenceMatchCount(db, query: "isolation"), 1,
                    "Joining source rows alone must not hide orphan postings in the actual FTS index")
            }
        }
    }
}

@MainActor
private func seedEvidenceMeeting(_ store: SQLiteMeetingStore, number: Int) async throws {
    try await store.createMeeting(MeetingRecord(id: evidenceUUID(number), title: "Synthetic evidence meeting",
        createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
    try await store.saveManualNote(StoredManualNote(meetingID: evidenceUUID(number),
        text: "Original synthetic manual note", editRevision: 2, modifiedAt: Date(timeIntervalSince1970: 2_000)))
}

@MainActor
private func withEvidenceDirectory(_ body: @MainActor (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-fts-evidence-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    do { try await body(root) }
    catch { try? FileManager.default.removeItem(at: root); throw error }
    guard root.lastPathComponent.hasPrefix("localminutes-fts-evidence-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe evidence fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}

@MainActor
private func withEvidenceStore(_ body: @MainActor (SQLiteMeetingStore, URL) async throws -> Void) async throws {
    try await withEvidenceDirectory { root in
        let database = root.appendingPathComponent("meetings.sqlite")
        let store = try SQLiteMeetingStore(databaseURL: database)
        do { try await body(store, database) }
        catch { try? await store.close(); throw error }
        try? await store.close()
    }
}

private func evidenceUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

private func evidenceSegment(_ number: Int, meeting: Int, sequence: Int,
                              start: Int64 = 0, end: Int64 = 16_000,
                              text: String) -> StoredTranscriptSegment {
    StoredTranscriptSegment(id: evidenceUUID(number), meetingID: evidenceUUID(meeting), sequence: sequence,
        startSample: start, endSample: end, text: text, modelRevision: "synthetic-original-revision")
}

private enum EvidenceFixtureError: Error { case sqlite(Int32) }

private func withEvidenceSQLite<T>(_ url: URL, create: Bool = false,
                                   _ body: (OpaquePointer) throws -> T) throws -> T {
    var handle: OpaquePointer?
    let flags = create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
    let code = sqlite3_open_v2(url.path, &handle, flags, nil)
    guard code == SQLITE_OK, let handle else {
        if let handle { sqlite3_close(handle) }
        throw EvidenceFixtureError.sqlite(code)
    }
    defer { sqlite3_close(handle) }
    return try body(handle)
}

private func evidenceSQL(_ db: OpaquePointer, _ sql: String) throws {
    let code = sqlite3_exec(db, sql, nil, nil, nil)
    guard code == SQLITE_OK else { throw EvidenceFixtureError.sqlite(code) }
}

private func evidenceScalar(_ db: OpaquePointer, _ sql: String) throws -> Int64 {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard code == SQLITE_OK else { throw EvidenceFixtureError.sqlite(code) }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw EvidenceFixtureError.sqlite(SQLITE_ERROR) }
    return sqlite3_column_int64(statement, 0)
}

private func evidenceText(_ db: OpaquePointer, _ sql: String) throws -> String? {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
    guard code == SQLITE_OK else { throw EvidenceFixtureError.sqlite(code) }
    defer { sqlite3_finalize(statement) }
    switch sqlite3_step(statement) {
    case SQLITE_DONE: return nil
    case SQLITE_ROW:
        guard let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    default: throw EvidenceFixtureError.sqlite(SQLITE_ERROR)
    }
}

private func evidenceMatchCount(_ db: OpaquePointer, query: String) throws -> Int64 {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(db,
        "SELECT count(*) FROM transcript_fts WHERE transcript_fts MATCH ?", -1, &statement, nil)
    guard code == SQLITE_OK else { throw EvidenceFixtureError.sqlite(code) }
    defer { sqlite3_finalize(statement) }
    let bound = query.withCString {
        sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
        throw EvidenceFixtureError.sqlite(SQLITE_ERROR)
    }
    return sqlite3_column_int64(statement, 0)
}

private func createVersionTwoEvidenceFixture(_ url: URL) throws {
    try withEvidenceSQLite(url, create: true) { db in
        // Constant original non-sensitive fixture values only; source SQL is
        // never built from query/model/user data in this test setup.
        try evidenceSQL(db, """
            BEGIN;
            CREATE TABLE meetings(id TEXT NOT NULL PRIMARY KEY,title TEXT NOT NULL,created_at REAL NOT NULL,
                recording_state TEXT NOT NULL,captured_sample_count INTEGER NOT NULL CHECK(captured_sample_count>=0));
            CREATE TABLE transcript_segments(id TEXT NOT NULL PRIMARY KEY,
                meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                sequence INTEGER NOT NULL CHECK(sequence>=0),start_sample INTEGER NOT NULL CHECK(start_sample>=0),
                end_sample INTEGER NOT NULL CHECK(end_sample>=start_sample),text TEXT NOT NULL,
                model_revision TEXT NOT NULL,UNIQUE(meeting_id,sequence));
            CREATE INDEX meetings_history ON meetings(created_at DESC,id ASC);
            CREATE TABLE manual_notes(meeting_id TEXT NOT NULL PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,
                text TEXT NOT NULL,edit_revision INTEGER NOT NULL CHECK(edit_revision>=0),modified_at REAL NOT NULL);
            INSERT INTO meetings VALUES('00000000-0000-0000-0000-000000000001','Original version-two meeting',1000,'completed',32000);
            INSERT INTO transcript_segments VALUES('00000000-0000-0000-0000-000000000010',
                '00000000-0000-0000-0000-000000000001',0,16000,32000,
                'Original café evidence — planning 原文 📝.','synthetic-original-revision');
            INSERT INTO manual_notes VALUES('00000000-0000-0000-0000-000000000001','Original manual note — preserved',7,2000);
            PRAGMA user_version=2;
            COMMIT;
            """)
    }
}
