import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum MeetingDeletionError: Error, Equatable, Sendable {
    case meetingInUse
    case unsafePath
    case invalidOwnership
    case metadataFailure
    case filesystemFailure
}

public struct MeetingRecordingLease: Sendable {
    public let meetingID: UUID
    let token: UUID
}

/// No-op test-first gate. Production must reserve before capture preparation
/// and release only after audio/transcript/activity cleanup has fully settled.
@MainActor
public final class MeetingUsageRegistry {
    public init() {}
    public func beginRecording(meetingID: UUID) throws -> MeetingRecordingLease {
        MeetingRecordingLease(meetingID: meetingID, token: meetingID)
    }
    public func endRecording(_ lease: MeetingRecordingLease) {}
}

/// No-op interfaces only. No filesystem or database behavior exists here.
/// Root must prove actual hosted assertion RED before implementing deletion.
public actor MeetingDeletionCoordinator {
    public init(store: SQLiteMeetingStore, recordingsRoot: URL,
                usage: MeetingUsageRegistry) {}

    // A bounded test scheduling boundary only, never a fake database. Production
    // construction above supplies no hook. Tests close the real SQLite adapter.
    init(store: SQLiteMeetingStore, recordingsRoot: URL, usage: MeetingUsageRegistry,
         beforeMetadataDeletion: @escaping @Sendable () async -> Void) {}

    public func delete(meetingID: UUID) async throws {}
    public func recoverPendingDeletions() async throws -> [UUID] { [] }
}
