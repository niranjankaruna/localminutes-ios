import Foundation
import Darwin

/// Environment is evidence provenance, never a device-validation verdict.
public enum StorageAuditEnvironment: String, Codable, Equatable, Sendable {
    case iOSDevice, iOSSimulator, macOS, other

    public static var current: Self {
#if os(iOS) && targetEnvironment(simulator)
        .iOSSimulator
#elseif os(iOS)
        .iOSDevice
#elseif os(macOS)
        .macOS
#else
        .other
#endif
    }
}

public enum StorageAuditStatus: String, Codable, Equatable, Sendable {
    case notInspected, complete, unreadable, unsafeRootOrItem, limitReached, invalidLimit
}

/// Fixed categories prevent sandbox paths and meeting/model names entering a report.
public enum StorageAuditRole: String, Codable, Equatable, Hashable, Sendable {
    case directory, libraryDatabase, databaseSidecar, audioSegment, captureManifest
    case modelArtifact, modelMetadata, summaryCheckpoint, diagnostics, other
}

public enum StorageAuditProtectionClass: String, Codable, Equatable, Sendable {
    case complete, completeUnlessOpen, completeUntilFirstUserAuthentication, none, unknown
}

public enum StorageAuditBackupExclusion: String, Codable, Equatable, Sendable {
    case excluded, included, unknown
}

public struct StorageAuditGroup: Codable, Equatable, Sendable {
    public let role: StorageAuditRole
    public let protectionClass: StorageAuditProtectionClass
    public let backupExclusion: StorageAuditBackupExclusion
    public let itemCount: Int

    public init(role: StorageAuditRole, protectionClass: StorageAuditProtectionClass,
                backupExclusion: StorageAuditBackupExclusion, itemCount: Int) {
        self.role = role; self.protectionClass = protectionClass
        self.backupExclusion = backupExclusion; self.itemCount = itemCount
    }
}

public struct StorageAuditReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let environment: StorageAuditEnvironment
    public let status: StorageAuditStatus
    public let inspectedItemCount: Int
    public let groups: [StorageAuditGroup]

    public init(environment: StorageAuditEnvironment, status: StorageAuditStatus,
                inspectedItemCount: Int, groups: [StorageAuditGroup]) {
        schemaVersion = 1; self.environment = environment; self.status = status
        self.inspectedItemCount = inspectedItemCount; self.groups = groups
    }
}

public enum StorageAuditInspector {
    public static let maximumItemLimit = 16_384

