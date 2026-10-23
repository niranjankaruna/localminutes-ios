import Foundation
import SQLite3

// TEST-FIRST INTERFACES ONLY. This file deliberately has no persistence behavior.
// Activate under Persistence/ only with its failing hosted XCTest suite.

public enum MeetingRecordingState: String, Codable, Sendable {
    case recording, completed, interrupted, recovered, failed
}

public struct MeetingRecord: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let recordingState: MeetingRecordingState
    public let capturedSampleCount: Int64

    public init(id: UUID, title: String, createdAt: Date,
                recordingState: MeetingRecordingState, capturedSampleCount: Int64 = 0) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.recordingState = recordingState
        self.capturedSampleCount = capturedSampleCount
    }
}

/// Finalized recognizer text only. Sample positions refer to the meeting's global
/// 16 kHz audio timeline; these are utterance ranges, not claimed word timings.
public struct StoredTranscriptSegment: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let meetingID: UUID
    public let sequence: Int
    public let startSample: Int64
    public let endSample: Int64
    public let text: String
    public let modelRevision: String

    public init(id: UUID, meetingID: UUID, sequence: Int, startSample: Int64,
                endSample: Int64, text: String, modelRevision: String) {
        self.id = id
        self.meetingID = meetingID
        self.sequence = sequence
        self.startSample = startSample
        self.endSample = endSample
        self.text = text
        self.modelRevision = modelRevision
    }

}

public enum MeetingStoreError: Error, Equatable, Sendable {
    case invalidInput
    case notFound
    case meetingConflict
    case segmentConflict
    case closed
    case unsupportedSchemaVersion(Int)
    case databaseFailure
}

/// Test-first no-op. Implementation must use a real on-disk SQLite database and
/// serialize access; it must not retain a mirror array as its persistence source.
public actor SQLiteMeetingStore {
    public init(databaseURL: URL) throws {}

    public func createMeeting(_ meeting: MeetingRecord) throws {}
    public func meeting(id: UUID) throws -> MeetingRecord? { nil }
    public func history(limit: Int = 100) throws -> [MeetingRecord] { [] }
    public func renameMeeting(id: UUID, title: String) throws {}
    public func updateRecordingState(id: UUID, state: MeetingRecordingState,
                                     capturedSampleCount: Int64) throws {}
    public func appendFinalizedSegments(_ segments: [StoredTranscriptSegment],
                                        to meetingID: UUID) throws {}
    public func transcript(meetingID: UUID) throws -> [StoredTranscriptSegment] { [] }
    public func searchTranscript(meetingID: UUID, query: String,
                                  limit: Int = 50) throws -> [StoredTranscriptSegment] { [] }
    public func deleteMeeting(id: UUID) throws {}
    public func close() throws {}
}
