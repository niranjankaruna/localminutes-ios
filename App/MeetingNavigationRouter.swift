#if os(iOS)
import Foundation
import Observation

enum LatestMeetingNavigationOutcome: Equatable, Sendable {
    case opened(UUID)
    case emptyLibrary
    case unavailable
}

/// Navigation retains only an opaque selected-meeting identifier. It must not
/// start recording or disclose meeting content through an intent response.
@MainActor @Observable
final class MeetingNavigationRouter {
    @ObservationIgnored private let store: SQLiteMeetingStore
    private(set) var requestedMeetingID: UUID?
    private(set) var requestID: UUID?

    init(store: SQLiteMeetingStore) { self.store = store }

    func openLatest() async throws -> LatestMeetingNavigationOutcome {
        try Task.checkCancellation()
        requestedMeetingID = nil
        requestID = nil
        do {
            // Read the durable library for each invocation, including meetings
            // that have not yet appeared in the foreground history projection.
            let latest = try await store.history(limit: 1).first
            try Task.checkCancellation()
            guard let latest else { return .emptyLibrary }
            requestedMeetingID = latest.id
            requestID = UUID()
            return .opened(latest.id)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            requestedMeetingID = nil
            requestID = nil
            return .unavailable
        }
    }
}
#endif
