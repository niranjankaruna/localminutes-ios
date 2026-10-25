import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum LibraryStartupState: String, Equatable, Sendable {
    case notStarted, running, ready, failed
}

public enum LibraryStartupError: Error, Equatable, Sendable {
    case metadataFailure, deletionReplayFailure
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

/// Application-lifetime reconciliation. Capture readiness stays closed until
/// durable deletions and every bounded unfinished-meeting page are accounted.
@MainActor @Observable
public final class LibraryStartupCoordinator {
    public private(set) var state: LibraryStartupState = .notStarted
    public private(set) var report: LibraryStartupReport?
    @ObservationIgnored private let store: SQLiteMeetingStore
    @ObservationIgnored private let usage: MeetingUsageRegistry
    @ObservationIgnored private let deletions: MeetingDeletionCoordinator
    @ObservationIgnored private let recovery: MeetingRecoveryCoordinator
    @ObservationIgnored private var operation: Task<LibraryStartupReport, Error>?

    public init(store: SQLiteMeetingStore, recordingsRoot: URL, usage: MeetingUsageRegistry,
                summaryCheckpointRoot: URL? = nil) {
        self.store = store
        self.usage = usage
        deletions = MeetingDeletionCoordinator(store: store, recordingsRoot: recordingsRoot, usage: usage,
            summaryCheckpointRoot: summaryCheckpointRoot)
        recovery = MeetingRecoveryCoordinator(store: store, recordingsRoot: recordingsRoot)
    }

    public func run() async throws -> LibraryStartupReport {
        if let operation { return try await operation.value }
        if state == .ready, let report { return report }
        state = .running
        report = nil
        usage.completeStartup(success: false)
        // View cancellation cannot release admission or abandon a durable
        // deletion halfway through. Every waiter joins the same retained task.
        let task = Task { @MainActor in
            do {
                let result = try await self.reconcile()
                self.report = result
                self.state = .ready
                self.usage.completeStartup(success: true)
                self.operation = nil
                return result
            } catch {
                self.report = nil
                self.state = .failed
                self.usage.completeStartup(success: false)
                self.operation = nil
                throw error
            }
        }
        operation = task
        return try await task.value
    }

    private func reconcile() async throws -> LibraryStartupReport {
        let deleted: [UUID]
        do { deleted = try await deletions.recoverPendingDeletions() }
        catch let failure as MeetingDeletionError where failure == .metadataFailure {
            throw LibraryStartupError.metadataFailure
        } catch { throw LibraryStartupError.deletionReplayFailure }
        var recovered: [UUID] = []
        var issues: [LibraryStartupIssue] = []
        var afterID: UUID?
        while true {
            let page: [MeetingRecord]
            do { page = try await store.unfinishedMeetings(afterID: afterID, limit: 100) }
            catch { throw LibraryStartupError.metadataFailure }
            guard !page.isEmpty else { break }
            // A corrupt/nonadvancing page cannot become an unbounded startup.
            var previous = afterID?.uuidString ?? ""
            for meeting in page {
                guard meeting.id.uuidString > previous else { throw LibraryStartupError.metadataFailure }
                previous = meeting.id.uuidString
                do {
                    _ = try await recovery.recover(meetingID: meeting.id)
                    recovered.append(meeting.id)
                } catch let failure as MeetingRecoveryError {
                    guard failure != .metadataFailure else { throw LibraryStartupError.metadataFailure }
                    issues.append(LibraryStartupIssue(meetingID: meeting.id, failure: failure))
                } catch {
                    issues.append(LibraryStartupIssue(meetingID: meeting.id, failure: .filesystemFailure))
                }
            }
            afterID = page.last?.id
        }
        return LibraryStartupReport(deletedMeetingIDs: deleted,
            recoveredMeetingIDs: recovered, issues: issues)
    }
}
