import Foundation
import SQLite3

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

/// One actor owns its on-disk connection. No SQLite pointer or SQL is exposed to
/// views, capture callbacks, recognizers or other actors. Mutations do not suspend.
public actor SQLiteMeetingStore {
    private let connection: MeetingSQLiteConnection

    public init(databaseURL: URL) throws {
        connection = try MeetingSQLiteConnection(databaseURL: databaseURL)
    }

    public func createMeeting(_ meeting: MeetingRecord) throws {
        let database = try connection.database()
        guard !meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              meeting.createdAt.timeIntervalSince1970.isFinite,
              meeting.capturedSampleCount >= 0 else { throw MeetingStoreError.invalidInput }
        guard try readMeeting(id: meeting.id, database: database) == nil else {
            throw MeetingStoreError.meetingConflict
        }
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "INSERT INTO meetings(id,title,created_at,recording_state,captured_sample_count) VALUES(?,?,?,?,?)")
        try statement.bind(meeting.id.uuidString, at: 1)
        try statement.bind(meeting.title, at: 2)
        try statement.bind(meeting.createdAt.timeIntervalSince1970, at: 3)
        try statement.bind(meeting.recordingState.rawValue, at: 4)
        try statement.bind(meeting.capturedSampleCount, at: 5)
        try statement.finish()
    }

    public func meeting(id: UUID) throws -> MeetingRecord? {
        try readMeeting(id: id, database: connection.database())
    }

    public func history(limit: Int = 100) throws -> [MeetingRecord] {
        let database = try connection.database()
        guard limit > 0 else { throw MeetingStoreError.invalidInput }
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings ORDER BY created_at DESC,id ASC LIMIT ?")
        try statement.bind(Int64(limit), at: 1)
        var records: [MeetingRecord] = []
        while try statement.next() { records.append(try decodeMeeting(statement)) }
        return records
    }

    public func renameMeeting(id: UUID, title: String) throws {
        let database = try connection.database()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingStoreError.invalidInput
        }
        let statement = try MeetingSQLiteStatement(database: database,
            sql: "UPDATE meetings SET title=? WHERE id=?")
        try statement.bind(title, at: 1)
        try statement.bind(id.uuidString, at: 2)
        try statement.finish()
        guard sqlite3_changes(database) > 0 else { throw MeetingStoreError.notFound }
    }

    public func updateRecordingState(id: UUID, state: MeetingRecordingState,
                                     capturedSampleCount: Int64) throws {
        let database = try connection.database()
        guard capturedSampleCount >= 0 else { throw MeetingStoreError.invalidInput }
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "UPDATE meetings SET recording_state=?,captured_sample_count=? WHERE id=?")
        try statement.bind(state.rawValue, at: 1)
        try statement.bind(capturedSampleCount, at: 2)
        try statement.bind(id.uuidString, at: 3)
        try statement.finish()
        guard sqlite3_changes(database) > 0 else { throw MeetingStoreError.notFound }
    }

    public func appendFinalizedSegments(_ segments: [StoredTranscriptSegment],
                                        to meetingID: UUID) throws {
        let database = try connection.database()
        for segment in segments {
            guard segment.meetingID == meetingID, segment.sequence >= 0,
                  segment.startSample >= 0, segment.endSample >= segment.startSample,
                  !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !segment.modelRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MeetingStoreError.invalidInput
            }
        }
        guard !segments.isEmpty else { return }
        try connection.transaction {
            guard try readMeeting(id: meetingID, database: database) != nil else {
                throw MeetingStoreError.notFound
            }
            for segment in segments {
                if let previous = try readSegment(id: segment.id, database: database) {
                    guard previous == segment else { throw MeetingStoreError.segmentConflict }
                    continue
                }
                let duplicate = try MeetingSQLiteStatement(database: database,
                    sql: "SELECT id FROM transcript_segments WHERE meeting_id=? AND sequence=?")
                try duplicate.bind(meetingID.uuidString, at: 1)
                try duplicate.bind(Int64(segment.sequence), at: 2)
                let sequenceExists = try duplicate.next()
                guard !sequenceExists else { throw MeetingStoreError.segmentConflict }
                let insert = try MeetingSQLiteStatement(database: database, sql:
                    "INSERT INTO transcript_segments(id,meeting_id,sequence,start_sample,end_sample,text,model_revision) VALUES(?,?,?,?,?,?,?)")
                try insert.bind(segment.id.uuidString, at: 1)
                try insert.bind(meetingID.uuidString, at: 2)
                try insert.bind(Int64(segment.sequence), at: 3)
                try insert.bind(segment.startSample, at: 4)
                try insert.bind(segment.endSample, at: 5)
                try insert.bind(segment.text, at: 6)
                try insert.bind(segment.modelRevision, at: 7)
                try insert.finish()
            }
        }
    }

    public func transcript(meetingID: UUID) throws -> [StoredTranscriptSegment] {
        let statement = try MeetingSQLiteStatement(database: connection.database(), sql:
            "SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments WHERE meeting_id=? ORDER BY sequence ASC")
        try statement.bind(meetingID.uuidString, at: 1)
        return try decodeSegments(statement)
    }

    public func searchTranscript(meetingID: UUID, query: String,
                                  limit: Int = 50) throws -> [StoredTranscriptSegment] {
        let database = try connection.database()
        guard limit > 0 else { throw MeetingStoreError.invalidInput }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        // instr treats percent, underscore, quotes and SQL-looking text literally.
        // This initial substring search is not the later FTS retrieval index.
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments WHERE meeting_id=? AND instr(lower(text),lower(?))>0 ORDER BY sequence ASC LIMIT ?")
        try statement.bind(meetingID.uuidString, at: 1)
        try statement.bind(query, at: 2)
        try statement.bind(Int64(limit), at: 3)
        return try decodeSegments(statement)
    }

    public func deleteMeeting(id: UUID) throws {
        let database = try connection.database()
        try connection.transaction {
            let statement = try MeetingSQLiteStatement(database: database,
                sql: "DELETE FROM meetings WHERE id=?")
            try statement.bind(id.uuidString, at: 1)
            try statement.finish()
            // The enabled FK cascade owns only this meeting's transcript rows.
            // No audio paths or arbitrary filesystem deletion occur here.
        }
    }

    public func close() throws { try connection.close() }

    /// A returned save has committed. Persisted revisions prevent a delayed
    /// autosave task from replacing newer manual work after navigation/relaunch.
    public func saveManualNote(_ note: StoredManualNote) throws {
        let database = try connection.database()
        guard note.editRevision >= 0, note.modifiedAt.timeIntervalSince1970.isFinite else {
            throw MeetingStoreError.invalidInput
        }
        try connection.transaction {
            guard try readMeeting(id: note.meetingID, database: database) != nil else {
                throw MeetingStoreError.notFound
            }
            if let current = try manualNote(meetingID: note.meetingID) {
                guard note.editRevision >= current.editRevision else {
                    throw ManualNoteStoreError.staleRevision
                }
                if note.editRevision == current.editRevision {
                    guard note == current else { throw ManualNoteStoreError.revisionConflict }
                    return
                }
            }
            let statement = try MeetingSQLiteStatement(database: database, sql:
                "INSERT INTO manual_notes(meeting_id,text,edit_revision,modified_at) VALUES(?,?,?,?) ON CONFLICT(meeting_id) DO UPDATE SET text=excluded.text,edit_revision=excluded.edit_revision,modified_at=excluded.modified_at")
            try statement.bind(note.meetingID.uuidString, at: 1)
            try statement.bind(note.text, at: 2)
            try statement.bind(note.editRevision, at: 3)
            try statement.bind(note.modifiedAt.timeIntervalSince1970, at: 4)
            try statement.finish()
        }
    }

    public func manualNote(meetingID: UUID) throws -> StoredManualNote? {
        let statement = try MeetingSQLiteStatement(database: connection.database(),
            sql: "SELECT text,edit_revision,modified_at FROM manual_notes WHERE meeting_id=?")
        try statement.bind(meetingID.uuidString, at: 1)
        guard try statement.next() else { return nil }
        let revision = try statement.integer(at: 1)
        let timestamp = try statement.real(at: 2)
        guard revision >= 0, timestamp.isFinite else { throw MeetingStoreError.databaseFailure }
        return StoredManualNote(meetingID: meetingID, text: try statement.text(at: 0),
            editRevision: revision, modifiedAt: Date(timeIntervalSince1970: timestamp))
    }

    private func readMeeting(id: UUID, database: OpaquePointer) throws -> MeetingRecord? {
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings WHERE id=?")
        try statement.bind(id.uuidString, at: 1)
        guard try statement.next() else { return nil }
        return try decodeMeeting(statement)
    }

    private func decodeMeeting(_ statement: MeetingSQLiteStatement) throws -> MeetingRecord {
        guard let id = UUID(uuidString: try statement.text(at: 0)),
              let state = MeetingRecordingState(rawValue: try statement.text(at: 3)) else {
            throw MeetingStoreError.databaseFailure
        }
        let timestamp = try statement.real(at: 2)
        let captured = try statement.integer(at: 4)
        guard timestamp.isFinite, captured >= 0 else { throw MeetingStoreError.databaseFailure }
        return MeetingRecord(id: id, title: try statement.text(at: 1),
            createdAt: Date(timeIntervalSince1970: timestamp), recordingState: state,
            capturedSampleCount: captured)
    }

    private func readSegment(id: UUID, database: OpaquePointer) throws -> StoredTranscriptSegment? {
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments WHERE id=?")
        try statement.bind(id.uuidString, at: 1)
        guard try statement.next() else { return nil }
        return try decodeSegment(statement)
    }

    private func decodeSegments(_ statement: MeetingSQLiteStatement) throws -> [StoredTranscriptSegment] {
        var values: [StoredTranscriptSegment] = []
        while try statement.next() { values.append(try decodeSegment(statement)) }
        return values
    }

    private func decodeSegment(_ statement: MeetingSQLiteStatement) throws -> StoredTranscriptSegment {
        guard let id = UUID(uuidString: try statement.text(at: 0)),
              let meetingID = UUID(uuidString: try statement.text(at: 1)),
              let sequence = Int(exactly: try statement.integer(at: 2)) else {
            throw MeetingStoreError.databaseFailure
        }
        let start = try statement.integer(at: 3)
        let end = try statement.integer(at: 4)
        guard sequence >= 0, start >= 0, end >= start else { throw MeetingStoreError.databaseFailure }
        return StoredTranscriptSegment(id: id, meetingID: meetingID, sequence: sequence,
            startSample: start, endSample: end, text: try statement.text(at: 5),
            modelRevision: try statement.text(at: 6))
    }
}
