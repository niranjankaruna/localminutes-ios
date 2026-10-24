import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesPersistence
import LocalMinutesRecording
#endif

public enum MeetingDeletionError: Error, Equatable, Sendable {
    case meetingInUse
    case unsafePath
    case invalidOwnership
    case metadataFailure
    case filesystemFailure
}

public struct MeetingRecordingLease: Sendable {
    public let meetingID: UUID
    let token: UUID
}

/// Shared app-lifetime admission. Recording must reserve before preparation and
/// release only after audio/transcript/activity cleanup has fully settled.
@MainActor
public final class MeetingUsageRegistry {
    private struct DeletionUse {
        let token: UUID
        var pending: Bool
    }
    private var recordings: [UUID: UUID] = [:]
    private var deletions: [UUID: DeletionUse] = [:]
    private var startupReady: Bool

    public init(requiresStartup: Bool = false) { startupReady = !requiresStartup }

    public func completeStartup(success: Bool) { startupReady = success }
    public func beginRecording(meetingID: UUID) throws -> MeetingRecordingLease {
        guard startupReady, recordings[meetingID] == nil, deletions[meetingID] == nil else {
            throw MeetingDeletionError.meetingInUse
        }
        let token = UUID()
        recordings[meetingID] = token
        return MeetingRecordingLease(meetingID: meetingID, token: token)
    }
    public func endRecording(_ lease: MeetingRecordingLease) {
        guard recordings[lease.meetingID] == lease.token else { return }
        recordings.removeValue(forKey: lease.meetingID)
    }

    fileprivate func beginDeletion(meetingID: UUID) throws -> UUID {
        guard recordings[meetingID] == nil else { throw MeetingDeletionError.meetingInUse }
        if let previous = deletions[meetingID], !previous.pending {
            throw MeetingDeletionError.meetingInUse
        }
        let token = UUID()
        deletions[meetingID] = DeletionUse(token: token, pending: false)
        return token
    }

    fileprivate func keepDeletionPending(meetingID: UUID, token: UUID) {
        guard deletions[meetingID]?.token == token else { return }
        deletions[meetingID]?.pending = true
    }

    fileprivate func endDeletion(meetingID: UUID, token: UUID) {
        guard deletions[meetingID]?.token == token else { return }
        deletions.removeValue(forKey: meetingID)
    }
}

extension MeetingUsageRegistry: RecordingUsageAdmission {
    public func acquireRecordingUsage(meetingID: UUID) -> UUID? {
        try? beginRecording(meetingID: meetingID).token
    }
    public func releaseRecordingUsage(meetingID: UUID, token: UUID) {
        endRecording(MeetingRecordingLease(meetingID: meetingID, token: token))
    }
}

