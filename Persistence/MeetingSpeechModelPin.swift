import Foundation
#if SWIFT_PACKAGE
import LocalMinutesModels
#endif

/// Immutable capture provenance, independent of the global Equip pointer.
/// Installation identity, full manifest and runtime profile are captured before
/// microphone/audio admission; an older meeting never guesses today's choice.
public struct StoredMeetingSpeechModelPin: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let meetingID: UUID
    public let selection: StoredModelSelection
    public init(schemaVersion: Int = 1, meetingID: UUID, selection: StoredModelSelection) {
        self.schemaVersion = schemaVersion; self.meetingID = meetingID; self.selection = selection
    }
}

public enum MeetingSpeechModelPinError: Error, Equatable, Sendable {
    case missingPin, invalidPin, immutableConflict
}

/// TEST-FIRST interfaces only. Schema5/read/save and live/replay integration
/// require observed native/migration RED. Implementation must move these methods
/// into the existing actor file to retain its private SQLite connection boundary.
extension SQLiteMeetingStore {
    public func speechModelPin(meetingID: UUID) throws -> StoredMeetingSpeechModelPin? { nil }
    public func saveSpeechModelPin(_ pin: StoredMeetingSpeechModelPin) throws {}
}
