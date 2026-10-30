import Foundation
import SQLite3
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

extension SQLiteMeetingStore {
    /// Enumerates every row without the UI's history/document limits; called under library maintenance.
    public func exportSyncRecords(to destination: URL) throws {
        let database = try connection.database()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw LocalSyncError.invalidData }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw LocalSyncError.invalidData }
        let output = try FileHandle(forWritingTo: destination); defer { try? output.close() }
        func row(_ type: String, _ value: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: ["type": type, "value": value], options: [.sortedKeys, .withoutEscapingSlashes])
            guard bytes.count <= LocalSyncArchive.maximumRecordBytes else { throw LocalSyncError.invalidData }
            try output.write(contentsOf: bytes); try output.write(contentsOf: Data([10]))
        }
        func query(_ sql: String, _ body: (MeetingSQLiteStatement) throws -> Void) throws {
            let statement = try MeetingSQLiteStatement(database: database, sql: sql)
            while try statement.next() { try Task.checkCancellation(); try body(statement) }
        }
        try query("SELECT id,title,created_at,recording_state,captured_sample_count FROM meetings ORDER BY id") { s in
            guard try s.text(at: 3) != "recording" else { throw LocalSyncError.busy }
            try row("meeting", ["id": s.text(at: 0), "title": s.text(at: 1), "createdAt": s.real(at: 2), "recordingState": s.text(at: 3), "capturedSampleCount": s.integer(at: 4)])
        }
        try query("SELECT id,meeting_id,sequence,start_sample,end_sample,text,model_revision FROM transcript_segments ORDER BY meeting_id,sequence") { s in
            try row("segment", ["id": s.text(at: 0), "meetingId": s.text(at: 1), "sequence": s.integer(at: 2), "startSample": s.integer(at: 3), "endSample": s.integer(at: 4), "text": s.text(at: 5), "modelRevision": s.text(at: 6)])
        }
        try query("SELECT meeting_id,text,edit_revision,modified_at FROM manual_notes ORDER BY meeting_id") { s in
            try row("note", ["meetingId": s.text(at: 0), "text": s.text(at: 1), "editRevision": s.integer(at: 2), "modifiedAt": s.real(at: 3)])
        }
        try query("SELECT id,meeting_id,kind,original_json,question,edited_text,edit_revision,model_revision,prompt_version,created_at,modified_at FROM generated_documents ORDER BY meeting_id,created_at,id") { s in
            let original = try s.blob(at: 3, maximumBytes: 1_048_576)
            guard let json = String(data: original, encoding: .utf8) else { throw LocalSyncError.invalidData }
            let question = try s.optionalText(at: 4)
            try row("document", ["id": s.text(at: 0), "meetingId": s.text(at: 1), "kind": s.text(at: 2), "originalJson": json,
                                 "question": question.map { $0 as Any } ?? NSNull(), "editedText": s.text(at: 5), "editRevision": s.integer(at: 6),
                                 "modelRevision": s.text(at: 7), "promptVersion": s.text(at: 8), "createdAt": s.real(at: 9), "modifiedAt": s.real(at: 10)])
        }
        try query("SELECT meeting_id,selection_json FROM meeting_speech_model_pins ORDER BY meeting_id") { s in
            try row("pin", ["meetingId": s.text(at: 0), "selectionJson": s.text(at: 1)])
        }
        try query("SELECT meeting_id,document_id FROM preferred_summaries ORDER BY meeting_id") { s in
            try row("preference", ["meetingId": s.text(at: 0), "documentId": s.text(at: 1)])
        }
        try output.synchronize()
        try PersistentFilePolicy.protectItem(destination, within: destination.deletingLastPathComponent())
    }

    public func syncReceipt(transferID: String) throws -> String? {
        _ = try LocalSyncArchive.canonicalID(transferID)
        let query = try MeetingSQLiteStatement(database: connection.database(), sql: "SELECT digest FROM sync_receipts WHERE transfer_id=?")
        try query.bind(transferID, at: 1)
        return try query.next() ? query.text(at: 0) : nil
    }

    /// Imports into a private candidate generation. All mutable conflicts use the sender's value; absent records are retained.
    public func applySyncRecords(from records: URL, manifest: LocalSyncManifest, digest: String) throws {
        if let previous = try syncReceipt(transferID: manifest.transferId) {
            guard previous == digest else { throw LocalSyncError.identityCollision }; return
        }
        let database = try connection.database()
        func statement(_ sql: String, _ parameters: [Any?]) throws -> MeetingSQLiteStatement {
            let s = try MeetingSQLiteStatement(database: database, sql: sql)
            for (index, value) in parameters.enumerated() {
                let position = Int32(index + 1)
                if value == nil || value is NSNull { try s.bind(nil as String?, at: position) }
                else if let bytes = value as? Data { try s.bind(bytes, at: position) }
                else if let text = value as? String { try s.bind(text, at: position) }
                else if let number = value as? NSNumber {
                    if String(cString: number.objCType) == "d" || String(cString: number.objCType) == "f" { try s.bind(number.doubleValue, at: position) }
                    else { try s.bind(number.int64Value, at: position) }
                } else { throw LocalSyncError.invalidData }
            }
            return s
        }
        func execute(_ sql: String, _ values: [Any?]) throws { try statement(sql, values).finish() }
        func exists(_ sql: String, _ values: [Any?]) throws -> Bool { try statement(sql, values).next() }
        var seen = Set<String>()
        try connection.transaction {
            try LocalSyncArchive.records(records) { record in
                guard let type = record["type"] as? String, let value = record["value"] as? [String: Any] else { throw LocalSyncError.invalidData }
                func string(_ key: String, maximum: Int = 1_048_576) throws -> String {
                    guard let text = value[key] as? String, text.utf8.count <= maximum else { throw LocalSyncError.invalidData }; return text
                }
                func id(_ key: String) throws -> String { try LocalSyncArchive.canonicalID(string(key, maximum: 36)) }
                func integer(_ key: String) throws -> Int64 {
                    guard let number = value[key] as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0,
                          number.doubleValue < Double(Int64.max), number.doubleValue.rounded(.towardZero) == number.doubleValue else { throw LocalSyncError.invalidData }
                    return number.int64Value
                }
                func time(_ key: String) throws -> Double {
                    guard let number = value[key] as? NSNumber, number.doubleValue.isFinite else { throw LocalSyncError.invalidData }; return number.doubleValue
                }
                let identity = try id(["meeting", "segment", "document"].contains(type) ? "id" : "meetingId")
                guard seen.insert(type + ":" + identity).inserted else { throw LocalSyncError.invalidData }
                switch type {
                case "meeting":
                    let title = try string("title", maximum: 4_000), state = try string("recordingState", maximum: 32)
                    let created = try time("createdAt"), samples = try integer("capturedSampleCount")
                    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          ["completed", "interrupted", "recovered", "failed"].contains(state) else { throw LocalSyncError.invalidData }
                    if try exists("SELECT id FROM meetings WHERE id=?", [identity]) {
                        guard try exists("SELECT id FROM meetings WHERE id=? AND created_at=?", [identity, created]) else { throw LocalSyncError.identityCollision }
                        try execute("UPDATE meetings SET title=?,recording_state=CASE WHEN captured_sample_count<=? THEN ? ELSE recording_state END,captured_sample_count=max(captured_sample_count,?) WHERE id=?", [title, samples, state, samples, identity])
                    } else { try execute("INSERT INTO meetings VALUES(?,?,?,?,?)", [identity, title, created, state, samples]) }
                case "segment":
                    let meeting = try id("meetingId"), sequence = try integer("sequence"), start = try integer("startSample"), end = try integer("endSample")
                    guard end >= start else { throw LocalSyncError.invalidData }
                    let values: [Any?] = [identity, meeting, sequence, start, end, try string("text"), try string("modelRevision")]
                    if try exists("SELECT id FROM transcript_segments WHERE id=?", [identity]) {
                        guard try exists("SELECT id FROM transcript_segments WHERE id=? AND meeting_id=? AND sequence=? AND start_sample=? AND end_sample=? AND text=? AND model_revision=?", values) else { throw LocalSyncError.identityCollision }
                    } else { try execute("INSERT INTO transcript_segments VALUES(?,?,?,?,?,?,?)", values) }
                case "note":
                    let text = try string("text"), modified = try time("modifiedAt")
                    try execute("INSERT INTO manual_notes VALUES(?,?,1,?) ON CONFLICT(meeting_id) DO UPDATE SET text=excluded.text,edit_revision=manual_notes.edit_revision+1,modified_at=excluded.modified_at", [identity, text, modified])
                case "document":
                    let meeting = try id("meetingId"), kind = try string("kind", maximum: 32)
                    let original = Data(try string("originalJson").utf8), edited = try string("editedText")
                    guard ["summary", "question_answer"].contains(kind), try JSONSerialization.jsonObject(with: original) is [String: Any] else { throw LocalSyncError.invalidData }
                    let question = value["question"] as? String
                    guard question == nil || question!.utf8.count <= 1_048_576 else { throw LocalSyncError.invalidData }
                    let model = try string("modelRevision"), prompt = try string("promptVersion"), created = try time("createdAt"), modified = try time("modifiedAt")
                    if try exists("SELECT id FROM generated_documents WHERE id=?", [identity]) {
                        guard try exists("SELECT id FROM generated_documents WHERE id=? AND meeting_id=? AND kind=? AND original_json=? AND question IS ? AND model_revision=? AND prompt_version=? AND created_at=?", [identity, meeting, kind, original, question, model, prompt, created]) else { throw LocalSyncError.identityCollision }
                        try execute("UPDATE generated_documents SET edited_text=?,edit_revision=edit_revision+1,modified_at=? WHERE id=?", [edited, modified, identity])
                    } else {
                        try execute("INSERT INTO generated_documents VALUES(?,?,?,?,?,?,0,?,?,?,?)", [identity, meeting, kind, original, question, edited, model, prompt, created, modified])
                    }
                case "pin":
                    let json = try string("selectionJson")
                    guard try JSONSerialization.jsonObject(with: Data(json.utf8)) is [String: Any] else { throw LocalSyncError.invalidData }
                    if try exists("SELECT meeting_id FROM meeting_speech_model_pins WHERE meeting_id=?", [identity]) {
                        guard try exists("SELECT meeting_id FROM meeting_speech_model_pins WHERE meeting_id=? AND selection_json=?", [identity, json]) else { throw LocalSyncError.identityCollision }
                    } else { try execute("INSERT INTO meeting_speech_model_pins VALUES(?,?)", [identity, json]) }
                case "preference":
                    let document = try id("documentId")
                    guard try exists("SELECT id FROM generated_documents WHERE id=? AND meeting_id=? AND kind='summary'", [document, identity]) else { throw LocalSyncError.invalidData }
                    try execute("INSERT INTO preferred_summaries VALUES(?,?) ON CONFLICT(meeting_id) DO UPDATE SET document_id=excluded.document_id", [identity, document])
                default: throw LocalSyncError.unsupportedVersion
                }
            }
            try execute("INSERT INTO sync_receipts VALUES(?,?,?,?)", [manifest.transferId, manifest.sourceId, digest, Date().timeIntervalSince1970])
        }
    }
}
