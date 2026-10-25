#if os(iOS)
import Foundation
import UIKit

/// App-owned bridge to the existing request-scoped intelligence cleanup path.
/// Memory warnings must never cancel recording or a different heavy resource.
@MainActor
final class IntelligenceMemoryPressureMonitor {
    private let activeSession: @MainActor () -> IntelligenceSession?
    private var observation: MemoryWarningObservation?
    private var cleanup: (session: ObjectIdentifier, request: UUID, token: UUID, task: Task<Void, Never>)?

    init(center: NotificationCenter = .default,
         activeSession: @escaping @MainActor () -> IntelligenceSession?) {
        self.activeSession = activeSession
        let token = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil) { [weak self] _ in
                // Notification payloads never cross the actor boundary.
                Task { @MainActor [weak self] in self?.receivedMemoryWarning() }
            }
        observation = MemoryWarningObservation(center: center, token: token)
    }

    private func receivedMemoryWarning() {
        guard let session = activeSession() else { return }
        let snapshot = session.snapshot()
        guard let request = snapshot.requestID,
              [.loading, .generating, .saving, .draining, .failed].contains(snapshot.phase) else { return }
        let identity = ObjectIdentifier(session)
        if let cleanup, cleanup.session == identity, cleanup.request == request { return }
        let token = UUID()
        // Retain the exact session/request through its existing cleanup. A later
        // selection or warning cannot cancel a replacement request or ASR lease.
        let task = Task { @MainActor [weak self] in
            do { try await session.cancelAndDrain(requestID: request) }
            catch {
                // The session retains failed cleanup and its admission claim.
                // A subsequent warning or explicit Cancel may retry it; never
                // release another resource or report a fabricated success.
            }
            if self?.cleanup?.token == token { self?.cleanup = nil }
        }
        cleanup = (identity, request, token, task)
    }
}

/// Immutable token ownership makes removal safe when the final reference is
/// released off MainActor. NotificationCenter owns a weak monitor callback;
/// neither observation nor a retained cleanup task forms a service cycle.
private final class MemoryWarningObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, token: any NSObjectProtocol) {
        self.center = center; self.token = token
    }
    deinit { center.removeObserver(token) }
}
#endif
