import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

/// Exact resume identity supplied by the planner and its leased real model.
/// Digests cover original source/notes and the complete ordered chunk plan.
public struct SummaryCheckpointIdentity: Codable, Equatable, Sendable {
    public let jobID: UUID
    public let meetingID: UUID
    public let sourceSHA256: String
    public let planSHA256: String
    public let modelID: String
    public let modelRevision: String
    public let modelSHA256: String
    public let runtimeVersion: String
    public let promptVersion: String
    public let contextTokenLimit: Int
    public let reservedOutputTokens: Int
    public let totalChunks: Int

    public init(jobID: UUID, meetingID: UUID, sourceSHA256: String, planSHA256: String,
                modelID: String, modelRevision: String, modelSHA256: String,
                runtimeVersion: String, promptVersion: String, contextTokenLimit: Int,
                reservedOutputTokens: Int, totalChunks: Int) {
        self.jobID = jobID; self.meetingID = meetingID
        self.sourceSHA256 = sourceSHA256; self.planSHA256 = planSHA256
        self.modelID = modelID; self.modelRevision = modelRevision; self.modelSHA256 = modelSHA256
        self.runtimeVersion = runtimeVersion; self.promptVersion = promptVersion
        self.contextTokenLimit = contextTokenLimit; self.reservedOutputTokens = reservedOutputTokens
        self.totalChunks = totalChunks
    }
}

/// Persisted JSON is untrusted on reopen. The resume adapter must run the
/// pipeline's evidence and semantic validation against this exact chunk before reuse.
public struct SummaryMapCheckpoint: Codable, Equatable, Sendable {
    public let index: Int
    public let chunkSHA256: String
    public let mapJSON: Data

    public init(index: Int, chunkSHA256: String, mapJSON: Data) {
        self.index = index; self.chunkSHA256 = chunkSHA256; self.mapJSON = mapJSON
    }
}

public struct StoredSummaryCheckpoint: Codable, Equatable, Sendable {
    public let identity: SummaryCheckpointIdentity
    public let maps: [SummaryMapCheckpoint]
    public var nextMapIndex: Int { maps.count }

    public init(identity: SummaryCheckpointIdentity, maps: [SummaryMapCheckpoint]) {
        self.identity = identity; self.maps = maps
    }
}

public enum SummaryCheckpointError: Error, Equatable, Sendable {
    case invalidInput, identityMismatch, nonContiguousMap, conflictingMap
    case limitExceeded, corruptCheckpoint
}

