import Foundation
import Darwin
import SQLite3
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

public enum SQLiteSnapshotError: Error, Equatable, Sendable {
    case notImplemented, invalidDestination, destinationExists, unsafeDestination, databaseFailure
}

/// Snapshot contract for SQLiteMeetingStore.createSnapshot(at:):
/// - use SQLite's native consistent backup boundary, including committed WAL;
/// - publish one closed standalone database to a fresh, symlink-free path;
/// - preserve originals, source WAL and unrelated sibling files;
/// - honor cancellation before publication and clean only owned staging;
/// - perform no upload, schema migration, audio/model copying or app-root swap.
/// App-wide recording/playback admission and the later CAF archive composition
/// remain separate requirements. The actor invokes this synchronous helper;
/// its native connection never crosses an actor or task boundary.
enum SQLiteMeetingBackup {
    private enum Stage: String {
        case preflight, createStage, protectStage, createFile, closeCreatedFile, protectFile
        case openDatabase, configureDatabase, backupInit, backupStep, backupFinish, journalMode, closeDatabase
        case verifySidecars, protectCompletedFile, synchronizeFile, closeCompletedFile, validatePublication, publish
    }
    private struct Trace {
        var stage = Stage.preflight
        var nativeStatus: Int32 = 0
        var posixStatus: Int32 = 0
        var foundationStatus = 0
        var count = 0
    }
    /// Output is internal staging beneath the source database's owned parent.
    /// Sharing a finished archive to Files is a separate, explicit operation.
    static func create(from source: OpaquePointer, to requested: URL) throws {
        var trace = Trace()
        do { try perform(from: source, to: requested, trace: &trace) }
        catch {
#if DEBUG
            // Numeric, fixed-category failure metadata only. Never print SQL,
            // paths, source bytes, model output or arbitrary error descriptions.
            let category = error as? SQLiteSnapshotError
            if !(error is CancellationError), category == nil || category == .databaseFailure {
                let row = "SQLITE_SNAPSHOT_FAILURE stage=\(trace.stage.rawValue) native=\(trace.nativeStatus) posix=\(trace.posixStatus) foundation=\(trace.foundationStatus) count=\(trace.count)\n"
                try? FileHandle.standardError.write(contentsOf: Data(row.utf8))
            }
#endif
            throw error
        }
    }

