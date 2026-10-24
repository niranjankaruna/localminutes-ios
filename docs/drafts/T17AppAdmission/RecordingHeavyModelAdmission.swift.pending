import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesRecording
#endif

/// Test-first pass-through seam. Actual per-meeting ownership remains real, but
/// the heavy gate is deliberately not consulted until compatible assertion RED.
@MainActor
public final class RecordingHeavyModelAdmission: RecordingUsageAdmission {
    public let usageRegistry: MeetingUsageRegistry
    public let heavyAdmission: HeavyModelAdmission
    public init(usageRegistry: MeetingUsageRegistry, heavyAdmission: HeavyModelAdmission) {
        self.usageRegistry = usageRegistry; self.heavyAdmission = heavyAdmission
    }
    public func bind(owner: RecordingSessionOwner) { }
    public func acquireRecordingUsage(meetingID: UUID) -> UUID? {
        usageRegistry.acquireRecordingUsage(meetingID: meetingID)
    }
    public func releaseRecordingUsage(meetingID: UUID, token: UUID) {
        usageRegistry.releaseRecordingUsage(meetingID: meetingID, token: token)
    }
    public func finishRecordingUsage(meetingID: UUID, token: UUID) async throws {
        releaseRecordingUsage(meetingID: meetingID, token: token)
    }
}
