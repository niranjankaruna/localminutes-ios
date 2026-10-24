import Foundation

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
/// existing grounded decoder against this exact chunk before reusing the map.
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

/// TEST-FIRST boundary only. No working checkpoint persistence is implemented
/// until compatible hosted behavioral RED is recorded. The directory is owned
/// exclusively by the app's summary checkpoints, not the meeting database.
public actor SummaryCheckpointStore {
    public init(directoryURL: URL) throws {}

    public func save(_ map: SummaryMapCheckpoint, matching identity: SummaryCheckpointIdentity) throws {}

    public func load(matching identity: SummaryCheckpointIdentity) throws -> StoredSummaryCheckpoint? { nil }

    public func remove(jobID: UUID, meetingID: UUID) throws {}
}
