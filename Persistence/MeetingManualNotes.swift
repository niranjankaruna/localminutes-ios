import Foundation

// Activate inside the existing LocalMinutesPersistence module with its tests.
// These are deliberately no-op interfaces, not implemented autosave behavior.
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

extension SQLiteMeetingStore {
    public func saveManualNote(_ note: StoredManualNote) throws {}
    public func manualNote(meetingID: UUID) throws -> StoredManualNote? { nil }
}
