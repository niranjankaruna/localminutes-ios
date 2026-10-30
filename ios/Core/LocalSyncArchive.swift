import Foundation
import CryptoKit

public struct LocalSyncFile: Codable, Equatable, Sendable {
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
}

public struct LocalSyncManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let transferId: String
    public let sourceId: String
    public let files: [LocalSyncFile]
}

public enum LocalSyncError: Error, Sendable {
    case invalidData, unsupportedVersion, integrityMismatch, identityCollision, busy, disconnected, unpaired, insufficientSpace
}

/// Platform-neutral exchange: bounded JSON-lines metadata and explicitly allowed original meeting files.
public enum LocalSyncArchive {
    public static let maximumFrameBytes = 16 * 1_024 * 1_024
    public static let maximumRecordBytes = 8 * 1_024 * 1_024

    public static func canonicalID(_ value: String) throws -> String {
        guard let id = UUID(uuidString: value), id.uuidString == value else { throw LocalSyncError.invalidData }
        return value
    }

    public static func allowed(_ path: String) -> Bool {
        if path == "records.jsonl" { return true }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || (parts.count == 4 && parts[2] == "RecoveryQuarantine"),
              parts[0] == "Meetings", let id = UUID(uuidString: parts[1]), id.uuidString == parts[1] else { return false }
        let name = parts.last!
        return (parts.count == 3 && ["capture-manifest.json", "recovery-report.json", "transcription-replay.json"].contains(name))
            || name.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil
    }

    public static func file(_ relative: String, within root: URL) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") }) else {
            throw LocalSyncError.invalidData
        }
        let result = root.appendingPathComponent(relative).standardizedFileURL
        guard result.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw LocalSyncError.invalidData }
        // Validate every existing ancestor; creation must never follow a symlink.
        var ancestor = result
        while ancestor.path.hasPrefix(root.standardizedFileURL.path + "/") {
            if FileManager.default.fileExists(atPath: ancestor.path) || (try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try PersistentFilePolicy.validateItem(ancestor, within: root)
            }
            ancestor.deleteLastPathComponent()
        }
        return result
    }

    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 131_072), !data.isEmpty {
            try Task.checkCancellation(); hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func validateManifest(_ manifest: LocalSyncManifest) throws {
        guard manifest.schemaVersion == 1 else { throw LocalSyncError.unsupportedVersion }
        _ = try canonicalID(manifest.transferId); _ = try canonicalID(manifest.sourceId)
        guard !manifest.files.isEmpty, manifest.files.count <= 100_000 else { throw LocalSyncError.invalidData }
        var names = Set<String>(); var total: Int64 = 0
        for item in manifest.files {
            guard allowed(item.relativePath), names.insert(item.relativePath.lowercased()).inserted, item.byteCount >= 0,
                  !item.relativePath.hasSuffix(".json") || item.byteCount <= Int64(maximumFrameBytes),
                  item.sha256.utf8.count == 64, item.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw LocalSyncError.invalidData }
            let addition = total.addingReportingOverflow(item.byteCount)
            guard !addition.overflow else { throw LocalSyncError.invalidData }; total = addition.partialValue
        }
        guard names.contains("records.jsonl") else { throw LocalSyncError.invalidData }
    }

    public static func validate(_ root: URL) throws -> LocalSyncManifest {
        let manifestURL = try file("manifest.json", within: root)
        guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumFrameBytes else { throw LocalSyncError.invalidData }
        let manifest = try JSONDecoder().decode(LocalSyncManifest.self, from: Data(contentsOf: manifestURL))
        try validateManifest(manifest)
        for entry in manifest.files {
            let url = try file(entry.relativePath, within: root)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value == entry.byteCount,
                  try digest(url) == entry.sha256 else { throw LocalSyncError.integrityMismatch }
        }
        return manifest
    }

    public static func seal(_ root: URL, sourceID: UUID) throws -> LocalSyncManifest {
        var files: [LocalSyncFile] = []
        try enumerateFiles(root) { relative, url, size in
            guard allowed(relative) else { throw LocalSyncError.invalidData }
            files.append(.init(relativePath: relative, byteCount: size, sha256: try digest(url)))
        }
        let manifest = LocalSyncManifest(schemaVersion: 1, transferId: UUID().uuidString, sourceId: sourceID.uuidString,
                                         files: files.sorted { $0.relativePath < $1.relativePath })
        try validateManifest(manifest)
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= maximumFrameBytes else { throw LocalSyncError.invalidData }
        try PersistentFilePolicy.writeAtomically(data, to: root.appendingPathComponent("manifest.json"), within: root)
        return manifest
    }

    public static func records(_ url: URL, body: ([String: Any]) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var pending = Data()
        while let bytes = try handle.read(upToCount: 65_536), !bytes.isEmpty {
            try Task.checkCancellation(); pending.append(bytes)
            while let end = pending.firstIndex(of: 10) {
                let length = pending.distance(from: pending.startIndex, to: end)
                guard length > 0, length <= maximumRecordBytes else { throw LocalSyncError.invalidData }
                guard let row = try JSONSerialization.jsonObject(with: pending.prefix(upTo: end)) as? [String: Any] else { throw LocalSyncError.invalidData }
                try body(row); pending.removeSubrange(...end)
            }
            guard pending.count <= maximumRecordBytes else { throw LocalSyncError.invalidData }
        }
        guard pending.isEmpty else { throw LocalSyncError.invalidData }
    }

    public static func copyMedia(from source: URL, to destination: URL) throws {
        let meetings = source.appendingPathComponent("Meetings", isDirectory: true)
        guard FileManager.default.fileExists(atPath: meetings.path) else { return }
        try enumerateFiles(meetings) { name, item, _ in
            let relative = "Meetings/" + name
            guard allowed(relative) else { return }
            let output = try file(relative, within: destination)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: item, to: output)
            try PersistentFilePolicy.protectItem(output, within: destination)
        }
    }

    private static func enumerateFiles(_ root: URL, body: (String, URL, Int64) throws -> Void) throws {
        var pending = [""]; var count = 0
        while let parent = pending.popLast() {
            let directory = parent.isEmpty ? root : root.appendingPathComponent(parent, isDirectory: true)
            try PersistentFilePolicy.validateItem(directory, within: root)
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try Task.checkCancellation(); count += 1
                guard count <= 200_000 else { throw LocalSyncError.invalidData }
                // Foundation may return canonical /private/var URLs. Derive relative names from traversal,
                // never by subtracting URL strings or relying on a directory URL's trailing slash.
                let relative = parent.isEmpty ? child.lastPathComponent : parent + "/" + child.lastPathComponent
                guard relative.split(separator: "/").count <= 5 else { throw LocalSyncError.invalidData }
                let item = root.appendingPathComponent(relative)
                try PersistentFilePolicy.validateItem(item, within: root)
                let metadata = try FileManager.default.attributesOfItem(atPath: item.path)
                if metadata[.type] as? FileAttributeType == .typeDirectory { pending.append(relative) }
                else {
                    guard metadata[.type] as? FileAttributeType == .typeRegular, let size = (metadata[.size] as? NSNumber)?.int64Value else { throw LocalSyncError.invalidData }
                    try body(relative, item, size)
                }
            }
        }
    }
}
