import Foundation
import SQLite3
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesPersistence
#endif

public struct ActiveLibrarySelection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generationID: UUID
    public init(schemaVersion: Int = 1, generationID: UUID) {
        self.schemaVersion = schemaVersion; self.generationID = generationID
    }
}

public enum LibraryArchiveCoordinatorError: Error, Equatable, Sendable {
    case notImplemented, busy, invalidActivePointer, invalidBackup, metadataFailure, filesystemFailure
}

/// Models/ModelSelections/Diagnostics stay
/// at applicationRoot; only meetings.sqlite and Meetings belong to a generation.
@MainActor
public final class LibraryArchiveCoordinator {
    @MainActor
    private final class MaintenanceUse: HeavyModelResourceLifecycle {
        var cancelWork: (() -> Void)?
        var joinWork: (() async -> Void)?
        var settled = false
        var released = false
        func requestCancellation() { cancelWork?() }
        func drain() async throws { await joinWork?() }
        func unloadAndReleaseModel() async throws {
            guard settled else { throw HeavyModelAdmissionError.cleanupFailed }
            released = true
        }
    }

    private let applicationRoot: URL
    private let currentLibraryRoot: URL
    private let store: SQLiteMeetingStore
    private let usage: MeetingUsageRegistry
    private let admission: HeavyModelAdmission
    private let canMaintain: @MainActor () -> Bool
    private let afterMaintenance: (@Sendable () async -> Void)?
    private var currentUse: MaintenanceUse?

    public init(applicationRoot: URL, currentLibraryRoot: URL, store: SQLiteMeetingStore,
                usage: MeetingUsageRegistry, admission: HeavyModelAdmission,
                canMaintain: @escaping @MainActor () -> Bool) {
        self.applicationRoot = applicationRoot.standardizedFileURL
        self.currentLibraryRoot = currentLibraryRoot.standardizedFileURL
        self.store = store; self.usage = usage; self.admission = admission
        self.canMaintain = canMaintain; afterMaintenance = nil
    }

    // Scheduling only; never a fake snapshot, archive, database or inference.
    init(applicationRoot: URL, currentLibraryRoot: URL, store: SQLiteMeetingStore,
         usage: MeetingUsageRegistry, admission: HeavyModelAdmission,
         canMaintain: @escaping @MainActor () -> Bool,
         afterMaintenance: @escaping @Sendable () async -> Void) {
        self.applicationRoot = applicationRoot.standardizedFileURL
        self.currentLibraryRoot = currentLibraryRoot.standardizedFileURL
        self.store = store; self.usage = usage; self.admission = admission
        self.canMaintain = canMaintain; self.afterMaintenance = afterMaintenance
    }

    public func export(to archiveURL: URL) async throws -> MeetingArchiveManifest {
        try await withMaintenance { try await self.exportMaintained(to: archiveURL) }
    }
    public func restore(from archiveURL: URL) async throws -> URL {
        try await withMaintenance { try await self.restoreMaintained(from: archiveURL) }
    }

    private func withMaintenance<Value: Sendable>(
        _ body: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        guard currentUse == nil, canMaintain(), admission.snapshot().phase == .idle else {
            throw LibraryArchiveCoordinatorError.busy
        }
        let maintenance: LibraryMaintenanceLease
        do { maintenance = try usage.beginMaintenance() }
        catch { throw LibraryArchiveCoordinatorError.busy }
        let use = MaintenanceUse()
        let heavy: HeavyModelUseLease
        do { heavy = try admission.acquire(purpose: .libraryMaintenance, requestID: UUID(), resource: use) }
        catch { usage.endMaintenance(maintenance); throw LibraryArchiveCoordinatorError.busy }
        currentUse = use
        let work = Task { @MainActor in
            defer { use.settled = true }
            if let afterMaintenance = self.afterMaintenance { await afterMaintenance() }
            try Task.checkCancellation()
            guard self.canMaintain() else { throw LibraryArchiveCoordinatorError.busy }
            return try await body()
        }
        use.cancelWork = { work.cancel() }
        use.joinWork = { _ = await work.result }
        let result = await withTaskCancellationHandler {
            await work.result
        } onCancel: { work.cancel() }
        // A retained cleanup joins real work before releasing either admission.
        // It never joins a task that itself awaits this gate's drain.
        let cleanup = Task { @MainActor in
            do { try await self.admission.cancelAndDrain(heavy) }
            catch HeavyModelAdmissionError.staleLease where use.released { }
            self.usage.endMaintenance(maintenance)
            use.cancelWork = nil; use.joinWork = nil
            if self.currentUse === use { self.currentUse = nil }
        }
        do { try await cleanup.value }
        catch { throw LibraryArchiveCoordinatorError.filesystemFailure }
        return try result.get()
    }

