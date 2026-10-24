import Foundation

public enum MeetingArchiveError: Error, Equatable, Sendable {
    case notImplemented, invalidLocation, destinationExists, unsafeItem, unexpectedFile
    case snapshotNotClosed, unsupportedVersion, invalidManifest, integrityMismatch, limitExceeded
    case ioFailure
}

public struct MeetingArchiveLimits: Sendable {
    public let maximumFiles: Int
    public let maximumTotalBytes: Int64
    public let maximumFileBytes: Int64
    public let maximumManifestBytes: Int
    public init(maximumFiles: Int = 16_384, maximumTotalBytes: Int64 = 8_589_934_592,
                maximumFileBytes: Int64 = 536_870_912, maximumManifestBytes: Int = 1_048_576) {
        self.maximumFiles = maximumFiles; self.maximumTotalBytes = maximumTotalBytes
        self.maximumFileBytes = maximumFileBytes; self.maximumManifestBytes = maximumManifestBytes
    }
}

public struct MeetingArchiveFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public init(relativePath: String, byteCount: Int64, sha256: String) {
        self.relativePath = relativePath; self.byteCount = byteCount; self.sha256 = sha256
    }
}

public struct MeetingArchiveManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let databaseUserVersion: Int
    public let totalByteCount: Int64
    public let files: [MeetingArchiveFile]
    public init(schemaVersion: Int = 1, databaseUserVersion: Int,
                totalByteCount: Int64, files: [MeetingArchiveFile]) {
        self.schemaVersion = schemaVersion; self.databaseUserVersion = databaseUserVersion
        self.totalByteCount = totalByteCount; self.files = files
    }
}

/// Versioned *directory package*, not ZIP extraction. Layout is manifest.json
/// plus payload/meetings.sqlite and payload/Meetings/<UUID>/{CAF,JSON}.
///
/// Input must be an immutable closed snapshot made under app-wide recording,
/// playback/deletion/model admission. The persistence layer must prepare it via
/// a real SQLite snapshot/checkpoint; this primitive must never copy a live DB.
/// WAL/SHM/journal sidecars are rejected, never silently omitted. Only database
/// and meeting files belong here: no credentials, weights or diagnostics.
/// The archive intentionally contains private notes/audio; this is an explicit
/// user export, not a redacted diagnostic or an automatic cloud backup.
///
/// Export/restore validate all relative paths, regular-file ownership, exact
/// byte counts and SHA-256s with bounded buffers before atomic publication.
/// Destination must not exist. Restore never merges into or overwrites an
/// existing application root. App swap/reopen/schema migration and Files UI
/// remain separate integration contracts. No symlinks/hardlinks are followed.
public enum MeetingArchive {
    // TEST-FIRST stubs only. No archive/copy/restore behavior before hosted RED.
    public static func export(snapshotRoot: URL, to archiveURL: URL,
                              limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        throw MeetingArchiveError.notImplemented
    }

    public static func inspect(_ archiveURL: URL,
                               limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        throw MeetingArchiveError.notImplemented
    }

    public static func restore(from archiveURL: URL, to destinationRoot: URL,
                               limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        throw MeetingArchiveError.notImplemented
    }
}
