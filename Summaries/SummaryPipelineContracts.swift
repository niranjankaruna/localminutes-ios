import Foundation
#if canImport(LocalMinutesPersistence)
import LocalMinutesPersistence
#endif

/// Disk-backed implementations persist transport bytes only. Every recovered
/// map must still pass the pipeline's source, chunk and grounding validation.
public protocol SummaryCheckpointing: Sendable {
    func save(_ map: SummaryMapCheckpoint, matching identity: SummaryCheckpointIdentity) async throws
    func load(matching identity: SummaryCheckpointIdentity) async throws -> StoredSummaryCheckpoint?
}

extension SummaryCheckpointStore: SummaryCheckpointing {}

public struct SummaryPipelineResumeConfiguration: Sendable {
    public let jobID: UUID
    public let modelID: String
    public let modelSHA256: String
    public let runtimeVersion: String
    public let checkpoints: any SummaryCheckpointing

    public init(jobID: UUID, modelID: String, modelSHA256: String,
                runtimeVersion: String, checkpoints: any SummaryCheckpointing) {
        self.jobID = jobID; self.modelID = modelID; self.modelSHA256 = modelSHA256
        self.runtimeVersion = runtimeVersion; self.checkpoints = checkpoints
    }
}

public typealias SummaryMapJSONGenerator = @Sendable (String, StructuredJSONSchema, Int) async throws -> String

public enum SummaryPipelinePhase: Equatable, Sendable { case idle, running, completed, failed, cancelled }

public typealias SummaryTokenCounter = @Sendable (String) async throws -> Int

public struct SummaryEvidenceSegment: Codable, Equatable, Sendable {
    public let id: String
    public let startSample: Int64
    public let endSample: Int64
    public let text: String
    public init(id: String, startSample: Int64, endSample: Int64, text: String) {
        self.id = id; self.startSample = startSample; self.endSample = endSample; self.text = text
    }
}

