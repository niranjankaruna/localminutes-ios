import Foundation

/// Application-lifetime resource admission shared with owned deletion/recovery.
/// Nil rejects a start before preparation or OS resource use. The exact token
/// remains held until the owner finishes every audio/transcript/activity barrier.
@MainActor
public protocol RecordingUsageAdmission: AnyObject {
    func acquireRecordingUsage(meetingID: UUID) -> UUID?
    func releaseRecordingUsage(meetingID: UUID, token: UUID)
}
