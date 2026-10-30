import Foundation

/// Original manual text, separate from finalized transcript and generated notes.
public struct StoredManualNote: Equatable, Sendable {
    public let meetingID: UUID
    public let text: String
    public let editRevision: Int64
    public let modifiedAt: Date

    public init(meetingID: UUID, text: String, editRevision: Int64, modifiedAt: Date) {
        self.meetingID = meetingID
        self.text = text
        self.editRevision = editRevision
        self.modifiedAt = modifiedAt
    }
}

public enum ManualNoteStoreError: Error, Equatable, Sendable {
    case staleRevision
    case revisionConflict
}