    private static func perform(from source: OpaquePointer, to requested: URL, trace: inout Trace) throws {
        try Task.checkCancellation()
        guard requested.isFileURL, requested.query == nil, requested.fragment == nil,
              requested.host == nil || requested.host == "" || requested.host == "localhost",
              let sourceName = sqlite3_db_filename(source, "main") else {
            throw SQLiteSnapshotError.invalidDestination
        }
        let sourceURL = URL(fileURLWithPath: String(cString: sourceName)).standardizedFileURL
        let sourceRoot = sourceURL.deletingLastPathComponent()
        let destination = requested.standardizedFileURL
        let root = try ownedRoot(for: destination, sourceRoot: sourceRoot)
        let parent = destination.deletingLastPathComponent()
        try validateDestination(destination, parent: parent, within: root)
        do { try PersistentFilePolicy.validateItem(sourceURL, within: sourceRoot) }
        catch { throw SQLiteSnapshotError.unsafeDestination }

        let staging = parent.appendingPathComponent(".localminutes-snapshot-\(UUID().uuidString)", isDirectory: true)
        trace.stage = .createStage
        let made = staging.path.withCString { Darwin.mkdir($0, mode_t(0o700)) }
        if made != 0 { trace.posixStatus = errno }
        guard made == 0 else { throw SQLiteSnapshotError.databaseFailure }
        defer {
            // Delete only this fresh owned stage, never destination or source.
            do {
                try PersistentFilePolicy.validateItem(staging, within: root)
                try FileManager.default.removeItem(at: staging)
            } catch {}
        }
        trace.stage = .protectStage
        do { try PersistentFilePolicy.protectDirectory(staging) }
        catch { trace.foundationStatus = (error as NSError).code; throw SQLiteSnapshotError.databaseFailure }
        let temporary = staging.appendingPathComponent("database.sqlite")
        trace.stage = .createFile
        let descriptor = temporary.path.withCString {
            Darwin.open($0, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else { trace.posixStatus = errno; throw SQLiteSnapshotError.databaseFailure }
        trace.stage = .closeCreatedFile
        guard Darwin.close(descriptor) == 0 else { trace.posixStatus = errno; throw SQLiteSnapshotError.databaseFailure }
        trace.stage = .protectFile
        do { try PersistentFilePolicy.protectItem(temporary, within: staging) }
        catch { trace.foundationStatus = (error as NSError).code; throw SQLiteSnapshotError.databaseFailure }

        try copyDatabase(from: source, to: temporary, trace: &trace)
        try Task.checkCancellation()
        trace.stage = .verifySidecars
        let contents = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        trace.count = contents.count
        guard contents.count == 1, contents[0].lastPathComponent == "database.sqlite" else {
            throw SQLiteSnapshotError.databaseFailure
        }
        do {
            trace.stage = .protectCompletedFile
            try PersistentFilePolicy.protectItem(temporary, within: staging)
            let file = try FileHandle(forUpdating: temporary)
            do {
                trace.stage = .synchronizeFile
                try file.synchronize()
                trace.stage = .closeCompletedFile
                try file.close()
            } catch { try? file.close(); throw error }
        } catch { trace.foundationStatus = (error as NSError).code; throw SQLiteSnapshotError.databaseFailure }
        trace.stage = .validatePublication
        try validateDestination(destination, parent: parent, within: root)
        try PersistentFilePolicy.validateItem(temporary, within: staging)
        try Task.checkCancellation()
        // Exclusive rename is the final publication boundary. Unlike ordinary
        // rename it cannot replace a destination created after preflight.
        trace.stage = .publish
        let moved = temporary.path.withCString { old in
            destination.path.withCString { new in Darwin.renamex_np(old, new, UInt32(RENAME_EXCL)) }
        }
        if moved != 0 {
            let code = errno; trace.posixStatus = code
            throw code == EEXIST ? SQLiteSnapshotError.destinationExists : SQLiteSnapshotError.databaseFailure
        }
        // No throwing operation follows publication. A late cancellation can
        // retain this complete snapshot; it never replaces an existing file.
    }

    private static func ownedRoot(for destination: URL, sourceRoot: URL) throws -> URL {
        let canonicalSource = sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        var ancestor = destination.deletingLastPathComponent()
        while ancestor.path != "/" {
            if ancestor.resolvingSymlinksInPath().standardizedFileURL.path == canonicalSource {
                // Permit system ancestors such as /var -> /private/var while
                // retaining every owned child component for no-link preflight.
                // A user-created alias at the owned root itself is rejected.
                do { try PersistentFilePolicy.validateItem(ancestor, within: ancestor) }
                catch { throw SQLiteSnapshotError.unsafeDestination }
                return ancestor
            }
            ancestor.deleteLastPathComponent()
        }
        throw SQLiteSnapshotError.invalidDestination
    }

    private static func validateDestination(_ destination: URL, parent: URL, within root: URL) throws {
        do { try PersistentFilePolicy.validateItem(parent, within: root) }
        catch { throw SQLiteSnapshotError.unsafeDestination }
        let values = try URL(fileURLWithPath: parent.path).resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw SQLiteSnapshotError.unsafeDestination }
        do {
            // Attributes recognize dangling links. An existing path is never
            // overwritten, including the live database or an external inode.
            _ = try FileManager.default.attributesOfItem(atPath: destination.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return
        }
        do { try PersistentFilePolicy.validateItem(destination, within: root) }
        catch { throw SQLiteSnapshotError.unsafeDestination }
        throw SQLiteSnapshotError.destinationExists
    }

    private static func copyDatabase(from source: OpaquePointer, to file: URL, trace: inout Trace) throws {
        var connection: OpaquePointer?
        trace.stage = .openDatabase
        let opened = sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        trace.nativeStatus = opened
        guard opened == SQLITE_OK, let connection else {
            if let connection { sqlite3_close_v2(connection) }
            throw SQLiteSnapshotError.databaseFailure
        }
        var closed = false
        defer { if !closed { sqlite3_close_v2(connection) } }
        trace.stage = .configureDatabase
        trace.nativeStatus = sqlite3_busy_timeout(connection, 1_000)
        guard trace.nativeStatus == SQLITE_OK else { throw SQLiteSnapshotError.databaseFailure }
        try execute(connection, "PRAGMA synchronous=FULL; PRAGMA journal_mode=DELETE;", trace: &trace)
        try copyPages(from: source, to: connection, trace: &trace)
        try Task.checkCancellation()
        // The source may be WAL-backed. Finish the private destination in
        // DELETE mode so no external sidecar is needed to open the snapshot.
        trace.stage = .journalMode
        try execute(connection, "PRAGMA journal_mode=DELETE;", trace: &trace)
        guard try scalar(connection, "PRAGMA journal_mode", trace: &trace) == "delete" else {
            throw SQLiteSnapshotError.databaseFailure
        }
        trace.stage = .closeDatabase
        trace.nativeStatus = sqlite3_close(connection)
        guard trace.nativeStatus == SQLITE_OK else { throw SQLiteSnapshotError.databaseFailure }
        closed = true
    }

    private static func copyPages(from source: OpaquePointer, to destination: OpaquePointer, trace: inout Trace) throws {
        trace.stage = .backupInit
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            trace.nativeStatus = sqlite3_extended_errcode(destination)
            throw SQLiteSnapshotError.databaseFailure
        }
        var finished = false
        defer { if !finished { sqlite3_backup_finish(backup) } }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        var busyRetries = 0
        while true {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw SQLiteSnapshotError.databaseFailure }
            trace.stage = .backupStep
            let status = sqlite3_backup_step(backup, 64)
            trace.nativeStatus = status
            if status == SQLITE_DONE { break }
            if status == SQLITE_OK { continue }
            if (status == SQLITE_BUSY || status == SQLITE_LOCKED), busyRetries < 2 {
                busyRetries += 1
                sqlite3_sleep(25)
                continue
            }
            throw SQLiteSnapshotError.databaseFailure
        }
        trace.stage = .backupFinish
        let result = sqlite3_backup_finish(backup)
        trace.nativeStatus = result
        finished = true
        guard result == SQLITE_OK else { throw SQLiteSnapshotError.databaseFailure }
    }

    private static func execute(_ database: OpaquePointer, _ sql: String, trace: inout Trace) throws {
        trace.nativeStatus = sqlite3_exec(database, sql, nil, nil, nil)
        guard trace.nativeStatus == SQLITE_OK else { throw SQLiteSnapshotError.databaseFailure }
    }

    private static func scalar(_ database: OpaquePointer, _ sql: String, trace: inout Trace) throws -> String {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        trace.nativeStatus = result
        guard result == SQLITE_OK, let statement else { throw SQLiteSnapshotError.databaseFailure }
        defer { sqlite3_finalize(statement) }
        trace.nativeStatus = sqlite3_step(statement)
        guard trace.nativeStatus == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw SQLiteSnapshotError.databaseFailure
        }
        return String(cString: text)
    }
}
