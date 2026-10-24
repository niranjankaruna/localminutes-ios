import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum LibraryStartupState: String, Equatable, Sendable {
    case notStarted, running, ready, failed
}

public enum LibraryStartupError: Error, Equatable, Sendable {
    case notImplemented, metadataFailure, deletionReplayFailure
}

public struct LibraryStartupIssue: Equatable, Sendable {
    public let meetingID: UUID
    public let failure: MeetingRecoveryError

    public init(meetingID: UUID, failure: MeetingRecoveryError) {
        self.meetingID = meetingID
        self.failure = failure
    }
}

public struct LibraryStartupReport: Equatable, Sendable {
    public let deletedMeetingIDs: [UUID]
    public let recoveredMeetingIDs: [UUID]
    public let issues: [LibraryStartupIssue]

    public init(deletedMeetingIDs: [UUID], recoveredMeetingIDs: [UUID], issues: [LibraryStartupIssue]) {
        self.deletedMeetingIDs = deletedMeetingIDs
        self.recoveredMeetingIDs = recoveredMeetingIDs
        self.issues = issues
    }
}

/// Test-first no-op. No deletion/recovery/admission readiness is performed.
/// Root must record actual hosted assertion RED before startup behavior exists.
@MainActor @Observable
public final class LibraryStartupCoordinator {
    public private(set) var state: LibraryStartupState = .notStarted
    public private(set) var report: LibraryStartupReport?

    public init(store: SQLiteMeetingStore, recordingsRoot: URL, usage: MeetingUsageRegistry) {}

    public func run() async throws -> LibraryStartupReport { throw LibraryStartupError.notImplemented }
}
