import Foundation

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

    /// Test-first seam. The caller supplies its owned persistent root. Production
    /// enumeration and OS metadata reads await meaningful hosted assertion RED.
    /// The limit covers all observed entries, including the root and directories;
    /// accepted limits are 1...maximumItemLimit.
    public static func inspect(rootURL: URL, itemLimit: Int = 2_048) -> StorageAuditReport {
        .init(environment: .current, status: .notInspected, inspectedItemCount: 0, groups: [])
    }
}
