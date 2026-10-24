import Foundation
import Synchronization
import CryptoKit
import Darwin

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
    public static func export(snapshotRoot: URL, to archiveURL: URL,
                              limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        try operation {
            try validate(limits)
            let source = try directory(snapshotRoot)
            let target = try destination(archiveURL, outside: source)
            // Preflight the complete source before creating or changing output.
            let scan = try scanPayload(source, limits: limits)
            guard scan.files["meetings.sqlite"] != nil else { throw MeetingArchiveError.invalidManifest }
            return try staged(at: target) { stage in
                let payload = stage.appendingPathComponent("payload", isDirectory: true)
                try makeDirectory(payload, within: stage)
                var entries: [MeetingArchiveFile] = []
                for path in scan.files.keys.sorted() {
                    try Task.checkCancellation()
                    let count = scan.sizes[path]!
                    let hash = try copy(scan.files[path]!, to: payload.appendingPathComponent(path),
                        sourceRoot: source, outputRoot: stage, expectedBytes: count, expectedHash: nil)
                    entries.append(.init(relativePath: path, byteCount: count, sha256: hash))
                }
                let version = try databaseVersion(payload.appendingPathComponent("meetings.sqlite"), within: stage)
                let manifest = MeetingArchiveManifest(databaseUserVersion: version,
                    totalByteCount: scan.total, files: entries)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(manifest)
                guard data.count <= limits.maximumManifestBytes else { throw MeetingArchiveError.limitExceeded }
                try PersistentFilePolicy.writeAtomically(data,
                    to: stage.appendingPathComponent("manifest.json"), within: stage)
                return manifest
            }
        }
    }

    public static func inspect(_ archiveURL: URL,
                               limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        try operation { try inspectValidated(archiveURL, limits: limits) }
    }

    public static func restore(from archiveURL: URL, to destinationRoot: URL,
                               limits: MeetingArchiveLimits = .init()) throws -> MeetingArchiveManifest {
        try operation {
            try validate(limits)
            let source = try directory(archiveURL)
            let target = try destination(destinationRoot, outside: source)
            let manifest = try inspectValidated(source, limits: limits)
            let payload = source.appendingPathComponent("payload", isDirectory: true)
            return try staged(at: target) { stage in
                for entry in manifest.files {
                    try Task.checkCancellation()
                    _ = try copy(payload.appendingPathComponent(entry.relativePath),
                        to: stage.appendingPathComponent(entry.relativePath), sourceRoot: source,
                        outputRoot: stage, expectedBytes: entry.byteCount, expectedHash: entry.sha256)
                }
                guard try databaseVersion(stage.appendingPathComponent("meetings.sqlite"), within: stage)
                    == manifest.databaseUserVersion else { throw MeetingArchiveError.integrityMismatch }
                return manifest
            }
        }
    }

    private struct Scan {
        var files: [String: URL] = [:]
        var sizes: [String: Int64] = [:]
        var total: Int64 = 0
    }

    private static func operation(_ body: () throws -> MeetingArchiveManifest) throws -> MeetingArchiveManifest {
        do { return try body() }
        catch let error as MeetingArchiveError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch is PersistentFilePolicyError { throw MeetingArchiveError.unsafeItem }
        catch { throw MeetingArchiveError.ioFailure }
    }

    private static func validate(_ limits: MeetingArchiveLimits) throws {
        guard (1...16_384).contains(limits.maximumFiles),
              (1...8_589_934_592).contains(limits.maximumTotalBytes),
              (1...536_870_912).contains(limits.maximumFileBytes),
              (1...1_048_576).contains(limits.maximumManifestBytes) else {
            throw MeetingArchiveError.limitExceeded
        }
    }

    private static func fileURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), url.standardizedFileURL.path != "/" else {
            throw MeetingArchiveError.invalidLocation
        }
        return url.standardizedFileURL
    }

    private static func directory(_ url: URL) throws -> URL {
        let value = try fileURL(url)
        let metadata = try FileManager.default.attributesOfItem(atPath: value.path)
        guard metadata[.type] as? FileAttributeType == .typeDirectory else { throw MeetingArchiveError.unsafeItem }
        try PersistentFilePolicy.validateItem(value, within: value)
        return value
    }

    private static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return false }
    }

    private static func destination(_ url: URL, outside source: URL) throws -> URL {
        let output = try fileURL(url)
        let parent = try directory(output.deletingLastPathComponent())
        let resolved = parent.resolvingSymlinksInPath().appendingPathComponent(output.lastPathComponent).standardizedFileURL
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path != source.path, !resolved.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(resolved.path + "/") else { throw MeetingArchiveError.invalidLocation }
        guard try !exists(output) else { throw MeetingArchiveError.destinationExists }
        return output
    }

    private static func allowedDirectory(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return path == "Meetings" || ((parts.count == 2 || (parts.count == 3 && parts[2] == "RecoveryQuarantine"))
            && parts[0] == "Meetings" && UUID(uuidString: String(parts[1])) != nil)
    }

    private static func allowedFile(_ path: String) -> Bool {
        if path == "meetings.sqlite" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard (parts.count == 3 || (parts.count == 4 && parts[2] == "RecoveryQuarantine")),
              parts[0] == "Meetings", UUID(uuidString: String(parts[1])) != nil else { return false }
        let name = String(parts.last!)
        return (parts.count == 3 && ["capture-manifest.json", "recovery-report.json", "transcription-replay.json"].contains(name))
            || name.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil
    }

    private static func scanPayload(_ root: URL, limits: MeetingArchiveLimits) throws -> Scan {
        var result = Scan()
        var directoryCount = 0
        let enumerationFailed = Mutex(false)
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
            options: [], errorHandler: { _, _ in enumerationFailed.withLock { $0 = true }; return false }) else {
            throw MeetingArchiveError.ioFailure
        }
        while let file = entries.nextObject() as? URL {
            try Task.checkCancellation()
                guard !enumerationFailed.withLock({ $0 }) else { throw MeetingArchiveError.ioFailure }
                let path = file.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
                if ["meetings.sqlite-wal", "meetings.sqlite-shm", "meetings.sqlite-journal"].contains(path) {
                    throw MeetingArchiveError.snapshotNotClosed
                }
                try PersistentFilePolicy.validateItem(file, within: root)
                let metadata = try FileManager.default.attributesOfItem(atPath: file.path)
                if metadata[.type] as? FileAttributeType == .typeDirectory {
                    guard allowedDirectory(path) else { throw MeetingArchiveError.unexpectedFile }
                    directoryCount += 1
                    guard directoryCount <= limits.maximumFiles else { throw MeetingArchiveError.limitExceeded }
                } else {
                    guard metadata[.type] as? FileAttributeType == .typeRegular else { throw MeetingArchiveError.unsafeItem }
                    guard allowedFile(path) else { throw MeetingArchiveError.unexpectedFile }
                    guard result.files.count < limits.maximumFiles,
                          let size = (metadata[.size] as? NSNumber)?.int64Value,
                          size >= 0, size <= limits.maximumFileBytes else { throw MeetingArchiveError.limitExceeded }
                    let (sum, overflow) = result.total.addingReportingOverflow(size)
                    guard !overflow, sum <= limits.maximumTotalBytes else { throw MeetingArchiveError.limitExceeded }
                    result.files[path] = file; result.sizes[path] = size; result.total = sum
                }
        }
        guard !enumerationFailed.withLock({ $0 }) else { throw MeetingArchiveError.ioFailure }
        return result
    }

    private static func inspectValidated(_ url: URL, limits: MeetingArchiveLimits) throws -> MeetingArchiveManifest {
        try validate(limits)
        let root = try directory(url)
        var names: Set<String> = []
        let enumerationFailed = Mutex(false)
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, _ in enumerationFailed.withLock { $0 = true }; return false }) else {
            throw MeetingArchiveError.ioFailure
        }
        while let file = entries.nextObject() as? URL {
            guard !enumerationFailed.withLock({ $0 }), names.count < 2 else { throw MeetingArchiveError.unexpectedFile }
            names.insert(file.lastPathComponent)
        }
        guard !enumerationFailed.withLock({ $0 }) else { throw MeetingArchiveError.ioFailure }
        guard Set(names) == ["manifest.json", "payload"] else { throw MeetingArchiveError.unexpectedFile }
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try bounded(manifestURL, within: root, maximum: limits.maximumManifestBytes)
        let manifest: MeetingArchiveManifest
        do { manifest = try JSONDecoder().decode(MeetingArchiveManifest.self, from: data) }
        catch { throw MeetingArchiveError.invalidManifest }
        guard manifest.schemaVersion == 1, (1...5).contains(manifest.databaseUserVersion) else {
            throw MeetingArchiveError.unsupportedVersion
        }
        guard !manifest.files.isEmpty, manifest.files.count <= limits.maximumFiles else { throw MeetingArchiveError.limitExceeded }
        var declared: Set<String> = []; var total: Int64 = 0
        for entry in manifest.files {
            guard allowedFile(entry.relativePath), declared.insert(entry.relativePath).inserted,
                  entry.sha256.utf8.count == 64,
                  entry.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  entry.byteCount >= 0 else { throw MeetingArchiveError.invalidManifest }
            guard entry.byteCount <= limits.maximumFileBytes else { throw MeetingArchiveError.limitExceeded }
            let (sum, overflow) = total.addingReportingOverflow(entry.byteCount)
            guard !overflow, sum <= limits.maximumTotalBytes else { throw MeetingArchiveError.limitExceeded }
            total = sum
        }
        guard declared.contains("meetings.sqlite"), manifest.totalByteCount == total else { throw MeetingArchiveError.invalidManifest }
        let payload = try directory(root.appendingPathComponent("payload", isDirectory: true))
        try PersistentFilePolicy.validateItem(payload, within: root)
        let scan = try scanPayload(payload, limits: limits)
        let actual = Set(scan.files.keys)
        guard actual.subtracting(declared).isEmpty else { throw MeetingArchiveError.unexpectedFile }
        guard actual == declared else { throw MeetingArchiveError.integrityMismatch }
        for entry in manifest.files {
            guard scan.sizes[entry.relativePath] == entry.byteCount else { throw MeetingArchiveError.integrityMismatch }
            let hash = try digest(scan.files[entry.relativePath]!, within: root, expectedBytes: entry.byteCount)
            guard hash == entry.sha256 else { throw MeetingArchiveError.integrityMismatch }
        }
        guard try databaseVersion(payload.appendingPathComponent("meetings.sqlite"), within: root)
            == manifest.databaseUserVersion else { throw MeetingArchiveError.integrityMismatch }
        return manifest
    }

    private static func input(_ url: URL, within root: URL) throws -> FileHandle {
        try PersistentFilePolicy.validateItem(url, within: root)
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw MeetingArchiveError.ioFailure }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_nlink == 1,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            try? handle.close(); throw MeetingArchiveError.unsafeItem
        }
        return handle
    }

    private static func bounded(_ url: URL, within root: URL, maximum: Int) throws -> Data {
        let handle = try input(url, within: root); defer { try? handle.close() }
        var result = Data()
        while let data = try handle.read(upToCount: min(65_536, maximum + 1 - result.count)), !data.isEmpty {
            try Task.checkCancellation(); result.append(data)
            guard result.count <= maximum else { throw MeetingArchiveError.limitExceeded }
        }
        return result
    }

    private static func databaseVersion(_ url: URL, within root: URL) throws -> Int {
        let file = try input(url, within: root); defer { try? file.close() }
        let header = try file.read(upToCount: 64) ?? Data()
        guard header.count == 64, header.starts(with: Data("SQLite format 3\0".utf8)) else {
            throw MeetingArchiveError.integrityMismatch
        }
        let version = header[60..<64].reduce(0) { ($0 << 8) | Int($1) }
        guard (1...5).contains(version) else { throw MeetingArchiveError.unsupportedVersion }
        return version
    }

    private static func digest(_ url: URL, within root: URL, expectedBytes: Int64) throws -> String {
        let file = try input(url, within: root); defer { try? file.close() }
        var hash = SHA256(); var count: Int64 = 0
        while let data = try file.read(upToCount: 65_536), !data.isEmpty {
            try Task.checkCancellation()
            guard Int64(data.count) <= expectedBytes - count else { throw MeetingArchiveError.integrityMismatch }
            count += Int64(data.count); hash.update(data: data)
        }
        guard count == expectedBytes else { throw MeetingArchiveError.integrityMismatch }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func makeDirectory(_ url: URL, within root: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try PersistentFilePolicy.protectItem(url, within: root)
    }

    private static func copy(_ source: URL, to output: URL, sourceRoot: URL, outputRoot: URL,
                             expectedBytes: Int64, expectedHash: String?) throws -> String {
        let incoming = try input(source, within: sourceRoot); defer { try? incoming.close() }
        try makeDirectory(output.deletingLastPathComponent(), within: outputRoot)
        let descriptor = output.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) }
        guard descriptor >= 0 else { throw MeetingArchiveError.ioFailure }
        let outgoing = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true); defer { try? outgoing.close() }
        try PersistentFilePolicy.protectItem(output, within: outputRoot)
        var count: Int64 = 0; var hash = SHA256()
        while let data = try incoming.read(upToCount: 65_536), !data.isEmpty {
            try Task.checkCancellation()
            guard Int64(data.count) <= expectedBytes - count else { throw MeetingArchiveError.integrityMismatch }
            count += Int64(data.count); hash.update(data: data); try outgoing.write(contentsOf: data)
        }
        let value = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == expectedBytes, expectedHash == nil || value == expectedHash else { throw MeetingArchiveError.integrityMismatch }
        try outgoing.synchronize(); try outgoing.close()
        return value
    }

    private static func staged(at output: URL,
        build: (URL) throws -> MeetingArchiveManifest) throws -> MeetingArchiveManifest {
        let parent = output.deletingLastPathComponent()
        let canonicalParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let stage = parent.appendingPathComponent(".localminutes-archive-\(UUID().uuidString)", isDirectory: true)
        guard stage.path.withCString({ Darwin.mkdir($0, mode_t(0o700)) }) == 0 else { throw MeetingArchiveError.ioFailure }
        var published = false
        defer {
            if !published, stage.deletingLastPathComponent() == parent,
               stage.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == canonicalParent {
                try? FileManager.default.removeItem(at: stage)
            }
        }
        try PersistentFilePolicy.protectDirectory(stage)
        let manifest = try build(stage)
        try Task.checkCancellation()
        try PersistentFilePolicy.protectDirectory(stage)
        guard parent.resolvingSymlinksInPath().standardizedFileURL == canonicalParent else { throw MeetingArchiveError.unsafeItem }
        guard try !exists(output) else { throw MeetingArchiveError.destinationExists }
        // Exclusive same-parent rename never merges or overwrites another root.
        let renamed = stage.path.withCString { from in
            output.path.withCString { to in Darwin.renamex_np(from, to, UInt32(RENAME_EXCL)) }
        }
        guard renamed == 0 else {
            if errno == EEXIST { throw MeetingArchiveError.destinationExists }
            throw MeetingArchiveError.ioFailure
        }
        published = true
        return manifest
    }
}
