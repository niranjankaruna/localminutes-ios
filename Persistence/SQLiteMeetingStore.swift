import Foundation
import SQLite3
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

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

    /// Content existence comes from this meeting's persisted rows. Neither audio
    /// duration nor another meeting's generated content establishes availability.
    /// One statement reads a consistent inventory without loading private text.
    public func contentStatus(meetingID: UUID) -> MeetingContentStatus {
        do {
            let statement = try MeetingSQLiteStatement(database: connection.database(), sql: """
                SELECT EXISTS(SELECT 1 FROM transcript_segments WHERE meeting_id=meetings.id),
                       EXISTS(SELECT 1 FROM generated_documents WHERE meeting_id=meetings.id AND kind=?)
                FROM meetings WHERE id=?
                """)
            try statement.bind(GeneratedDocumentKind.summary.rawValue, at: 1)
            try statement.bind(meetingID.uuidString, at: 2)
            guard try statement.next() else { return .unknown }
            return try MeetingContentStatus(
                transcript: statement.integer(at: 0) == 1 ? .available : .absent,
                summary: statement.integer(at: 1) == 1 ? .available : .absent)
        } catch { return .unknown }
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

    /// Exclusive canonical-UUID keyset, independent of changing recording state
    /// and creation-date order. Startup can enumerate every bounded page while
    /// earlier rows are marked recovered without skipping or repeating them.
    public func unfinishedMeetings(afterID: UUID?, limit: Int = 100) throws -> [MeetingRecord] {
        let database = try connection.database()
        guard limit > 0, limit <= 1_000 else { throw MeetingStoreError.invalidInput }
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings WHERE recording_state<>? AND id>? ORDER BY id ASC LIMIT ?")
        try statement.bind(MeetingRecordingState.completed.rawValue, at: 1)
        try statement.bind(afterID?.uuidString ?? "", at: 2)
        try statement.bind(Int64(limit), at: 3)
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

    /// Ranked original evidence only from the selected meeting. User punctuation
    /// and operator spellings have no FTS/SQL authority; literal lexical terms
    /// form an application-owned conjunction. No answer or citation is generated.
    public func retrieveEvidence(meetingID: UUID, query: String,
                                 limit: Int = 8) throws -> [StoredTranscriptSegment] {
        let database = try connection.database()
        guard limit >= 1, limit <= 20 else { throw MeetingStoreError.invalidInput }
        let tokenCharacters = CharacterSet.alphanumerics.union(.nonBaseCharacters)
        let terms = query.components(separatedBy: tokenCharacters.inverted).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let expression = terms.map {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: " AND ")
        let statement = try MeetingSQLiteStatement(database: database, sql: """
            SELECT source.id,source.meeting_id,source.sequence,source.start_sample,
                   source.end_sample,source.text,source.model_revision
            FROM transcript_fts JOIN transcript_segments AS source ON source.rowid=transcript_fts.rowid
            WHERE transcript_fts MATCH ? AND source.meeting_id=?
            ORDER BY bm25(transcript_fts) ASC,source.sequence ASC LIMIT ?
            """)
        try statement.bind(expression, at: 1)
        try statement.bind(meetingID.uuidString, at: 2)
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

    /// A consistent native snapshot includes committed WAL data without
    /// checkpointing the caller-owned source or exposing its connection.
    public func createSnapshot(at destinationURL: URL) throws {
        try Task.checkCancellation()
        let source = try connection.database()
        do { try SQLiteMeetingBackup.create(from: source, to: destinationURL) }
        catch is CancellationError { throw CancellationError() }
        catch let error as SQLiteSnapshotError { throw error }
        catch { throw SQLiteSnapshotError.databaseFailure }
    }

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

    /// Capture provenance is immutable and belongs to exactly one meeting.
    /// Missing legacy provenance stays unknown; corruption never becomes nil.
    public func speechModelPin(meetingID: UUID) throws -> StoredMeetingSpeechModelPin? {
        let statement = try MeetingSQLiteStatement(database: connection.database(), sql:
            "SELECT length(CAST(selection_json AS BLOB)),selection_json FROM meeting_speech_model_pins WHERE meeting_id=?")
        try statement.bind(meetingID.uuidString, at: 1)
        guard try statement.next() else { return nil }
        let bytes = try statement.integer(at: 0)
        guard bytes >= 1, bytes <= 1_048_576 else { throw MeetingSpeechModelPinError.invalidPin }
        let data: Data
        do { data = Data(try statement.text(at: 1).utf8) }
        catch { throw MeetingSpeechModelPinError.invalidPin }
        let pin: StoredMeetingSpeechModelPin
        do { pin = try JSONDecoder().decode(StoredMeetingSpeechModelPin.self, from: data) }
        catch { throw MeetingSpeechModelPinError.invalidPin }
        guard pin.meetingID == meetingID else { throw MeetingSpeechModelPinError.invalidPin }
        try pin.validate()
        return pin
    }

    public func saveSpeechModelPin(_ pin: StoredMeetingSpeechModelPin) throws {
        let database = try connection.database()
        try pin.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pin)
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else { throw MeetingSpeechModelPinError.invalidPin }
        try connection.transaction {
            guard try readMeeting(id: pin.meetingID, database: database) != nil else { throw MeetingStoreError.notFound }
            if let previous = try speechModelPin(meetingID: pin.meetingID) {
                guard previous == pin, try encoder.encode(previous) == data else { throw MeetingSpeechModelPinError.immutableConflict }
                return
            }
            let statement = try MeetingSQLiteStatement(database: database, sql:
                "INSERT INTO meeting_speech_model_pins(meeting_id,selection_json) VALUES(?,?)")
            try statement.bind(pin.meetingID.uuidString, at: 1)
            try statement.bind(text, at: 2)
            try statement.finish()
        }
    }

    /// One immutable generated original, with a separate initial display value.
    /// A duplicate can only replay the exact initial record; it never replaces
    /// later user edits, original JSON bytes, or generation provenance.
    public func createGeneratedDocument(_ document: StoredGeneratedDocument,
                                        commitAdmission: GeneratedDocumentCommitAdmission? = nil) throws {
        let database = try connection.database()
        try validateGeneratedDocument(document, initialRevision: true)
        try connection.transaction {
            // BEGIN IMMEDIATE has acquired the actual writer before this body.
            // A cancelled queued save rolls back before any generated-row write.
            try commitAdmission?.acceptCommit()
            guard try readMeeting(id: document.meetingID, database: database) != nil else {
                throw GeneratedDocumentStoreError.notFound
            }
            if let previous = try readGeneratedDocument(id: document.id, meetingID: nil, database: database) {
                guard previous == document,
                      Data(previous.editedText.utf8) == Data(document.editedText.utf8),
                      previous.question.map({ Data($0.utf8) }) == document.question.map({ Data($0.utf8) }),
                      Data(previous.modelRevision.utf8) == Data(document.modelRevision.utf8),
                      Data(previous.promptVersion.utf8) == Data(document.promptVersion.utf8) else {
                    throw GeneratedDocumentStoreError.immutableConflict
                }
                return
            }
            let statement = try MeetingSQLiteStatement(database: database, sql:
                "INSERT INTO generated_documents(id,meeting_id,kind,original_json,question,edited_text,edit_revision,model_revision,prompt_version,created_at,modified_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)")
            try statement.bind(document.id.uuidString, at: 1)
            try statement.bind(document.meetingID.uuidString, at: 2)
            try statement.bind(document.kind.rawValue, at: 3)
            try statement.bind(document.originalJSON, at: 4)
            try statement.bind(document.question, at: 5)
            try statement.bind(document.editedText, at: 6)
            try statement.bind(document.editRevision, at: 7)
            try statement.bind(document.modelRevision, at: 8)
            try statement.bind(document.promptVersion, at: 9)
            try statement.bind(document.createdAt.timeIntervalSince1970, at: 10)
            try statement.bind(document.modifiedAt.timeIntervalSince1970, at: 11)
            try statement.finish()
        }
    }

    public func generatedDocument(id: UUID, meetingID: UUID) throws -> StoredGeneratedDocument? {
        try readGeneratedDocument(id: id, meetingID: meetingID, database: connection.database())
    }

    public func generatedDocuments(meetingID: UUID, kind: GeneratedDocumentKind? = nil,
                                   limit: Int = 50) throws -> [StoredGeneratedDocument] {
        let database = try connection.database()
        guard (1...1_000).contains(limit) else { throw GeneratedDocumentStoreError.invalidInput }
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT \(Self.generatedDocumentColumns) FROM generated_documents WHERE meeting_id=? AND (? IS NULL OR kind=?) ORDER BY created_at DESC,id ASC LIMIT ?")
        try statement.bind(meetingID.uuidString, at: 1)
        try statement.bind(kind?.rawValue, at: 2)
        try statement.bind(kind?.rawValue, at: 3)
        try statement.bind(Int64(limit), at: 4)
        var documents: [StoredGeneratedDocument] = []
        while try statement.next() { documents.append(try decodeGeneratedDocument(statement)) }
        return documents
    }

    /// Compare-and-swap modifies only the user's display text and edit metadata.
    /// Meeting identity and expected revision are part of the bound SQL update,
    /// inside the same transaction as validation and the returned durable value.
    public func saveGeneratedDocumentEdit(id: UUID, meetingID: UUID, text: String,
                                          expectedRevision: Int64, modifiedAt: Date) throws -> StoredGeneratedDocument {
        let database = try connection.database()
        let (nextRevision, overflow) = expectedRevision.addingReportingOverflow(1)
        guard expectedRevision >= 0, !overflow, modifiedAt.timeIntervalSince1970.isFinite,
              text.utf8.count <= Self.maximumGeneratedBytes else { throw GeneratedDocumentStoreError.invalidInput }
        var committed: StoredGeneratedDocument?
        try connection.transaction {
            guard let current = try readGeneratedDocument(id: id, meetingID: meetingID, database: database) else {
                throw GeneratedDocumentStoreError.notFound
            }
            guard current.editRevision == expectedRevision else { throw GeneratedDocumentStoreError.staleRevision }
            let statement = try MeetingSQLiteStatement(database: database, sql:
                "UPDATE generated_documents SET edited_text=?,edit_revision=?,modified_at=? WHERE id=? AND meeting_id=? AND edit_revision=?")
            try statement.bind(text, at: 1)
            try statement.bind(nextRevision, at: 2)
            try statement.bind(modifiedAt.timeIntervalSince1970, at: 3)
            try statement.bind(id.uuidString, at: 4)
            try statement.bind(meetingID.uuidString, at: 5)
            try statement.bind(expectedRevision, at: 6)
            try statement.finish()
            guard sqlite3_changes(database) == 1 else { throw GeneratedDocumentStoreError.staleRevision }
            committed = try readGeneratedDocument(id: id, meetingID: meetingID, database: database)
            guard committed != nil else { throw MeetingStoreError.databaseFailure }
        }
        guard let committed else { throw MeetingStoreError.databaseFailure }
        return committed
    }

    private static let maximumGeneratedBytes = 1_048_576
    private static let generatedDocumentColumns = "id,meeting_id,kind,original_json,question,edited_text,edit_revision,model_revision,prompt_version,created_at,modified_at"

    private func readGeneratedDocument(id: UUID, meetingID: UUID?,
                                        database: OpaquePointer) throws -> StoredGeneratedDocument? {
        let statement = try MeetingSQLiteStatement(database: database, sql:
            "SELECT \(Self.generatedDocumentColumns) FROM generated_documents WHERE id=? AND (? IS NULL OR meeting_id=?)")
        try statement.bind(id.uuidString, at: 1)
        try statement.bind(meetingID?.uuidString, at: 2)
        try statement.bind(meetingID?.uuidString, at: 3)
        guard try statement.next() else { return nil }
        return try decodeGeneratedDocument(statement)
    }

    private func decodeGeneratedDocument(_ statement: MeetingSQLiteStatement) throws -> StoredGeneratedDocument {
        guard let id = UUID(uuidString: try statement.text(at: 0)),
              let meetingID = UUID(uuidString: try statement.text(at: 1)),
              let kind = GeneratedDocumentKind(rawValue: try statement.text(at: 2)) else {
            throw MeetingStoreError.databaseFailure
        }
        let document = StoredGeneratedDocument(id: id, meetingID: meetingID, kind: kind,
            originalJSON: try statement.blob(at: 3, maximumBytes: Self.maximumGeneratedBytes),
            question: try statement.optionalText(at: 4), editedText: try statement.text(at: 5),
            editRevision: try statement.integer(at: 6), modelRevision: try statement.text(at: 7),
            promptVersion: try statement.text(at: 8), createdAt: Date(timeIntervalSince1970: try statement.real(at: 9)),
            modifiedAt: Date(timeIntervalSince1970: try statement.real(at: 10)))
        do { try validateGeneratedDocument(document, initialRevision: false) }
        catch { throw MeetingStoreError.databaseFailure }
        return document
    }

    private func validateGeneratedDocument(_ document: StoredGeneratedDocument, initialRevision: Bool) throws {
        guard document.editRevision >= 0, !initialRevision || document.editRevision == 0,
              document.createdAt.timeIntervalSince1970.isFinite, document.modifiedAt.timeIntervalSince1970.isFinite,
              !document.originalJSON.isEmpty, document.originalJSON.count <= Self.maximumGeneratedBytes,
              String(data: document.originalJSON, encoding: .utf8) != nil,
              document.editedText.utf8.count <= Self.maximumGeneratedBytes,
              !document.modelRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              document.modelRevision.utf8.count <= 256,
              !document.promptVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              document.promptVersion.utf8.count <= 128 else { throw GeneratedDocumentStoreError.invalidInput }
        switch document.kind {
        case .summary:
            guard document.question == nil else { throw GeneratedDocumentStoreError.invalidInput }
        case .questionAnswer:
            guard let question = document.question,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.utf8.count <= 8_192 else { throw GeneratedDocumentStoreError.invalidInput }
        }
        do {
            guard try JSONSerialization.jsonObject(with: document.originalJSON) is [String: Any] else {
                throw GeneratedDocumentStoreError.invalidInput
            }
        } catch { throw GeneratedDocumentStoreError.invalidInput }
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