    /// The caller supplies its vetted, canonical owned persistent root.
    /// The limit covers all observed entries, including the root and directories;
    /// accepted limits are 1...maximumItemLimit.
    public static func inspect(rootURL: URL, itemLimit: Int = 2_048) -> StorageAuditReport {
        var count = 0
        var groups: [StorageAuditGroup] = []
        func report(_ status: StorageAuditStatus) -> StorageAuditReport {
            .init(environment: .current, status: status, inspectedItemCount: count,
                groups: groups.sorted { groupOrder($0) < groupOrder($1) })
        }
        guard (1...maximumItemLimit).contains(itemLimit) else { return report(.invalidLimit) }
        guard rootURL.isFileURL, rootURL.query == nil, rootURL.fragment == nil,
              rootURL.user == nil, rootURL.password == nil, rootURL.port == nil,
              rootURL.host == nil || rootURL.host == "" || rootURL.host == "localhost" else {
            return report(.unsafeRootOrItem)
        }
        let root = rootURL.standardizedFileURL
        guard root.path != "/", root.path.hasPrefix("/"), canonical(root) else {
            return report(.unsafeRootOrItem)
        }
        var cursors: [DirectoryCursor] = []
        do {
            let attributes = try inspectAttributes(root, within: root)
            guard attributes.directory else { return report(.unsafeRootOrItem) }
            let exclusion = effectiveExclusion(attributes.backupExcluded, inherited: .included)
            add(role: .directory, protection: attributes.protection, exclusion: exclusion, to: &groups)
            count = 1
            cursors.append(try DirectoryCursor(url: root, components: [], exclusion: exclusion,
                                               identity: attributes.identity))
            while let cursor = cursors.last {
                // Directory handles are streamed; neither a child-name array nor
                // an unbounded pending-directory queue is ever collected.
                try validateIdentity(cursor.url, expected: cursor.identity, within: root)
                errno = 0
                guard let entry = readdir(cursor.handle) else {
                    guard errno == 0 else { throw AuditFailure.unreadable }
                    cursors.removeLast()
                    continue
                }
                let length = Int(entry.pointee.d_namlen)
                let bytes = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix(length)) }
                guard let name = String(bytes: bytes, encoding: .utf8) else { throw AuditFailure.unsafe }
                if name == "." || name == ".." { continue }
                guard !name.isEmpty, !name.contains("/"), !name.contains("\0") else { throw AuditFailure.unsafe }
                guard count < itemLimit else { return report(.limitReached) }
                let item = cursor.url.appendingPathComponent(name)
                let attributes = try inspectAttributes(item, within: root)
                let components = cursor.components + [name]
                let exclusion = effectiveExclusion(attributes.backupExcluded, inherited: cursor.exclusion)
                let itemRole = attributes.directory ? StorageAuditRole.directory : role(for: components)
                add(role: itemRole, protection: attributes.protection, exclusion: exclusion, to: &groups)
                count += 1
                if attributes.directory {
                    cursors.append(try DirectoryCursor(url: item, components: components,
                        exclusion: exclusion, identity: attributes.identity))
                }
            }
            return report(.complete)
        } catch AuditFailure.unsafe { return report(.unsafeRootOrItem) }
        catch { return report(.unreadable) }
    }

    private enum AuditFailure: Error { case unsafe, unreadable }
    private struct Identity {
        let device: dev_t
        let inode: ino_t
    }
    private struct Attributes {
        let directory: Bool
        let identity: Identity
        let protection: StorageAuditProtectionClass
        let backupExcluded: Bool?
    }
    private final class DirectoryCursor {
        let url: URL
        let components: [String]
        let exclusion: StorageAuditBackupExclusion
        let identity: Identity
        let handle: UnsafeMutablePointer<DIR>

        init(url: URL, components: [String], exclusion: StorageAuditBackupExclusion,
             identity: Identity) throws {
            // Do not follow a leaf link introduced after metadata inspection.
            let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            guard descriptor >= 0 else { throw AuditFailure.unreadable }
            var observed = stat()
            guard fstat(descriptor, &observed) == 0,
                  observed.st_dev == identity.device, observed.st_ino == identity.inode else {
                Darwin.close(descriptor)
                throw AuditFailure.unreadable
            }
            guard let stream = fdopendir(descriptor) else {
                Darwin.close(descriptor)
                throw AuditFailure.unreadable
            }
            self.url = url; self.components = components; self.exclusion = exclusion
            self.identity = identity; handle = stream
        }
        deinit { closedir(handle) }
    }

    private static func canonical(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path
    }

    private static func identity(_ url: URL, within root: URL) throws -> (Identity, Bool) {
        let path = url.standardizedFileURL.path
        guard path == root.path || path.hasPrefix(root.path + "/"), canonical(url) else { throw AuditFailure.unsafe }
        var value = stat()
        guard path.withCString({ lstat($0, &value) }) == 0 else { throw AuditFailure.unreadable }
        let type = value.st_mode & mode_t(S_IFMT)
        guard type == mode_t(S_IFDIR) || type == mode_t(S_IFREG) else { throw AuditFailure.unsafe }
        return (Identity(device: value.st_dev, inode: value.st_ino), type == mode_t(S_IFDIR))
    }

    private static func validateIdentity(_ url: URL, expected: Identity, within root: URL) throws {
        let (actual, _) = try identity(url, within: root)
        guard actual.device == expected.device, actual.inode == expected.inode else { throw AuditFailure.unreadable }
    }

    private static func inspectAttributes(_ item: URL, within root: URL) throws -> Attributes {
        let (observed, directory) = try identity(item, within: root)
        let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
        let protectionValue = attributes[FileAttributeKey(rawValue: "NSFileProtectionKey")]
        let raw: String?
#if os(iOS)
        raw = (protectionValue as? FileProtectionType)?.rawValue ?? (protectionValue as? String)
#else
        raw = protectionValue as? String
#endif
        let protection: StorageAuditProtectionClass
        switch raw {
        case "NSFileProtectionComplete": protection = .complete
        case "NSFileProtectionCompleteUnlessOpen": protection = .completeUnlessOpen
        case "NSFileProtectionCompleteUntilFirstUserAuthentication": protection = .completeUntilFirstUserAuthentication
        case "NSFileProtectionNone": protection = .none
        default: protection = .unknown
        }
        let excluded = try URL(fileURLWithPath: item.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        try validateIdentity(item, expected: observed, within: root)
        return Attributes(directory: directory, identity: observed, protection: protection, backupExcluded: excluded)
    }

    private static func effectiveExclusion(_ own: Bool?, inherited: StorageAuditBackupExclusion) -> StorageAuditBackupExclusion {
        if own == true || inherited == .excluded { return .excluded }
        if own == nil || inherited == .unknown { return .unknown }
        return .included
    }

    private static func add(role: StorageAuditRole, protection: StorageAuditProtectionClass,
                            exclusion: StorageAuditBackupExclusion, to groups: inout [StorageAuditGroup]) {
        if let index = groups.firstIndex(where: {
            $0.role == role && $0.protectionClass == protection && $0.backupExclusion == exclusion
        }) {
            groups[index] = .init(role: role, protectionClass: protection, backupExclusion: exclusion,
                itemCount: groups[index].itemCount + 1)
        } else {
            groups.append(.init(role: role, protectionClass: protection, backupExclusion: exclusion, itemCount: 1))
        }
    }

    private static func groupOrder(_ group: StorageAuditGroup) -> String {
        group.role.rawValue + "|" + group.protectionClass.rawValue + "|" + group.backupExclusion.rawValue
    }

    private static func role(for path: [String]) -> StorageAuditRole {
        var libraryPath = path
        if path.count >= 3, path[0] == "LibraryGenerations", UUID(uuidString: path[1]) != nil {
            libraryPath = Array(path.dropFirst(2))
        }
        if libraryPath == ["meetings.sqlite"] { return .libraryDatabase }
        if libraryPath.count == 1, ["meetings.sqlite-wal", "meetings.sqlite-shm", "meetings.sqlite-journal"].contains(libraryPath[0]) {
            return .databaseSidecar
        }
        if libraryPath.count == 3, libraryPath[0] == "Meetings", UUID(uuidString: libraryPath[1]) != nil {
            let name = libraryPath[2]
            if name == "capture-manifest.json" { return .captureManifest }
            if name.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil { return .audioSegment }
        }
        if libraryPath.count == 2, libraryPath[0] == "SummaryCheckpoints",
           libraryPath[1].hasSuffix(".json"), UUID(uuidString: String(libraryPath[1].dropLast(5))) != nil {
            return .summaryCheckpoint
        }
        if path.count == 2, path[0] == "ModelSelections", ["speechRecognition.json", "summary.json"].contains(path[1]) {
            return .modelMetadata
        }
        if path.count == 3, path[0] == "Models", path[2] == "current.json" { return .modelMetadata }
        if path.count >= 5, path[0] == "Models",
           path[2].range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil,
           UUID(uuidString: path[3]) != nil {
            return path.count == 5 && path[4] == "manifest.json" ? .modelMetadata : .modelArtifact
        }
        if path.count == 2, path[0] == "Diagnostics", ["endurance-metrics.json", "transcription-metrics.json"].contains(path[1]) {
            return .diagnostics
        }
        return .other
    }
}