/// One app-owned actor serializes a directory dedicated to summary checkpoints.
/// A protected replacement is synced before atomic publication. Reopening is
/// recovery of progress only: the pipeline must revalidate every saved map.
public actor SummaryCheckpointStore {
    private struct Envelope: Codable {
        let schemaVersion: Int
        let checkpoint: StoredSummaryCheckpoint
    }

    public static let maximumMaps = 1_024
    private static let maximumMapBytes = 1_048_576
    // Codable represents map Data as base64. Keep an independent total bound;
    // a job cannot fill every possible map with the maximum individual payload.
    private static let maximumEnvelopeBytes = 96 * 1_048_576
    private let directoryURL: URL
    private let canonicalDirectoryPath: String

    public init(directoryURL: URL) throws {
        guard directoryURL.isFileURL,
              directoryURL.host == nil || directoryURL.host == "" || directoryURL.host == "localhost" else {
            throw PersistentFilePolicyError.invalidRoot
        }
        let directory = directoryURL.standardizedFileURL
        guard directory.path != "/", directory.path.hasPrefix("/") else {
            throw PersistentFilePolicyError.invalidRoot
        }
        let parent = directory.deletingLastPathComponent()
        try PersistentFilePolicy.validateItem(parent, within: parent)
        if try !Self.exists(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try PersistentFilePolicy.validateItem(directory, within: parent)
        // This root belongs exclusively to checkpoints. Preflight the complete
        // existing tree before changing any protection/backup/POSIX metadata.
        try PersistentFilePolicy.protectDirectory(directory)
        self.directoryURL = directory
        canonicalDirectoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public func save(_ map: SummaryMapCheckpoint, matching identity: SummaryCheckpointIdentity) throws {
        try Task.checkCancellation()
        try Self.validate(identity)
        try validateDirectory()
        let current = try read(jobID: identity.jobID)
        if let current, current.identity != identity { throw SummaryCheckpointError.identityMismatch }
        try Self.validate(map, for: identity)
        var maps = current?.maps ?? []
        if map.index < maps.count {
            guard maps[map.index] == map else { throw SummaryCheckpointError.conflictingMap }
            // Identical replay is a read-only success, including after reopen.
            return
        }
        guard map.index == maps.count else { throw SummaryCheckpointError.nonContiguousMap }
        maps.append(map)
        let checkpoint = StoredSummaryCheckpoint(identity: identity, maps: maps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(schemaVersion: 1, checkpoint: checkpoint))
        guard data.count <= Self.maximumEnvelopeBytes else { throw SummaryCheckpointError.limitExceeded }
        // No suspension occurs between this admission and publication. A late
        // cancellation may leave this complete valid map available for resume;
        // it can never publish an unfinished generated meeting document.
        try Task.checkCancellation()
        try PersistentFilePolicy.writeAtomically(data, to: file(for: identity.jobID), within: directoryURL)
    }

    public func load(matching identity: SummaryCheckpointIdentity) throws -> StoredSummaryCheckpoint? {
        try Task.checkCancellation()
        try Self.validate(identity)
        try validateDirectory()
        guard let checkpoint = try read(jobID: identity.jobID) else { return nil }
        guard checkpoint.identity == identity else { throw SummaryCheckpointError.identityMismatch }
        return checkpoint
    }

    /// Presentation metadata only. Resuming still requires the pipeline's full
    /// identity and evidence validation before any saved map can be reused.
    public func savedMapCount(jobID: UUID, meetingID: UUID) throws -> Int {
        try Task.checkCancellation()
        try validateDirectory()
        guard let checkpoint = try read(jobID: jobID) else { return 0 }
        guard checkpoint.identity.meetingID == meetingID else { throw SummaryCheckpointError.identityMismatch }
        return checkpoint.maps.count
    }

    public func remove(jobID: UUID, meetingID: UUID) throws {
        try Task.checkCancellation()
        try validateDirectory()
        guard let checkpoint = try read(jobID: jobID) else { return }
        guard checkpoint.identity.meetingID == meetingID else { throw SummaryCheckpointError.identityMismatch }
        let url = file(for: jobID)
        try PersistentFilePolicy.validateItem(url, within: directoryURL)
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: url)
    }

    private func file(for jobID: UUID) -> URL {
        directoryURL.appendingPathComponent(jobID.uuidString + ".json", isDirectory: false)
    }

    private func validateDirectory() throws {
        try PersistentFilePolicy.validateItem(directoryURL, within: directoryURL.deletingLastPathComponent())
        let values = try URL(fileURLWithPath: directoryURL.path).resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true,
              directoryURL.resolvingSymlinksInPath().standardizedFileURL.path == canonicalDirectoryPath else {
            throw PersistentFilePolicyError.unsafePath
        }
    }

    private func read(jobID: UUID) throws -> StoredSummaryCheckpoint? {
        let url = file(for: jobID)
        guard try Self.exists(url) else { return nil }
        try PersistentFilePolicy.validateItem(url, within: directoryURL)
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize,
              count > 0, count <= Self.maximumEnvelopeBytes else {
            throw SummaryCheckpointError.corruptCheckpoint
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        data.reserveCapacity(count)
        while data.count <= Self.maximumEnvelopeBytes {
            try Task.checkCancellation()
            let remaining = Self.maximumEnvelopeBytes + 1 - data.count
            guard let bytes = try handle.read(upToCount: min(65_536, remaining)), !bytes.isEmpty else { break }
            data.append(bytes)
        }
        guard !data.isEmpty, data.count <= Self.maximumEnvelopeBytes else {
            throw SummaryCheckpointError.corruptCheckpoint
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw SummaryCheckpointError.corruptCheckpoint }
        let checkpoint = envelope.checkpoint
        guard envelope.schemaVersion == 1, checkpoint.identity.jobID == jobID,
              !checkpoint.maps.isEmpty, checkpoint.maps.count <= Self.maximumMaps,
              checkpoint.maps.count <= checkpoint.identity.totalChunks else {
            throw SummaryCheckpointError.corruptCheckpoint
        }
        do {
            try Self.validate(checkpoint.identity)
            for (index, map) in checkpoint.maps.enumerated() {
                guard map.index == index else { throw SummaryCheckpointError.corruptCheckpoint }
                try Self.validate(map, for: checkpoint.identity)
            }
        } catch { throw SummaryCheckpointError.corruptCheckpoint }
        return checkpoint
    }

    private static func validate(_ identity: SummaryCheckpointIdentity) throws {
        guard hex(identity.sourceSHA256, count: 64), hex(identity.planSHA256, count: 64),
              hex(identity.modelRevision, count: 40), hex(identity.modelSHA256, count: 64),
              metadata(identity.modelID, maximumBytes: 256),
              metadata(identity.runtimeVersion, maximumBytes: 128),
              metadata(identity.promptVersion, maximumBytes: 128),
              (64...SummaryContextWindow.maximumSupportedTokens).contains(identity.contextTokenLimit),
              (1...SummaryContextWindow.maximumSupportedOutputTokens).contains(identity.reservedOutputTokens),
              identity.reservedOutputTokens < identity.contextTokenLimit,
              (1...maximumMaps).contains(identity.totalChunks) else {
            throw SummaryCheckpointError.invalidInput
        }
    }

    private static func validate(_ map: SummaryMapCheckpoint, for identity: SummaryCheckpointIdentity) throws {
        guard map.mapJSON.count <= maximumMapBytes else { throw SummaryCheckpointError.limitExceeded }
        guard (0..<identity.totalChunks).contains(map.index), hex(map.chunkSHA256, count: 64),
              !map.mapJSON.isEmpty else { throw SummaryCheckpointError.invalidInput }
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: map.mapJSON) as? [String: Any] else {
                throw SummaryCheckpointError.invalidInput
            }
            object = decoded
        } catch { throw SummaryCheckpointError.invalidInput }
        guard let meeting = object["meeting_id"] as? String, UUID(uuidString: meeting) == identity.meetingID else {
            throw SummaryCheckpointError.invalidInput
        }
        // Prompt revisions change wording, not the stored index format. The
        // payload declares its own schema; exact prompt identity is still
        // checked by save/load before any checkpoint can be reused.
        let narrativePrefix = "narrative-v"
        let narrativeRevision = identity.promptVersion.hasPrefix(narrativePrefix)
            ? Int(identity.promptVersion.dropFirst(narrativePrefix.count)) : nil
        if let narrativeRevision, narrativeRevision > 0 {
            // The pipeline validates topic contents and references on resume.
            guard object["schema_version"] as? Int == 2, object["topics"] is [Any] else {
                throw SummaryCheckpointError.invalidInput
            }
        } else {
            // Legacy progress remains readable and removable. Exact identity
            // comparison prevents its reuse by the narrative pipeline.
            guard object["schema_version"] == nil || object["schema_version"] as? Int == 1,
                  object["summary_points"] is [Any], object["decisions"] is [Any], object["actions"] is [Any] else {
                throw SummaryCheckpointError.invalidInput
            }
        }
    }

    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func metadata(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func exists(_ url: URL) throws -> Bool {
        do {
            // File attributes recognize a dangling symlink too; it must fail
            // ownership validation instead of becoming an absent checkpoint.
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }
}
