import Foundation
import SQLite3
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// Non-Sendable native owner. Created inside, retained only by, and synchronously
/// accessed through SQLiteMeetingStore. Its destructor handles abandoned stores
/// without giving actor deinit access to a non-Sendable C pointer. No global
/// connection, pointer transfer, background task or unchecked Sendable is used.
final class MeetingSQLiteConnection {
    private var handle: OpaquePointer?

    init(databaseURL: URL) throws {
        guard databaseURL.isFileURL, !databaseURL.path.isEmpty else {
            throw MeetingStoreError.invalidInput
        }
        let directory = databaseURL.deletingLastPathComponent()
        do {
            // A database URL confers ownership of its exact SQLite files,
            // not the parent or every unrelated source beside the database.
            // Default App Services performs its own whole-app migration.
            try PersistentFilePolicy.validateItem(directory, within: directory)
            try Self.protectDatabaseFiles(at: databaseURL, within: directory)
        }
        catch { throw MeetingStoreError.databaseFailure }
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw MeetingStoreError.databaseFailure
        }
        handle = opened
        do {
            let version = try schemaVersion()
            guard version == 0 || version == 1 || version == 2 || version == 3 || version == 4 else {
                throw MeetingStoreError.unsupportedSchemaVersion(Int(version))
            }
            try PersistentFilePolicy.protectItem(databaseURL, within: directory)
            // Future schema detection precedes all persistent schema mutations.
            guard sqlite3_busy_timeout(opened, 1_000) == SQLITE_OK else {
                throw MeetingStoreError.databaseFailure
            }
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA synchronous=FULL")
            if version == 0 {
                try transaction {
                    try execute("""
                        CREATE TABLE meetings(
                            id TEXT NOT NULL PRIMARY KEY,
                            title TEXT NOT NULL,
                            created_at REAL NOT NULL,
                            recording_state TEXT NOT NULL CHECK(recording_state IN ('recording','completed','interrupted','recovered','failed')),
                            captured_sample_count INTEGER NOT NULL CHECK(captured_sample_count>=0)
                        )
                        """)
                    try execute("""
                        CREATE TABLE transcript_segments(
                            id TEXT NOT NULL PRIMARY KEY,
                            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                            sequence INTEGER NOT NULL CHECK(sequence>=0),
                            start_sample INTEGER NOT NULL CHECK(start_sample>=0),
                            end_sample INTEGER NOT NULL CHECK(end_sample>=start_sample),
                            text TEXT NOT NULL,
                            model_revision TEXT NOT NULL,
                            UNIQUE(meeting_id,sequence)
                        )
                        """)
                    try execute("CREATE INDEX meetings_history ON meetings(created_at DESC,id ASC)")
                    try execute("PRAGMA user_version=1")
                }
            }
            if version < 2 {
                try transaction {
                    try execute("""
                        CREATE TABLE manual_notes(
                            meeting_id TEXT NOT NULL PRIMARY KEY REFERENCES meetings(id) ON DELETE CASCADE,
                            text TEXT NOT NULL,
                            edit_revision INTEGER NOT NULL CHECK(edit_revision>=0),
                            modified_at REAL NOT NULL
                        )
                        """)
                    try execute("PRAGMA user_version=2")
                }
            }
            if version < 3 {
                try transaction {
                    // Text has one source of truth. The index resolves its
                    // integer docids to the original transcript row, whose UUID,
                    // meeting, media range and model revision remain unchanged.
                    try execute("""
                        CREATE VIRTUAL TABLE transcript_fts USING fts5(
                            text, content='transcript_segments', content_rowid='rowid',
                            tokenize='unicode61 remove_diacritics 2'
                        )
                        """)
                    try execute("""
                        CREATE TRIGGER transcript_segments_fts_insert AFTER INSERT ON transcript_segments BEGIN
                            INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text);
                        END
                        """)
                    try execute("""
                        CREATE TRIGGER transcript_segments_fts_delete AFTER DELETE ON transcript_segments BEGIN
                            INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text);
                        END
                        """)
                    try execute("""
                        CREATE TRIGGER transcript_segments_fts_update AFTER UPDATE ON transcript_segments BEGIN
                            INSERT INTO transcript_fts(transcript_fts,rowid,text) VALUES('delete',old.rowid,old.text);
                            INSERT INTO transcript_fts(rowid,text) VALUES(new.rowid,new.text);
                        END
                        """)
                    // Triggers maintain subsequent source changes; rebuild
                    // indexes all preexisting v1/v2 finalized rows exactly once.
                    try execute("INSERT INTO transcript_fts(transcript_fts) VALUES('rebuild')")
                    try execute("PRAGMA user_version=3")
                }
            }
            if version < 4 {
                try transaction {
                    // Generated originals and user edits have their own meeting
                    // ownership. This migration never rewrites source text,
                    // manual notes, or the existing external-content FTS index.
                    try execute("""
                        CREATE TABLE generated_documents(
                            id TEXT NOT NULL PRIMARY KEY,
                            meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                            kind TEXT NOT NULL CHECK(kind IN ('summary','question_answer')),
                            original_json BLOB NOT NULL CHECK(length(original_json) BETWEEN 1 AND 1048576),
                            question TEXT,
                            edited_text TEXT NOT NULL,
                            edit_revision INTEGER NOT NULL CHECK(edit_revision>=0),
                            model_revision TEXT NOT NULL,
                            prompt_version TEXT NOT NULL,
                            created_at REAL NOT NULL,
                            modified_at REAL NOT NULL
                        )
                        """)
                    try execute("CREATE INDEX generated_documents_history ON generated_documents(meeting_id,created_at DESC,id ASC)")
                    try execute("PRAGMA user_version=4")
                }
            }
            try Self.protectDatabaseFiles(at: databaseURL, within: directory)
        } catch {
            sqlite3_close_v2(opened)
            handle = nil
            throw error
        }
    }

    private static func protectDatabaseFiles(at database: URL, within directory: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let item = URL(fileURLWithPath: database.path + suffix)
            // fileExists follows links and is false for a dangling link. That
            // case must still reach the policy's strict ownership validation.
            let symbolic = try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
            if FileManager.default.fileExists(atPath: item.path) || symbolic == true {
                try PersistentFilePolicy.protectItem(item, within: directory)
            }
        }
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func database() throws -> OpaquePointer {
        guard let handle else { throw MeetingStoreError.closed }
        return handle
    }

    func execute(_ sql: String) throws {
        let statement = try MeetingSQLiteStatement(database: database(), sql: sql)
        try statement.finish()
    }

    private func schemaVersion() throws -> Int64 {
        let statement = try MeetingSQLiteStatement(database: database(), sql: "PRAGMA user_version")
        guard try statement.next() else { throw MeetingStoreError.databaseFailure }
        // Keeping this statement inside its own scope releases its read before
        // initial schema creation begins and before a schema transaction commits.
        return try statement.integer(at: 0)
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            // Rollback must not replace the original typed validation/conflict.
            try? execute("ROLLBACK")
            throw error
        }
    }

    func close() throws {
        guard let handle else { return }
        guard sqlite3_close(handle) == SQLITE_OK else { throw MeetingStoreError.databaseFailure }
        self.handle = nil
    }
}

