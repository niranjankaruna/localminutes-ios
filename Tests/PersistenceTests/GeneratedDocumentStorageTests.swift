import Foundation
import SQLite3
import XCTest
@testable import LocalMinutesPersistence

/// Actual on-disk SQLite only. All content is original synthetic test data.
/// These are persistence tests, not model inference or grounding evidence.
@MainActor
final class GeneratedDocumentStorageTests: XCTestCase {
    func testVersionThreeMigrationAddsSeparateGeneratedStorageWithoutChangingOriginalsOrFTS() async throws {
        try await withGeneratedStorageFixture { fixture in
            let meeting = try await fixture.store.meeting(id: fixture.selected)
            let source = try await fixture.store.transcript(meetingID: fixture.selected)
            let note = try await fixture.store.manualNote(meetingID: fixture.selected)
            let evidence = try await fixture.store.retrieveEvidence(meetingID: fixture.selected, query: "original planning")
            let documents = try await fixture.store.generatedDocuments(meetingID: fixture.selected)
            XCTAssertEqual(meeting, generatedStorageMeeting(1))
            XCTAssertEqual(source, [generatedStorageSegment(1)])
            XCTAssertEqual(note, generatedStorageNote(1))
            XCTAssertEqual(evidence, source)
            XCTAssertTrue(documents.isEmpty)
            try await fixture.store.close()
            try withGeneratedStorageSQLite(fixture.database) { database in
                XCTAssertEqual(try generatedStorageScalar(database, "PRAGMA user_version"), 5)
                XCTAssertEqual(try generatedStorageScalar(database,
                    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='generated_documents'"), 1,
                    "A separate durable table is required; never repurpose manual_notes/transcript_segments")
                XCTAssertEqual(try generatedStorageScalar(database,
                    "SELECT count(*) FROM transcript_fts WHERE transcript_fts MATCH 'planning'"), 2)
                XCTAssertEqual(try generatedStorageScalar(database, "SELECT count(*) FROM manual_notes"), 2)
                XCTAssertEqual(try generatedStorageScalar(database, "SELECT count(*) FROM transcript_segments"), 2)
            }
        }
    }

    func testSummaryAndQuestionAnswerOriginalsEditsAndProvenanceSurviveReopenSeparately() async throws {
        try await withGeneratedStorageFixture { fixture in
            let summary = try generatedStorageDocument(100, meeting: 1, kind: .summary)
            let answer = try generatedStorageDocument(101, meeting: 1, kind: .questionAnswer)
            let other = try generatedStorageDocument(200, meeting: 2, kind: .summary)
            for document in [summary, answer, other] { try await fixture.store.createGeneratedDocument(document) }
            let editedSummary = generatedStorageEdited(summary, text: "My edited summary — 原文.", revision: 1,
                at: Date(timeIntervalSince1970: 6_000))
            let editedAnswer = generatedStorageEdited(answer, text: "My edited answer — café.", revision: 1,
                at: Date(timeIntervalSince1970: 5_000))
            for edited in [editedSummary, editedAnswer] {
                do {
                    let committed = try await fixture.store.saveGeneratedDocumentEdit(id: edited.id,
                        meetingID: fixture.selected, text: edited.editedText, expectedRevision: 0,
                        modifiedAt: edited.modifiedAt)
                    XCTAssertEqual(committed, edited)
                } catch { XCTFail("Generated edit must commit before reopen: \(error)") }
            }
            try await fixture.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            do {
                let restoredSummary = try await reopened.generatedDocument(id: summary.id, meetingID: fixture.selected)
                let restoredAnswer = try await reopened.generatedDocument(id: answer.id, meetingID: fixture.selected)
                let summaries = try await reopened.generatedDocuments(meetingID: fixture.selected, kind: .summary)
                let answers = try await reopened.generatedDocuments(meetingID: fixture.selected, kind: .questionAnswer)
                let all = try await reopened.generatedDocuments(meetingID: fixture.selected)
                let wrongMeeting = try await reopened.generatedDocument(id: other.id, meetingID: fixture.selected)
                XCTAssertEqual(restoredSummary, editedSummary); XCTAssertEqual(restoredAnswer, editedAnswer)
                XCTAssertEqual(restoredSummary?.originalJSON, summary.originalJSON,
                    "Generated UTF-8 payload bytes and source references must round-trip without normalization")
                XCTAssertEqual(summaries, [editedSummary]); XCTAssertEqual(answers, [editedAnswer])
                XCTAssertEqual(all, [editedAnswer, editedSummary],
                    "Order uses immutable createdAt descending, not latest edit time, then UUID ascending")
                XCTAssertNil(wrongMeeting)
                let original = try await reopened.manualNote(meetingID: fixture.selected)
                let source = try await reopened.transcript(meetingID: fixture.selected)
                XCTAssertEqual(original, generatedStorageNote(1)); XCTAssertEqual(source, [generatedStorageSegment(1)])
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }

    func testOptimisticEditsRejectLateRevisionOriginalReplacementAndWrongMeetingWithoutLosingLatest() async throws {
        try await withGeneratedStorageFixture { fixture in
            let original = try generatedStorageDocument(100, meeting: 1, kind: .summary)
            try await fixture.store.createGeneratedDocument(original)
            let changedAt = Date(timeIntervalSince1970: 4_000)
            let expected = generatedStorageEdited(original, text: "My edited generated summary — 原文 📝", revision: 1, at: changedAt)
            do {
                let saved = try await fixture.store.saveGeneratedDocumentEdit(id: original.id, meetingID: fixture.selected,
                    text: expected.editedText, expectedRevision: 0, modifiedAt: changedAt)
                XCTAssertEqual(saved, expected)
            } catch { XCTFail("The first compare-and-swap edit must commit: \(error)") }
            do {
                _ = try await fixture.store.saveGeneratedDocumentEdit(id: original.id, meetingID: fixture.selected,
                    text: "Late autosave must not win", expectedRevision: 0, modifiedAt: Date(timeIntervalSince1970: 5_000))
                XCTFail("A delayed edit based on revision zero replaced revision one")
            } catch { XCTAssertEqual(error as? GeneratedDocumentStoreError, .staleRevision) }
            let replacement = StoredGeneratedDocument(id: original.id, meetingID: original.meetingID,
                kind: original.kind, originalJSON: Data("{\"forged\":true}".utf8), question: nil,
                editedText: "Replacement", modelRevision: original.modelRevision, promptVersion: original.promptVersion,
                createdAt: original.createdAt, modifiedAt: original.modifiedAt)
            do {
                try await fixture.store.createGeneratedDocument(replacement)
                XCTFail("Reusing an ID must not replace immutable generated provenance/source payload")
            } catch { XCTAssertEqual(error as? GeneratedDocumentStoreError, .immutableConflict) }
            do {
                _ = try await fixture.store.saveGeneratedDocumentEdit(id: original.id, meetingID: fixture.other,
                    text: "Wrong selected meeting", expectedRevision: 1, modifiedAt: changedAt)
                XCTFail("An edit must be scoped to the selected meeting as well as document UUID")
            } catch { XCTAssertEqual(error as? GeneratedDocumentStoreError, .notFound) }
            let latest = try await fixture.store.generatedDocument(id: original.id, meetingID: fixture.selected)
            let notes = try await fixture.store.manualNote(meetingID: fixture.selected)
            let source = try await fixture.store.transcript(meetingID: fixture.selected)
            XCTAssertEqual(latest, expected); XCTAssertEqual(notes, generatedStorageNote(1))
            XCTAssertEqual(source, [generatedStorageSegment(1)])
            try await fixture.store.close()
            do {
                _ = try await fixture.store.generatedDocument(id: original.id, meetingID: fixture.selected)
                XCTFail("A closed SQLite connection is a real failure, not a successful empty result")
            } catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
        }
    }

    func testSelectedMeetingDeletionCascadesBothGeneratedKindsAndPreservesOtherMeetingAfterReopen() async throws {
        try await withGeneratedStorageFixture { fixture in
            let selectedSummary = try generatedStorageDocument(100, meeting: 1, kind: .summary)
            let selectedAnswer = try generatedStorageDocument(101, meeting: 1, kind: .questionAnswer)
            let other = try generatedStorageDocument(200, meeting: 2, kind: .questionAnswer)
            for document in [selectedSummary, selectedAnswer, other] {
                try await fixture.store.createGeneratedDocument(document)
            }
            try await fixture.store.deleteMeeting(id: fixture.selected)
            try await fixture.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            do {
                let documents = try await reopened.generatedDocuments(meetingID: fixture.selected)
                let removedSummary = try await reopened.generatedDocument(id: selectedSummary.id, meetingID: fixture.selected)
                let removedAnswer = try await reopened.generatedDocument(id: selectedAnswer.id, meetingID: fixture.selected)
                let remaining = try await reopened.generatedDocuments(meetingID: fixture.other)
                let meeting = try await reopened.meeting(id: fixture.other)
                let source = try await reopened.transcript(meetingID: fixture.other)
                let note = try await reopened.manualNote(meetingID: fixture.other)
                XCTAssertTrue(documents.isEmpty); XCTAssertNil(removedSummary); XCTAssertNil(removedAnswer)
                XCTAssertEqual(remaining, [other]); XCTAssertEqual(meeting, generatedStorageMeeting(2))
                XCTAssertEqual(source, [generatedStorageSegment(2)]); XCTAssertEqual(note, generatedStorageNote(2))
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
            try withGeneratedStorageSQLite(fixture.database) { database in
                let exists = try generatedStorageScalar(database,
                    "SELECT count(*) FROM sqlite_master WHERE name='generated_documents'")
                XCTAssertEqual(exists, 1)
                if exists == 1 {
                    XCTAssertEqual(try generatedStorageScalar(database, "SELECT count(*) FROM generated_documents"), 1,
                        "Delete must remove the actual rows, not hide them in a read projection")
                }
            }
        }
    }
}

private struct GeneratedStorageFixture {
    let database: URL
    let store: SQLiteMeetingStore
    let selected: UUID
    let other: UUID
}

@MainActor
private func withGeneratedStorageFixture(_ body: (GeneratedStorageFixture) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.standardizedFileURL
        .appendingPathComponent("localminutes-generated-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = root.appendingPathComponent("meetings.sqlite")
    try createGeneratedStorageVersionThreeFixture(database)
    let store = try SQLiteMeetingStore(databaseURL: database)
    do {
        try await body(.init(database: database, store: store, selected: generatedStorageUUID(1), other: generatedStorageUUID(2)))
        try await store.close()
    } catch { try? await store.close(); throw error }
}

private func generatedStorageUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
}

private func generatedStorageMeeting(_ number: Int) -> MeetingRecord {
    .init(id: generatedStorageUUID(number), title: "Original synthetic meeting \(number)",
          createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed, capturedSampleCount: 32_000)
}

private func generatedStorageSegment(_ number: Int) -> StoredTranscriptSegment {
    .init(id: generatedStorageUUID(10 + number), meetingID: generatedStorageUUID(number), sequence: 0,
          startSample: 16_000, endSample: 32_000, text: "Original planning café source \(number) — 原文 📝.",
          modelRevision: "synthetic-asr-revision")
}

private func generatedStorageNote(_ number: Int) -> StoredManualNote {
    .init(meetingID: generatedStorageUUID(number), text: "Original manual note \(number) — unchanged.",
          editRevision: 7, modifiedAt: Date(timeIntervalSince1970: 2_000))
}

private func generatedStorageDocument(_ number: Int, meeting: Int,
                                      kind: GeneratedDocumentKind) throws -> StoredGeneratedDocument {
    let source = generatedStorageSegment(meeting)
    let question: String? = kind == .questionAnswer ? "What planning source was recorded?" : nil
    let payload = ["meeting_id": source.meetingID.uuidString, "source_id": source.id.uuidString,
                   "kind": kind.rawValue, "quote": source.text, "question": question ?? "",
                   "unicode_probe": "é | e\u{301}"]
    return .init(id: generatedStorageUUID(number), meetingID: source.meetingID, kind: kind,
        originalJSON: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]),
        question: question, editedText: "Original generated display \(number) — café.",
        modelRevision: "synthetic-qwen-revision", promptVersion: "synthetic-prompt-v1",
        createdAt: Date(timeIntervalSince1970: 3_000 + Double(number)),
        modifiedAt: Date(timeIntervalSince1970: 3_000 + Double(number)))
}

private func generatedStorageEdited(_ original: StoredGeneratedDocument, text: String,
                                    revision: Int64, at modifiedAt: Date) -> StoredGeneratedDocument {
    .init(id: original.id, meetingID: original.meetingID, kind: original.kind,
          originalJSON: original.originalJSON, question: original.question, editedText: text, editRevision: revision,
          modelRevision: original.modelRevision, promptVersion: original.promptVersion,
          createdAt: original.createdAt, modifiedAt: modifiedAt)
}

private enum GeneratedStorageFixtureError: Error { case sqlite(Int32) }

private func withGeneratedStorageSQLite<T>(_ url: URL, create: Bool = false,
                                            _ body: (OpaquePointer) throws -> T) throws -> T {
    var database: OpaquePointer?
    let code = sqlite3_open_v2(url.path, &database,
        create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY, nil)
    guard code == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw GeneratedStorageFixtureError.sqlite(code)
    }
    defer { sqlite3_close(database) }
    return try body(database)
}

private func generatedStorageScalar(_ database: OpaquePointer, _ sql: String) throws -> Int64 {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard code == SQLITE_OK else { throw GeneratedStorageFixtureError.sqlite(code) }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw GeneratedStorageFixtureError.sqlite(SQLITE_ERROR) }
    return sqlite3_column_int64(statement, 0)
}

