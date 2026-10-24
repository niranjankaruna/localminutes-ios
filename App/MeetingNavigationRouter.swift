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

    // Test-first stub: hosted assertions must prove absent navigation before
    // latest-row lookup and app-owned publication are implemented.
    func openLatest() async throws -> LatestMeetingNavigationOutcome { .unavailable }
}

extension RecordingApplication {
    // Test-first composition seam. The real owner must retain one router for
    // its current library; creating one per intent would lose the UI request.
    var meetingNavigation: MeetingNavigationRouter? { nil }
}
#endif
