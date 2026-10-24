import Foundation

/// Application-lifetime resource admission shared with owned deletion/recovery.
/// Nil rejects a start before preparation or OS resource use. The exact token
/// remains held until the owner finishes every audio/transcript/activity barrier.
@MainActor
public protocol RecordingUsageAdmission: AnyObject {
    func acquireRecordingUsage(meetingID: UUID) -> UUID?
    func releaseRecordingUsage(meetingID: UUID, token: UUID)
    /// Invoked after resource barriers, before acknowledging owner completion.
    func finishRecordingUsage(meetingID: UUID, token: UUID) async throws
}

public extension RecordingUsageAdmission {
    func finishRecordingUsage(meetingID: UUID, token: UUID) async throws {
        releaseRecordingUsage(meetingID: meetingID, token: token)
    }
}
