import Foundation

public enum GeneratedDocumentKind: String, Codable, Equatable, Sendable {
    case summary
    case questionAnswer = "question_answer"
}

/// The original validated generated payload and its provenance remain immutable.
/// Only editedText/editRevision/modifiedAt may change through the edit API.
/// Manual notes and finalized transcripts are independent original records.
public struct StoredGeneratedDocument: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let meetingID: UUID
    public let kind: GeneratedDocumentKind
    public let originalJSON: Data
    public let question: String?
    public let editedText: String
    public let editRevision: Int64
    public let modelRevision: String
    public let promptVersion: String
    public let createdAt: Date
    public let modifiedAt: Date

    public init(id: UUID, meetingID: UUID, kind: GeneratedDocumentKind, originalJSON: Data,
                question: String?, editedText: String, editRevision: Int64 = 0,
                modelRevision: String, promptVersion: String, createdAt: Date, modifiedAt: Date) {
        self.id = id; self.meetingID = meetingID; self.kind = kind; self.originalJSON = originalJSON
        self.question = question; self.editedText = editedText; self.editRevision = editRevision
        self.modelRevision = modelRevision; self.promptVersion = promptVersion
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }
}

public enum GeneratedDocumentStoreError: Error, Equatable, Sendable {
    case invalidInput, notFound, staleRevision, immutableConflict
}