/// A confirmed UUID-only request remains recoverable until real SQLite commit
/// and owned audio cleanup both settle. It never follows manifest-provided paths.
public actor MeetingDeletionCoordinator {
    private struct Request: Codable {
        let schemaVersion: Int
        let meetingID: UUID
    }
    private let store: SQLiteMeetingStore
    private let recordingsRoot: URL
    private let usage: MeetingUsageRegistry
    private let beforeMetadataDeletion: (@Sendable () async -> Void)?
    private var inFlight: Set<UUID> = []

    public init(store: SQLiteMeetingStore, recordingsRoot: URL,
                usage: MeetingUsageRegistry) {
        self.store = store
        self.recordingsRoot = recordingsRoot
        self.usage = usage
        beforeMetadataDeletion = nil
    }

    // A bounded test scheduling boundary only, never a fake database. Production
    // construction above supplies no hook. Tests close the real SQLite adapter.
    init(store: SQLiteMeetingStore, recordingsRoot: URL, usage: MeetingUsageRegistry,
         beforeMetadataDeletion: @escaping @Sendable () async -> Void) {
        self.store = store
        self.recordingsRoot = recordingsRoot
        self.usage = usage
        self.beforeMetadataDeletion = beforeMetadataDeletion
    }

    public func delete(meetingID: UUID) async throws {
        _ = try await performDeletion(meetingID: meetingID, recoveryOnly: false)
    }

    public func recoverPendingDeletions() async throws -> [UUID] {
        guard let root = try checkedRoot(create: false) else { return [] }
        let pending = root.appendingPathComponent(".pending-deletions", isDirectory: true)
        guard try attributes(pending) != nil else { return [] }
        try checkedTree(pending, within: root)
        let entries = try directoryContents(pending).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var recovered: [UUID] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), id.uuidString == entry.lastPathComponent,
                  try attributes(entry)?[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingDeletionError.invalidOwnership
            }
            let marker = entry.appendingPathComponent("request.json")
            if try attributes(marker) == nil {
                // A failure before marker publication may leave an empty stage.
                // It is not authority to delete any meeting or audio content.
                guard try directoryContents(entry).isEmpty else {
                    throw MeetingDeletionError.invalidOwnership
                }
                try await removeEmptyStage(entry, meetingID: id, root: root)
                continue
            }
            if try await performDeletion(meetingID: id, recoveryOnly: true) { recovered.append(id) }
        }
        return recovered
    }

    private func performDeletion(meetingID: UUID, recoveryOnly: Bool) async throws -> Bool {
        guard inFlight.insert(meetingID).inserted else { throw MeetingDeletionError.meetingInUse }
        defer { inFlight.remove(meetingID) }
        let token = try await usage.beginDeletion(meetingID: meetingID)
        var intentPublished = false
        do {
            let meeting: MeetingRecord?
            do { meeting = try await store.meeting(id: meetingID) }
            catch { throw MeetingDeletionError.metadataFailure }
            guard let root = try checkedRoot(create: meeting != nil) else {
                await usage.endDeletion(meetingID: meetingID, token: token)
                return false
            }
            let original = root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
            let pending = root.appendingPathComponent(".pending-deletions", isDirectory: true)
            let requestDirectory = pending.appendingPathComponent(meetingID.uuidString, isDirectory: true)
            let marker = requestDirectory.appendingPathComponent("request.json")
            let audio = requestDirectory.appendingPathComponent("audio", isDirectory: true)
            if try attributes(marker) != nil {
                try validateRequest(marker, meetingID: meetingID, root: root)
                intentPublished = true
            } else if recoveryOnly {
                throw MeetingDeletionError.invalidOwnership
            }
            let hasOriginal = try attributes(original) != nil
            let hasQuarantine = try attributes(audio) != nil
            guard !(hasOriginal && hasQuarantine) else { throw MeetingDeletionError.invalidOwnership }
            if !intentPublished && meeting == nil {
                guard !hasOriginal, !hasQuarantine else { throw MeetingDeletionError.invalidOwnership }
                await usage.endDeletion(meetingID: meetingID, token: token)
                return false
            }
            if hasOriginal {
                try validateAudio(original, meetingID: meetingID, root: root,
                                  permitIncomplete: meeting == nil && intentPublished)
            }
            if hasQuarantine {
                try validateAudio(audio, meetingID: meetingID, root: root,
                                  permitIncomplete: meeting == nil && intentPublished)
            }
            // The policy preflights the entire tree before changing protection.
            // Ownership/manifest validation above precedes staging and moves.
            try PersistentFilePolicy.protectDirectory(root)
            try createPrivateDirectory(pending, root: root)
            try createPrivateDirectory(requestDirectory, root: root)
            if !intentPublished {
                let request = Request(schemaVersion: 1, meetingID: meetingID)
                try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(request), to: marker, within: root)
                intentPublished = true
            }
            if hasOriginal {
                // Both paths are within one owned root. No copy/delete fallback
                // may report success if the source cannot be quarantined.
                try FileManager.default.moveItem(at: original, to: audio)
                try PersistentFilePolicy.protectDirectory(audio)
            }
            if let beforeMetadataDeletion { await beforeMetadataDeletion() }
            do { try await store.deleteMeeting(id: meetingID) }
            catch { throw MeetingDeletionError.metadataFailure }
            // Keep the marker until all audio is gone. A partial recursive purge
            // cannot erase the retry intent before it erases the owned bytes.
            if try attributes(audio) != nil {
                try checkedTree(audio, within: root)
                try FileManager.default.removeItem(at: audio)
            }
            try checkedTree(requestDirectory, within: root)
            let leftovers = try directoryContents(requestDirectory)
            guard leftovers.allSatisfy({ $0.lastPathComponent == "request.json" }) else {
                throw MeetingDeletionError.invalidOwnership
            }
            if try attributes(marker) != nil { try FileManager.default.removeItem(at: marker) }
            try FileManager.default.removeItem(at: requestDirectory)
            await usage.endDeletion(meetingID: meetingID, token: token)
            return true
        } catch {
            if intentPublished { await usage.keepDeletionPending(meetingID: meetingID, token: token) }
            else { await usage.endDeletion(meetingID: meetingID, token: token) }
            if let failure = error as? MeetingDeletionError { throw failure }
            throw MeetingDeletionError.filesystemFailure
        }
    }

    private func removeEmptyStage(_ entry: URL, meetingID: UUID, root: URL) async throws {
        let token = try await usage.beginDeletion(meetingID: meetingID)
        do {
            do { _ = try await store.meeting(id: meetingID) }
            catch { throw MeetingDeletionError.metadataFailure }
            try checkedTree(entry, within: root)
            guard try directoryContents(entry).isEmpty else { throw MeetingDeletionError.invalidOwnership }
            try FileManager.default.removeItem(at: entry)
            await usage.endDeletion(meetingID: meetingID, token: token)
        } catch {
            await usage.endDeletion(meetingID: meetingID, token: token)
            if let failure = error as? MeetingDeletionError { throw failure }
            throw MeetingDeletionError.filesystemFailure
        }
    }

    private func checkedRoot(create: Bool) throws -> URL? {
        guard recordingsRoot.isFileURL, !recordingsRoot.lastPathComponent.isEmpty,
              recordingsRoot.standardizedFileURL.path != "/" else { throw MeetingDeletionError.unsafePath }
        let given = recordingsRoot.standardizedFileURL
        if let current = try attributes(given) {
            guard current[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingDeletionError.unsafePath
            }
        } else {
            guard create else { return nil }
            let parent = given.deletingLastPathComponent().resolvingSymlinksInPath()
            guard try attributes(parent)?[.type] as? FileAttributeType == .typeDirectory else {
                throw MeetingDeletionError.filesystemFailure
            }
            try FileManager.default.createDirectory(at: given, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
        }
        // Trusted OS ancestors may themselves have canonical aliases (e.g. /var).
        // Every entry below this selected root is separately checked for links.
        let root = given.resolvingSymlinksInPath()
        try checkedTree(root, within: root)
        return root
    }

    private func createPrivateDirectory(_ url: URL, root: URL) throws {
        if try attributes(url) == nil {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
        }
        try checkedTree(url, within: root)
        guard try attributes(url)?[.type] as? FileAttributeType == .typeDirectory else {
            throw MeetingDeletionError.unsafePath
        }
        try PersistentFilePolicy.protectDirectory(url)
    }

    private func validateRequest(_ marker: URL, meetingID: UUID, root: URL) throws {
        try checkedTree(marker.deletingLastPathComponent(), within: root)
        guard let info = try attributes(marker), info[.type] as? FileAttributeType == .typeRegular,
              let size = info[.size] as? NSNumber, size.int64Value <= 4_096 else {
            throw MeetingDeletionError.invalidOwnership
        }
        let request: Request
        do { request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: marker)) }
        catch { throw MeetingDeletionError.invalidOwnership }
        guard request.schemaVersion == 1, request.meetingID == meetingID else {
            throw MeetingDeletionError.invalidOwnership
        }
    }

    private func validateAudio(_ directory: URL, meetingID: UUID, root: URL,
                               permitIncomplete: Bool) throws {
        try checkedTree(directory, within: root)
        guard try attributes(directory)?[.type] as? FileAttributeType == .typeDirectory else {
            throw MeetingDeletionError.unsafePath
        }
        let manifestURL = directory.appendingPathComponent("capture-manifest.json")
        guard let info = try attributes(manifestURL) else {
            if permitIncomplete { return }
            if try directoryContents(directory).isEmpty { return }
            throw MeetingDeletionError.invalidOwnership
        }
        guard info[.type] as? FileAttributeType == .typeRegular,
              let size = info[.size] as? NSNumber, size.int64Value <= 4_194_304 else {
            throw MeetingDeletionError.invalidOwnership
        }
        let manifest: AudioCaptureManifest
        do { manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw MeetingDeletionError.invalidOwnership }
        guard manifest.schemaVersion == 1, manifest.sessionID == meetingID else {
            throw MeetingDeletionError.invalidOwnership
        }
    }

    private func checkedTree(_ url: URL, within root: URL) throws {
        let path = url.standardizedFileURL.path
        guard path == root.path || path.hasPrefix(root.path + "/"),
              let info = try attributes(url) else { throw MeetingDeletionError.unsafePath }
        let type = info[.type] as? FileAttributeType
        guard type == .typeDirectory || type == .typeRegular,
              url.standardizedFileURL.resolvingSymlinksInPath().path == path else {
            throw MeetingDeletionError.unsafePath
        }
        if type == .typeDirectory {
            for child in try directoryContents(url) { try checkedTree(child, within: root) }
        }
    }

    private func directoryContents(_ url: URL) throws -> [URL] {
        do { return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
        catch { throw MeetingDeletionError.filesystemFailure }
    }

    private func attributes(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               [CocoaError.Code.fileNoSuchFile.rawValue,
                CocoaError.Code.fileReadNoSuchFile.rawValue].contains(error.code) {
                return nil
            }
            throw MeetingDeletionError.filesystemFailure
        }
    }
}
