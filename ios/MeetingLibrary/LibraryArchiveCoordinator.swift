import Foundation
import SQLite3
import AVFoundation
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
    case busy, invalidActivePointer, invalidBackup, metadataFailure, filesystemFailure
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

    public func exportLocalSync(to destination: URL, sourceID: UUID) async throws -> LocalSyncManifest {
        try await withMaintenance {
            try self.validateCurrentLibrary()
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw LocalSyncError.invalidData }
            try Self.createDirectory(destination, within: self.applicationRoot)
            try await self.store.exportSyncRecords(to: destination.appendingPathComponent("records.jsonl"))
            return try await Self.worker { [currentLibraryRoot = self.currentLibraryRoot] in
                try LocalSyncArchive.copyMedia(from: currentLibraryRoot, to: destination)
                return try LocalSyncArchive.seal(destination, sourceID: sourceID)
            }
        }
    }

    /// Merge into a candidate built from the entire existing library. Publication reuses the proven generation pointer boundary.
    public func mergeLocalSync(from source: URL) async throws -> URL {
        try await withMaintenance {
            try self.validateCurrentLibrary()
            let manifest = try await Self.worker { try LocalSyncArchive.validate(source) }
            let digest = try LocalSyncArchive.digest(source.appendingPathComponent("manifest.json"))
            if let previous = try await self.store.syncReceipt(transferID: manifest.transferId) {
                guard previous == digest else { throw LocalSyncError.identityCollision }; return self.currentLibraryRoot
            }
            let generations = self.applicationRoot.appendingPathComponent("LibraryGenerations", isDirectory: true)
            try Self.createDirectory(generations, within: self.applicationRoot)
            let generation = UUID()
            let candidate = generations.appendingPathComponent(generation.uuidString, isDirectory: true)
            try Self.createDirectory(candidate, within: self.applicationRoot)
            var published = false
            defer { if !published { try? FileManager.default.removeItem(at: candidate) } }
            try await self.store.createSnapshot(at: candidate.appendingPathComponent("meetings.sqlite"))
            try await Self.worker { [currentLibraryRoot = self.currentLibraryRoot] in
                try LocalSyncArchive.copyMedia(from: currentLibraryRoot, to: candidate)
                let checkpoints = currentLibraryRoot.appendingPathComponent("SummaryCheckpoints")
                if FileManager.default.fileExists(atPath: checkpoints.path) {
                    if let entries = FileManager.default.enumerator(at: checkpoints, includingPropertiesForKeys: nil) {
                        for case let item as URL in entries { try PersistentFilePolicy.validateItem(item, within: currentLibraryRoot) }
                    }
                    try FileManager.default.copyItem(at: checkpoints, to: candidate.appendingPathComponent("SummaryCheckpoints"))
                }
                try Self.mergeSyncMedia(source: source, destination: candidate, manifest: manifest)
            }
            let incoming = try SQLiteMeetingStore(databaseURL: candidate.appendingPathComponent("meetings.sqlite"))
            do {
                try await incoming.applySyncRecords(from: source.appendingPathComponent("records.jsonl"), manifest: manifest, digest: digest)
                try await incoming.close()
                try Self.validateDatabase(candidate.appendingPathComponent("meetings.sqlite"), within: self.applicationRoot)
            } catch { try? await incoming.close(); throw error }
            try Self.createDirectory(candidate.appendingPathComponent("Meetings", isDirectory: true), within: self.applicationRoot)
            try PersistentFilePolicy.protectDirectory(candidate)
            try self.validateCurrentLibrary(); try Task.checkCancellation()
            guard self.canMaintain() else { throw LocalSyncError.busy }
            try await self.store.close()
            try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(ActiveLibrarySelection(generationID: generation)),
                to: self.applicationRoot.appendingPathComponent("activeLibrary.json"), within: self.applicationRoot)
            published = true
            return candidate
        }
    }

    nonisolated private static func mergeSyncMedia(source: URL, destination: URL, manifest: LocalSyncManifest) throws {
        for file in manifest.files where file.relativePath != "records.jsonl" {
            let incoming = try LocalSyncArchive.file(file.relativePath, within: source)
            let target = try LocalSyncArchive.file(file.relativePath, within: destination)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                if try LocalSyncArchive.digest(target) == file.sha256 { continue }
                guard !file.relativePath.hasSuffix(".caf") else { throw LocalSyncError.identityCollision }
                if file.relativePath.hasSuffix("/capture-manifest.json") {
                    guard var existing = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any],
                          let new = try JSONSerialization.jsonObject(with: Data(contentsOf: incoming)) as? [String: Any],
                          existing["schemaVersion"] as? Int == 1, new["schemaVersion"] as? Int == 1,
                          existing["sessionID"] as? String == new["sessionID"] as? String,
                          let oldSegments = existing["segments"] as? [[String: Any]], let newSegments = new["segments"] as? [[String: Any]] else { throw LocalSyncError.invalidData }
                    var segments: [String: [String: Any]] = [:]
                    for segment in oldSegments + newSegments {
                        guard let path = segment["relativePath"] as? String else { throw LocalSyncError.invalidData }
                        if let old = segments[path], !NSDictionary(dictionary: old).isEqual(to: segment) { throw LocalSyncError.identityCollision }
                        segments[path] = segment
                    }
                    let ordered = segments.values.sorted { ($0["startFrame"] as? Int64 ?? -1) < ($1["startFrame"] as? Int64 ?? -1) }
                    existing["segments"] = ordered
                    if let last = ordered.last, let start = last["startFrame"] as? Int64, let count = last["frameCount"] as? Int64 {
                        let end = start.addingReportingOverflow(count); guard !end.overflow else { throw LocalSyncError.invalidData }; existing["totalFrames"] = end.partialValue
                    }
                    try PersistentFilePolicy.writeAtomically(JSONSerialization.data(withJSONObject: existing), to: target, within: destination)
                    continue
                }
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: incoming, to: target)
            try PersistentFilePolicy.protectItem(target, within: destination)
        }
        for entry in manifest.files where entry.relativePath.hasSuffix("/capture-manifest.json") {
            let url = try LocalSyncArchive.file(entry.relativePath, within: destination)
            guard let capture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], capture["schemaVersion"] as? Int == 1,
                  let segments = capture["segments"] as? [[String: Any]], let total = capture["totalFrames"] as? Int64 else { throw LocalSyncError.invalidData }
            var end: Int64 = 0
            for segment in segments {
                guard let name = segment["relativePath"] as? String, name.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil,
                      let start = segment["startFrame"] as? Int64, let frames = segment["frameCount"] as? Int64,
                      start >= end, (0...960_000).contains(frames) else { throw LocalSyncError.invalidData }
                let addition = start.addingReportingOverflow(frames); guard !addition.overflow else { throw LocalSyncError.invalidData }; end = addition.partialValue
                let audio = try AVAudioFile(forReading: url.deletingLastPathComponent().appendingPathComponent(name))
                guard audio.length == frames, audio.fileFormat.sampleRate == 16_000, audio.fileFormat.channelCount == 1 else { throw LocalSyncError.integrityMismatch }
            }
            guard end == total else { throw LocalSyncError.integrityMismatch }
        }
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
        catch {
            Self.traceExportFailure(error, phase: "snapshot")
            throw LibraryArchiveCoordinatorError.metadataFailure
        }
        let recordings = currentLibraryRoot.appendingPathComponent("Meetings", isDirectory: true)
        do {
            return try await Self.worker {
                do { try Self.copyRecordings(from: recordings, to: stage.appendingPathComponent("Meetings", isDirectory: true), within: stage) }
                catch { Self.traceExportFailure(error, phase: "copy"); throw error }
                do { return try MeetingArchive.export(snapshotRoot: stage, to: archiveURL) }
                catch { Self.traceExportFailure(error, phase: "archive"); throw error }
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
        var pending = [""]
        var items: [(String, Bool)] = []
        var bytes: Int64 = 0
        while let relative = pending.popLast() {
            try Task.checkCancellation()
            guard items.count < 16_384 else { throw LibraryArchiveCoordinatorError.invalidBackup }
            let item = relative.isEmpty ? source : source.appendingPathComponent(relative)
            try PersistentFilePolicy.validateItem(item, within: source)
            let metadata = try FileManager.default.attributesOfItem(atPath: item.path)
            let directory = metadata[.type] as? FileAttributeType == .typeDirectory
            if directory {
                let children = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                if relative == ".pending-deletions" {
                    // An empty control directory is not meeting payload. Any
                    // durable request still present must be reconciled first.
                    guard children.isEmpty else { throw LibraryArchiveCoordinatorError.busy }
                    continue
                }
                guard children.count <= 16_384 - items.count - pending.count else { throw LibraryArchiveCoordinatorError.invalidBackup }
                // Foundation may return child URLs with canonical/relative bases
                // or different directory hints. Carry validated relative names;
                // never derive output paths by subtracting raw URL strings.
                pending.append(contentsOf: children.map { child in
                    relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                })
            } else {
                guard metadata[.type] as? FileAttributeType == .typeRegular,
                      let size = metadata[.size] as? NSNumber, (0...536_870_912).contains(size.int64Value),
                      bytes <= 8_589_934_592 - size.int64Value else { throw LibraryArchiveCoordinatorError.invalidBackup }
                bytes += size.int64Value
            }
            items.append((relative, directory))
        }
        for (relative, directory) in items {
            try Task.checkCancellation()
            let item = relative.isEmpty ? source : source.appendingPathComponent(relative)
            try PersistentFilePolicy.validateItem(item, within: source)
            let target = relative.isEmpty ? destination : destination.appendingPathComponent(relative, isDirectory: directory)
            if directory { try createDirectory(target, within: stage) }
            else {
                try FileManager.default.copyItem(at: item, to: target)
                try PersistentFilePolicy.protectItem(target, within: stage)
            }
        }
    }

    nonisolated private static func traceExportFailure(_ error: Error, phase: String) {
#if DEBUG
        // Only fixed phases and typed error codes. Never paths, IDs, audio,
        // database messages, user text or NSError userInfo.
        if let error = error as? MeetingArchiveError {
            print("LIBRARY_EXPORT_BOUNDARY phase=\(phase) archive=\(error)")
        } else if let error = error as? LibraryArchiveCoordinatorError {
            print("LIBRARY_EXPORT_BOUNDARY phase=\(phase) library=\(error)")
        } else if let error = error as? MeetingStoreError {
            print("LIBRARY_EXPORT_BOUNDARY phase=\(phase) metadata=\(error)")
        } else if let error = error as? PersistentFilePolicyError {
            print("LIBRARY_EXPORT_BOUNDARY phase=\(phase) policy=\(error)")
        } else {
            let code = (error as NSError).code
            print("LIBRARY_EXPORT_BOUNDARY phase=\(phase) ioCode=\(code)")
        }
#endif
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
