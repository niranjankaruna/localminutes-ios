import Foundation
import SQLite3
import XCTest
@testable import LocalMinutesPersistence

/// Real schema-four store and a real open WAL connection. No database,
/// filesystem, inference or audio boundary is replaced by a mock.
@MainActor
final class SQLiteSnapshotTests: XCTestCase {
    func testNativeSnapshotIncludesCommittedWALSourcesNotesGeneratedEditsAndFTSAsStandaloneDatabase() async throws {
        try await withSQLiteSnapshotFixture { fixture in
            let before = try fixture.sourceBytes()
            XCTAssertFalse(try XCTUnwrap(before["-wal"]).isEmpty, "Setup requires a real retained WAL")
            try await fixture.store.createSnapshot(at: fixture.destination)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.path))
            for suffix in ["-wal", "-shm", "-journal"] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path + suffix),
                               "A published snapshot must be a closed standalone database")
            }
            XCTAssertEqual(try snapshotScalar(fixture.destination, "PRAGMA integrity_check"), "ok")
            XCTAssertEqual(try snapshotScalar(fixture.destination, "PRAGMA user_version"), "4")
            try await fixture.assertSnapshotOriginals()
            XCTAssertEqual(try fixture.sourceBytes(), before, "Backup must not checkpoint or rewrite the live source")
        }
    }

    func testSnapshotIsIndependentOfLaterEditsAndCannotCopyOrMutateAdjacentModelsAndDiagnostics() async throws {
        try await withSQLiteSnapshotFixture { fixture in
            let protectedBytes = try fixture.siblingBytes()
            let protectedMetadata = try fixture.siblingMetadata()
            let before = try fixture.children()
            try await fixture.store.createSnapshot(at: fixture.destination)
            XCTAssertEqual(try fixture.children(), before.union([fixture.destination.lastPathComponent]),
                           "Only one owned database output may be published; no copied private tree or staging remains")
            XCTAssertEqual(try fixture.siblingBytes(), protectedBytes)
            XCTAssertEqual(try fixture.siblingMetadata(), protectedMetadata)
            let bytes = try Data(contentsOf: fixture.destination)
            for marker in protectedBytes.values {
                XCTAssertNil(bytes.range(of: marker), "Sibling model/diagnostic/credential files are not snapshot inputs")
            }
            try await fixture.store.renameMeeting(id: fixture.meetingID, title: "Later source title")
            try await fixture.store.saveManualNote(.init(meetingID: fixture.meetingID, text: "Later original manual note",
                editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 3_000)))
            _ = try await fixture.store.saveGeneratedDocumentEdit(id: fixture.documentID, meetingID: fixture.meetingID,
                text: "Later edited generated text", expectedRevision: 1, modifiedAt: Date(timeIntervalSince1970: 3_000))
            try await fixture.assertSnapshotOriginals()
            let current = try await fixture.store.manualNote(meetingID: fixture.meetingID)
            XCTAssertEqual(current?.text, "Later original manual note")
            let sourceAttributes = try FileManager.default.attributesOfItem(atPath: fixture.database.path)
            let snapshotAttributes = try FileManager.default.attributesOfItem(atPath: fixture.destination.path)
            XCTAssertEqual((snapshotAttributes[.referenceCount] as? NSNumber)?.intValue, 1)
            XCTAssertNotEqual(sourceAttributes[.systemFileNumber] as? NSNumber,
                              snapshotAttributes[.systemFileNumber] as? NSNumber, "Never publish a hardlink to the live source")
            XCTAssertEqual((snapshotAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testCancelledSnapshotPublishesNothingAndPreservesLiveDatabaseWALAndOutputSiblings() async throws {
        try await withSQLiteSnapshotFixture { fixture in
            let before = try fixture.sourceBytes()
            let children = try fixture.children()
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await fixture.store.createSnapshot(at: fixture.destination)
            }
            do { try await task.value; XCTFail("Cancellation before snapshot admission must throw") }
            catch is CancellationError {} catch { XCTFail("Expected CancellationError, got \(error)") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
            XCTAssertEqual(try fixture.sourceBytes(), before)
            XCTAssertEqual(try fixture.children(), children)
            let transcript = try await fixture.store.transcript(meetingID: fixture.meetingID)
            XCTAssertEqual(transcript, [fixture.segment])
        }
    }

    func testClosedStoreCannotCreateSnapshotOrModifyExistingSourceFiles() async throws {
        try await withSQLiteSnapshotFixture { fixture in
            try await fixture.store.close()
            let before = try fixture.sourceBytes()
            let children = try fixture.children()
            do { try await fixture.store.createSnapshot(at: fixture.destination); XCTFail("Closed connection must fail") }
            catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
            XCTAssertEqual(try fixture.sourceBytes(), before)
            XCTAssertEqual(try fixture.children(), children)
        }
    }

    func testExistingRemoteAndSymlinkDestinationsCannotOverwriteOrEscapeOwnedOutput() async throws {
        try await withSQLiteSnapshotFixture { fixture in
            let before = try fixture.sourceBytes()
            let sentinel = Data("Original existing destination — do not overwrite.".utf8)
            try sentinel.write(to: fixture.destination)
            await expectSQLiteSnapshotError(.destinationExists) {
                try await fixture.store.createSnapshot(at: fixture.destination)
            }
            XCTAssertEqual(try Data(contentsOf: fixture.destination), sentinel)
            await expectSQLiteSnapshotError(.destinationExists) {
                try await fixture.store.createSnapshot(at: fixture.database)
            }
            await expectSQLiteSnapshotError(.invalidDestination) {
                try await fixture.store.createSnapshot(at: URL(string: "https://example.invalid/private-snapshot")!)
            }
            let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            let external = outside.appendingPathComponent("original-private-file")
            try sentinel.write(to: external)
            let alias = fixture.root.appendingPathComponent("Alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
            let link = fixture.root.appendingPathComponent("linked.sqlite")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
            let children = try fixture.children()
            for target in [alias.appendingPathComponent("snapshot.sqlite"), link] {
                await expectSQLiteSnapshotError(.unsafeDestination) {
                    try await fixture.store.createSnapshot(at: target)
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("snapshot.sqlite").path))
            XCTAssertEqual(try Data(contentsOf: external), sentinel)
            XCTAssertEqual(try fixture.children(), children)
            XCTAssertEqual(try fixture.sourceBytes(), before)
            // Remove fixture-owned links before recursive fixture cleanup.
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.removeItem(at: link)
        }
    }
}

@MainActor
private func expectSQLiteSnapshotError(_ expected: SQLiteSnapshotError,
    file: StaticString = #filePath, line: UInt = #line,
    _ operation: @MainActor () async throws -> Void) async {
    do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
    catch { XCTAssertEqual(error as? SQLiteSnapshotError, expected, file: file, line: line) }
}

private enum SnapshotFixtureError: Error { case sqlite(Int32), unsafeCleanup }
private func snapshotSQL(_ database: OpaquePointer, _ sql: String) throws {
    let code = sqlite3_exec(database, sql, nil, nil, nil)
    guard code == SQLITE_OK else { throw SnapshotFixtureError.sqlite(code) }
}
private func snapshotScalar(_ url: URL, _ sql: String) throws -> String {
    var handle: OpaquePointer?
    let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
    guard code == SQLITE_OK, let handle else {
        if let handle { sqlite3_close(handle) }
        throw SnapshotFixtureError.sqlite(code)
    }
    defer { sqlite3_close(handle) }
    return try snapshotScalar(handle, sql)
}
private func snapshotScalar(_ handle: OpaquePointer, _ sql: String) throws -> String {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard code == SQLITE_OK, let statement else { throw SnapshotFixtureError.sqlite(code) }
    defer { sqlite3_finalize(statement) }
    let stepped = sqlite3_step(statement)
    guard stepped == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
        throw SnapshotFixtureError.sqlite(stepped)
    }
    return String(cString: text)
}

@MainActor
private final class SQLiteSnapshotFixture {
    let root: URL
    let database: URL
    let destination: URL
    let store: SQLiteMeetingStore
    let meetingID = UUID()
    let segmentID = UUID()
    let documentID = UUID()
    var heldWAL: OpaquePointer?
    init(root: URL, database: URL, destination: URL, store: SQLiteMeetingStore) {
        self.root = root; self.database = database; self.destination = destination; self.store = store
    }
    var meeting: MeetingRecord {
        .init(id: meetingID, title: "Original synthetic snapshot meeting", createdAt: Date(timeIntervalSince1970: 1_000),
              recordingState: .completed, capturedSampleCount: 16_000)
    }
    var segment: StoredTranscriptSegment {
        .init(id: segmentID, meetingID: meetingID, sequence: 0, startSample: 0, endSample: 16_000,
              text: "Original planning source — café 原文.", modelRevision: "synthetic-asr-revision")
    }
    var note: StoredManualNote {
        .init(meetingID: meetingID, text: "Original manual notes — Cafe\u{301} 📝.", editRevision: 0,
              modifiedAt: Date(timeIntervalSince1970: 1_000))
    }
    var document: StoredGeneratedDocument {
        .init(id: documentID, meetingID: meetingID, kind: .summary,
              originalJSON: Data("{\"schemaVersion\":1,\"text\":\"Synthetic generated transport\"}".utf8),
              question: nil, editedText: "Original generated display text", modelRevision: String(repeating: "a", count: 40),
              promptVersion: "synthetic-snapshot-fixture", createdAt: Date(timeIntervalSince1970: 1_000),
              modifiedAt: Date(timeIntervalSince1970: 1_000))
    }
    let editedGeneratedText = "User-edited generated text — kept separately."
    var siblingPaths: [String] { ["Models/private-model.gguf", "Diagnostics/raw.txt", "Credentials/secret-marker.txt"] }

    func prepare() async throws {
        var connection: OpaquePointer?
        let code = sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READWRITE, nil)
        guard code == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw SnapshotFixtureError.sqlite(code)
        }
        heldWAL = connection
        try snapshotSQL(connection, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        XCTAssertEqual(try snapshotScalar(connection, "PRAGMA journal_mode"), "wal")
        try await store.createMeeting(meeting)
        try await store.appendFinalizedSegments([segment], to: meetingID)
        try await store.saveManualNote(note)
        try await store.createGeneratedDocument(document)
        _ = try await store.saveGeneratedDocumentEdit(id: documentID, meetingID: meetingID,
            text: editedGeneratedText, expectedRevision: 0, modifiedAt: Date(timeIntervalSince1970: 2_000))
        for (index, path) in siblingPaths.enumerated() {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("Synthetic sibling marker \(index), never a model or credential.".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = false
            var fresh = URL(fileURLWithPath: file.path); try fresh.setResourceValues(values)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path + "-wal"))
        XCTAssertFalse(try Data(contentsOf: URL(fileURLWithPath: database.path + "-wal")).isEmpty)
    }
    func sourceBytes() throws -> [String: Data] {
        ["": try Data(contentsOf: database),
         "-wal": try Data(contentsOf: URL(fileURLWithPath: database.path + "-wal"))]
    }
    func siblingBytes() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: siblingPaths.map { ($0, try Data(contentsOf: root.appendingPathComponent($0))) })
    }
    func siblingMetadata() throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: siblingPaths.map { path in
            let url = root.appendingPathComponent(path)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            let excluded = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
            return (path, "\(permissions?.intValue ?? -1):\(String(describing: excluded))")
        })
    }
    func children() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) }
    func assertSnapshotOriginals() async throws {
        let reopened = try SQLiteMeetingStore(databaseURL: destination)
        do {
            let restoredMeeting = try await reopened.meeting(id: meetingID)
            let restoredSegments = try await reopened.transcript(meetingID: meetingID)
            let restoredNote = try await reopened.manualNote(meetingID: meetingID)
            let generated = try await reopened.generatedDocument(id: documentID, meetingID: meetingID)
            let found = try await reopened.retrieveEvidence(meetingID: meetingID, query: "planning")
            XCTAssertEqual(restoredMeeting, meeting)
            XCTAssertEqual(restoredSegments, [segment])
            XCTAssertEqual(Data(try XCTUnwrap(restoredNote).text.utf8), Data(note.text.utf8))
            XCTAssertEqual(restoredNote, note)
            XCTAssertEqual(generated?.originalJSON, document.originalJSON)
            XCTAssertEqual(generated?.editedText, editedGeneratedText)
            XCTAssertEqual(generated?.editRevision, 1)
            XCTAssertEqual(found, [segment], "The real FTS index and source UUID/ranges must remain consistent")
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }
    func cleanup() async throws {
        try? await store.close()
        if let connection = heldWAL { sqlite3_close_v2(connection); heldWAL = nil }
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.deletingLastPathComponent().path == parent.path,
              root.resolvingSymlinksInPath().standardizedFileURL.path == root.path,
              root.lastPathComponent.hasPrefix("LocalMinutesSQLiteSnapshot-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("LocalMinutesSQLiteSnapshot-".count))) != nil else {
            throw SnapshotFixtureError.unsafeCleanup
        }
        try FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func withSQLiteSnapshotFixture(_ body: @MainActor (SQLiteSnapshotFixture) async throws -> Void) async throws {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    let root = parent.appendingPathComponent("LocalMinutesSQLiteSnapshot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let database = root.appendingPathComponent("meetings.sqlite")
    let store = try SQLiteMeetingStore(databaseURL: database)
    let fixture = SQLiteSnapshotFixture(root: root, database: database,
        destination: root.appendingPathComponent("snapshot.sqlite"), store: store)
    do { try await fixture.prepare(); try await body(fixture); try await fixture.cleanup() }
    catch { try? await fixture.cleanup(); throw error }
}
