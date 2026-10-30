#if os(iOS)
import Foundation
import Observation

enum LatestMeetingNavigationOutcome: Equatable, Sendable {
    case opened(UUID)
    case emptyLibrary
    case unavailable
    case superseded
}

enum MeetingNavigationDestination: Equatable, Sendable {
    case recording
    case meetings
    case meeting(UUID)
}

struct MeetingNavigationRequest: Equatable, Sendable {
    let id: UUID
    let destination: MeetingNavigationDestination
}

/// Navigation retains only an opaque selected-meeting identifier. It must not
/// start recording or disclose meeting content through an intent response.
@MainActor @Observable
final class MeetingNavigationRouter {
    @ObservationIgnored private let store: SQLiteMeetingStore?
    @ObservationIgnored private var latestRequestID: UUID?
    @ObservationIgnored private let beforeLatestRead: (@MainActor @Sendable () async -> Void)?
    private(set) var request: MeetingNavigationRequest?

    init(store: SQLiteMeetingStore?, beforeLatestRead: (@MainActor @Sendable () async -> Void)? = nil) {
        self.store = store
        // Deterministic test scheduling only; production leaves this nil.
        self.beforeLatestRead = beforeLatestRead
    }

    func openRecording() { publish(.recording) }
    func openMeetings() { publish(.meetings) }

    func consumeRequest(_ id: UUID) {
        guard request?.id == id else { return }
        request = nil
    }

    private func publish(_ destination: MeetingNavigationDestination) {
        let id = UUID()
        latestRequestID = id
        request = .init(id: id, destination: destination)
    }

    func openLatest() async throws -> LatestMeetingNavigationOutcome {
        try Task.checkCancellation()
        let id = UUID()
        latestRequestID = id
        request = nil
        do {
            await beforeLatestRead?()
            try Task.checkCancellation()
            // Read the durable library for each invocation, including meetings
            // that have not yet appeared in the foreground history projection.
            let latest = try await store?.history(limit: 1).first
            try Task.checkCancellation()
            guard latestRequestID == id else { return .superseded }
            guard let latest else {
                request = .init(id: id, destination: .meetings)
                return store == nil ? .unavailable : .emptyLibrary
            }
            request = .init(id: id, destination: .meeting(latest.id))
            return .opened(latest.id)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            guard latestRequestID == id else { return .superseded }
            request = .init(id: id, destination: .meetings)
            return .unavailable
        }
    }
}
#endif