    private func validateCurrentLibrary() throws {
        guard try Self.activeLibraryRoot(at: applicationRoot) == currentLibraryRoot else {
            throw LibraryArchiveCoordinatorError.invalidActivePointer
        }
        try Self.requireDirectory(currentLibraryRoot, within: applicationRoot)
        do { try PersistentFilePolicy.validateItem(currentLibraryRoot.appendingPathComponent("meetings.sqlite"), within: applicationRoot) }
        catch { throw LibraryArchiveCoordinatorError.metadataFailure }
    }

    private func exportMaintained(to archiveURL: URL) async throws -> MeetingArchiveManifest {
        try validateCurrentLibrary()
        let stage = currentLibraryRoot.appendingPathComponent(".library-export-\(UUID().uuidString)", isDirectory: true)
        do {
            guard try !Self.exists(stage) else { throw LibraryArchiveCoordinatorError.filesystemFailure }
            try Self.createDirectory(stage, within: applicationRoot)
        }
        catch { throw LibraryArchiveCoordinatorError.filesystemFailure }
        defer { try? FileManager.default.removeItem(at: stage) }
        do { try await store.createSnapshot(at: stage.appendingPathComponent("meetings.sqlite")) }
        catch is CancellationError { throw CancellationError() }
        catch { throw LibraryArchiveCoordinatorError.metadataFailure }
        let recordings = currentLibraryRoot.appendingPathComponent("Meetings", isDirectory: true)
        do {
            return try await Self.worker {
                try Self.copyRecordings(from: recordings, to: stage.appendingPathComponent("Meetings"), within: stage)
                return try MeetingArchive.export(snapshotRoot: stage, to: archiveURL)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw LibraryArchiveCoordinatorError.filesystemFailure }
    }

    private func restoreMaintained(from archiveURL: URL) async throws -> URL {
        try validateCurrentLibrary()
        do { _ = try await Self.worker { try MeetingArchive.inspect(archiveURL) } }
        catch is CancellationError { throw CancellationError() }
        catch { throw LibraryArchiveCoordinatorError.invalidBackup }
        try Task.checkCancellation()
        let generations = applicationRoot.appendingPathComponent("LibraryGenerations", isDirectory: true)
        do { try Self.createDirectory(generations, within: applicationRoot) }
        catch { throw LibraryArchiveCoordinatorError.invalidActivePointer }
        let generation = UUID()
        let destination = generations.appendingPathComponent(generation.uuidString, isDirectory: true)
        var committed = false
        var ownsCandidate = false
        defer { if ownsCandidate && !committed { try? FileManager.default.removeItem(at: destination) } }
        do {
            _ = try await Self.worker { try MeetingArchive.restore(from: archiveURL, to: destination) }
            ownsCandidate = true
        } catch is CancellationError { throw CancellationError() }
        catch { throw LibraryArchiveCoordinatorError.invalidBackup }
        let incoming: SQLiteMeetingStore
        do { incoming = try SQLiteMeetingStore(databaseURL: destination.appendingPathComponent("meetings.sqlite")) }
        catch { throw LibraryArchiveCoordinatorError.invalidBackup }
        do {
            _ = try await incoming.history(limit: 1)
            try await incoming.close()
            try await Self.worker { [applicationRoot] in
                try Self.validateDatabase(destination.appendingPathComponent("meetings.sqlite"), within: applicationRoot)
            }
        } catch {
            try? await incoming.close()
            if error is CancellationError { throw CancellationError() }
            throw LibraryArchiveCoordinatorError.invalidBackup
        }
        do {
            try Self.createDirectory(destination.appendingPathComponent("Meetings", isDirectory: true), within: applicationRoot)
            try PersistentFilePolicy.protectDirectory(destination)
            try validateCurrentLibrary()
        } catch { throw LibraryArchiveCoordinatorError.invalidActivePointer }
        let pointer = applicationRoot.appendingPathComponent("activeLibrary.json")
        let bytes = try JSONEncoder().encode(ActiveLibrarySelection(generationID: generation))
        try Task.checkCancellation()
        guard canMaintain() else { throw LibraryArchiveCoordinatorError.busy }
        // Everything untrusted has been validated and all candidate connections
        // closed. No cancellation check after this publication admission: late
        // cancellation cannot turn an activated generation into failed restore.
        do { try await store.close() }
        catch { throw LibraryArchiveCoordinatorError.metadataFailure }
        do { try PersistentFilePolicy.writeAtomically(bytes, to: pointer, within: applicationRoot) }
        catch { throw LibraryArchiveCoordinatorError.filesystemFailure }
        committed = true
        return destination
    }

    public static func activeLibraryRoot(at applicationRoot: URL) throws -> URL {
        let root = applicationRoot.standardizedFileURL
        do {
            try requireDirectory(root, within: root)
            let pointer = root.appendingPathComponent("activeLibrary.json")
            guard try exists(pointer) else { return root }
            try PersistentFilePolicy.validateItem(pointer, within: root)
            let metadata = try FileManager.default.attributesOfItem(atPath: pointer.path)
            guard metadata[.type] as? FileAttributeType == .typeRegular,
                  let count = metadata[.size] as? NSNumber, (1...4_096).contains(count.intValue) else {
                throw LibraryArchiveCoordinatorError.invalidActivePointer
            }
            let selection = try JSONDecoder().decode(ActiveLibrarySelection.self, from: Data(contentsOf: pointer))
            guard selection.schemaVersion == 1 else { throw LibraryArchiveCoordinatorError.invalidActivePointer }
            let destination = root.appendingPathComponent("LibraryGenerations/\(selection.generationID.uuidString)", isDirectory: true)
            try requireDirectory(destination, within: root)
            try validateDatabase(destination.appendingPathComponent("meetings.sqlite"), within: root)
            return destination
        } catch { throw LibraryArchiveCoordinatorError.invalidActivePointer }
    }

    nonisolated private static func worker<Value: Sendable>(
        _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: .utility) { try body() }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    nonisolated private static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return false }
    }

    nonisolated private static func requireDirectory(_ url: URL, within root: URL) throws {
        try PersistentFilePolicy.validateItem(url, within: root)
        let metadata = try FileManager.default.attributesOfItem(atPath: url.path)
        guard metadata[.type] as? FileAttributeType == .typeDirectory else { throw LibraryArchiveCoordinatorError.invalidActivePointer }
    }

    nonisolated private static func createDirectory(_ url: URL, within root: URL) throws {
        if try !exists(url) {
            try requireDirectory(url.deletingLastPathComponent(), within: root)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        try requireDirectory(url, within: root)
        try PersistentFilePolicy.protectItem(url, within: root)
    }

    nonisolated private static func copyRecordings(from source: URL, to destination: URL, within stage: URL) throws {
        guard try exists(source) else { return }
        try requireDirectory(source, within: source)
        var pending = [source]
        var items: [(URL, Bool)] = []
        var bytes: Int64 = 0
        while let item = pending.popLast() {
            try Task.checkCancellation()
            guard items.count < 16_384 else { throw LibraryArchiveCoordinatorError.invalidBackup }
            try PersistentFilePolicy.validateItem(item, within: source)
            let metadata = try FileManager.default.attributesOfItem(atPath: item.path)
            let directory = metadata[.type] as? FileAttributeType == .typeDirectory
            if directory {
                let children = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                if item.deletingLastPathComponent() == source, item.lastPathComponent == ".pending-deletions" {
                    // An empty control directory is not meeting payload. Any
                    // durable request still present must be reconciled first.
                    guard children.isEmpty else { throw LibraryArchiveCoordinatorError.busy }
                    continue
                }
                guard children.count <= 16_384 - items.count - pending.count else { throw LibraryArchiveCoordinatorError.invalidBackup }
                pending.append(contentsOf: children)
            } else {
                guard metadata[.type] as? FileAttributeType == .typeRegular,
                      let size = metadata[.size] as? NSNumber, (0...536_870_912).contains(size.int64Value),
                      bytes <= 8_589_934_592 - size.int64Value else { throw LibraryArchiveCoordinatorError.invalidBackup }
                bytes += size.int64Value
            }
            items.append((item, directory))
        }
        for (item, directory) in items {
            try Task.checkCancellation()
            try PersistentFilePolicy.validateItem(item, within: source)
            let suffix = item.path.dropFirst(source.path.count)
            let target = suffix.isEmpty ? destination : URL(fileURLWithPath: destination.path + String(suffix))
            if directory { try createDirectory(target, within: stage) }
            else {
                try FileManager.default.copyItem(at: item, to: target)
                try PersistentFilePolicy.protectItem(target, within: stage)
            }
        }
    }

    /// Structural validation uses the actual SQLite engine, never only a header.
    /// The native pointer is local to this synchronous scope and always closed.
    nonisolated private static func validateDatabase(_ url: URL, within root: URL) throws {
        try PersistentFilePolicy.validateItem(url, within: root)
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close_v2(database) }
            throw LibraryArchiveCoordinatorError.invalidBackup
        }
        defer { sqlite3_close_v2(database) }
        func check(_ sql: String, expectsOK: Bool) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LibraryArchiveCoordinatorError.invalidBackup
            }
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            if expectsOK {
                guard status == SQLITE_ROW, let value = sqlite3_column_text(statement, 0),
                      String(cString: value) == "ok", sqlite3_step(statement) == SQLITE_DONE else {
                    throw LibraryArchiveCoordinatorError.invalidBackup
                }
            } else if status != SQLITE_DONE { throw LibraryArchiveCoordinatorError.invalidBackup }
        }
        try check("PRAGMA quick_check", expectsOK: true)
        try check("PRAGMA foreign_key_check", expectsOK: false)
        try check("SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings LIMIT 0", expectsOK: false)
    }
}