private func createGeneratedStorageVersionThreeFixture(_ url: URL) throws {
    try withGeneratedStorageSQLite(url, create: true) { database in
        // This is a complete constant legacy v3 fixture. Do not create it using
        // the current store and then merely relabel user_version=3.
        let sql = """
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
        CREATE VIRTUAL TABLE transcript_fts USING fts5(text,content='transcript_segments',content_rowid='rowid',
            tokenize='unicode61 remove_diacritics 2');
        CREATE TRIGGER transcript_segments_fts_insert AFTER INSERT ON transcript_segments BEGIN
            INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text); END;
        CREATE TRIGGER transcript_segments_fts_delete AFTER DELETE ON transcript_segments BEGIN
            INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text); END;
        CREATE TRIGGER transcript_segments_fts_update AFTER UPDATE ON transcript_segments BEGIN
            INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text);
            INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text); END;
        INSERT INTO meetings VALUES('00000000-0000-0000-0000-000000000001','Original synthetic meeting 1',1000,'completed',32000);
        INSERT INTO meetings VALUES('00000000-0000-0000-0000-000000000002','Original synthetic meeting 2',1000,'completed',32000);
        INSERT INTO transcript_segments VALUES('00000000-0000-0000-0000-000000000011',
            '00000000-0000-0000-0000-000000000001',0,16000,32000,'Original planning café source 1 — 原文 📝.','synthetic-asr-revision');
        INSERT INTO transcript_segments VALUES('00000000-0000-0000-0000-000000000012',
            '00000000-0000-0000-0000-000000000002',0,16000,32000,'Original planning café source 2 — 原文 📝.','synthetic-asr-revision');
        INSERT INTO manual_notes VALUES('00000000-0000-0000-0000-000000000001','Original manual note 1 — unchanged.',7,2000);
        INSERT INTO manual_notes VALUES('00000000-0000-0000-0000-000000000002','Original manual note 2 — unchanged.',7,2000);
        PRAGMA user_version=3;
        COMMIT;
        """
        let code = sqlite3_exec(database, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw GeneratedStorageFixtureError.sqlite(code) }
    }
}