/// Every statement is finalized on scope exit, including errors and rollback.
/// Bound UTF-8 values are copied by SQLite before their temporary Swift storage
/// goes away. SQLite error messages/content/paths never escape this layer.
final class MeetingSQLiteStatement {
    private let handle: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw MeetingStoreError.databaseFailure
        }
        handle = statement
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ value: String, at index: Int32) throws {
        guard let length = Int32(exactly: value.utf8.count) else {
            throw MeetingStoreError.invalidInput
        }
        let result = value.withCString { bytes in
            sqlite3_bind_text(handle, index, bytes, length,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard result == SQLITE_OK else { throw MeetingStoreError.databaseFailure }
    }

    func bind(_ value: Int64, at index: Int32) throws {
        guard sqlite3_bind_int64(handle, index, value) == SQLITE_OK else {
            throw MeetingStoreError.databaseFailure
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        if let value { try bind(value, at: index) }
        else if sqlite3_bind_null(handle, index) != SQLITE_OK { throw MeetingStoreError.databaseFailure }
    }

    func bind(_ value: Data, at index: Int32) throws {
        guard let length = Int32(exactly: value.count) else { throw MeetingStoreError.invalidInput }
        let result: Int32
        if value.isEmpty { result = sqlite3_bind_zeroblob(handle, index, 0) }
        else {
            result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(handle, index, bytes.baseAddress, length,
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        guard result == SQLITE_OK else { throw MeetingStoreError.databaseFailure }
    }

    func bind(_ value: Double, at index: Int32) throws {
        guard sqlite3_bind_double(handle, index, value) == SQLITE_OK else {
            throw MeetingStoreError.databaseFailure
        }
    }

    func next() throws -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw MeetingStoreError.databaseFailure
        }
    }

    func finish() throws {
        if try next() { throw MeetingStoreError.databaseFailure }
    }

    func text(at index: Int32) throws -> String {
        guard sqlite3_column_type(handle, index) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(handle, index) else {
            throw MeetingStoreError.databaseFailure
        }
        let length = Int(sqlite3_column_bytes(handle, index))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    func integer(at index: Int32) throws -> Int64 {
        guard sqlite3_column_type(handle, index) == SQLITE_INTEGER else {
            throw MeetingStoreError.databaseFailure
        }
        return sqlite3_column_int64(handle, index)
    }

    func optionalText(at index: Int32) throws -> String? {
        if sqlite3_column_type(handle, index) == SQLITE_NULL { return nil }
        return try text(at: index)
    }

    func blob(at index: Int32, maximumBytes: Int) throws -> Data {
        guard sqlite3_column_type(handle, index) == SQLITE_BLOB else { throw MeetingStoreError.databaseFailure }
        let length = Int(sqlite3_column_bytes(handle, index))
        guard maximumBytes >= 0, length >= 0, length <= maximumBytes else { throw MeetingStoreError.databaseFailure }
        guard length > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(handle, index) else { throw MeetingStoreError.databaseFailure }
        return Data(bytes: bytes, count: length)
    }

    func real(at index: Int32) throws -> Double {
        let type = sqlite3_column_type(handle, index)
        guard type == SQLITE_FLOAT || type == SQLITE_INTEGER else {
            throw MeetingStoreError.databaseFailure
        }
        return sqlite3_column_double(handle, index)
    }
}
