import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum MeetingRecoveryError: Error, Equatable, Sendable {
    case notImplemented, unsafePath, invalidManifest, metadataFailure, meetingInUse
}

public enum AudioRecoveryGapReason: String, Codable, Sendable {
    case missingAudio, corruptAudio, manifestGap
}

public struct AudioRecoveryGap: Equatable, Codable, Sendable {
    public let startSample: Int64
    public let endSample: Int64
    public let reason: AudioRecoveryGapReason
}

public struct MeetingRecoveryReport: Equatable, Codable, Sendable {
    public let meetingID: UUID
    public let durableFrameCount: Int64
    public let timelineEndSample: Int64
    public let resumeFromSample: Int64
    public let gaps: [AudioRecoveryGap]
    public let quarantinedFiles: [String]
}

/// Test-first interface only. Recovery must reconcile actual CAF/SQLite bytes,
/// retain original transcript rows and never turn a terminated session complete.
public actor MeetingRecoveryCoordinator {
    public init(store: SQLiteMeetingStore, recordingsRoot: URL) {}

    // Test scheduling only: failure closes the actual SQLite connection after
    // real quarantine work. Production supplies no hook.
    init(store: SQLiteMeetingStore, recordingsRoot: URL,
         beforeMetadataUpdate: @escaping @Sendable () async -> Void) {}

    public func recover(meetingID: UUID, activeMeetingIDs: Set<UUID> = []) async throws -> MeetingRecoveryReport {
        throw MeetingRecoveryError.notImplemented
    }
}
