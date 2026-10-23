import Foundation

/// Caller-supplied display content. The resource controller neither derives nor
/// owns recording state, microphone readiness, transcription or completion.
public enum LiveActivityStatus: String, Sendable, Equatable {
    case preparing, recording, stopping, finished, interrupted, failed
}

public enum LiveActivityResourceState: Sendable, Equatable {
    case active, stale, pending, ended, dismissed
}

public typealias LiveActivityStateObserver =
    @MainActor @Sendable (LiveActivityResourceState) -> Void

/// Applied means the matching SDK call returned, not that presentation or
/// physical-device behavior has been verified. Missing resources are explicit.
public enum LiveActivityOperationOutcome: Sendable, Equatable {
    case applied, notFound
}

/// ActivityKit handle boundary only. The actual adapter will observe the real
/// activityStateUpdates sequence and call real async update/end SDK methods.
@MainActor
public protocol LiveActivityHandle: AnyObject {
    var state: LiveActivityResourceState { get }
    func setStateObserver(_ observer: LiveActivityStateObserver?)
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome
}

@MainActor
public protocol LiveActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    /// Synchronous to match Activity.request(attributes:content:pushType:).
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle
}

public enum LiveActivityStartResult: Sendable, Equatable {
    case active, reused, busy, unavailable
}

public enum LiveActivityResourceFailure: Sendable, Equatable {
    case disabled, requestFailed, notActive
}

public enum LiveActivityResourceEvent: Sendable, Equatable {
    case active(UUID)
    case unavailable(UUID, LiveActivityResourceFailure)
    case lost(UUID)
    case updateFailed(UUID)
    case endFailed(UUID)
    /// Resource cleanup acknowledgement, never recording completion.
    case ended(UUID)
}

public struct LiveActivityResourceSnapshot: Sendable, Equatable {
    public let sessionID: UUID?
    public let isActive: Bool
    public let isEnding: Bool

    public init(sessionID: UUID? = nil, isActive: Bool = false, isEnding: Bool = false) {
        self.sessionID = sessionID
        self.isActive = isActive
        self.isEnding = isEnding
    }
}

@MainActor
private final class LiveActivityOwnership {
    let sessionID: UUID
    let handle: any LiveActivityHandle
    var reportedActive = false
    var reportedLost = false
    var lastUpdate: Task<Void, Never>?
    var ending: Task<Void, Never>?

    init(sessionID: UUID, handle: any LiveActivityHandle) {
        self.sessionID = sessionID
        self.handle = handle
    }

    var isActive: Bool {
        guard reportedActive, !reportedLost, ending == nil else { return false }
        return handle.state == .active || handle.state == .stale
    }
}

/// App-owned resource lifetime, independent of views. RecordingCoordinator
/// remains the authority for recording state and the combined readiness gate.
@MainActor
public final class LiveActivityController {
    private let backend: any LiveActivityBackend
    private let onEvent: @MainActor @Sendable (LiveActivityResourceEvent) -> Void
    private var current: LiveActivityOwnership?

    public init(
        backend: any LiveActivityBackend,
        onEvent: @escaping @MainActor @Sendable (LiveActivityResourceEvent) -> Void
    ) {
        self.backend = backend
        self.onEvent = onEvent
    }

    /// Only a returned handle whose actual current state is active may produce
    /// readiness. Same-ID duplicates reuse ownership without a second request
    /// or active event. Any request while end is settling returns busy.
    /// A returned inactive handle remains owned for explicit end cleanup.
    public func start(sessionID: UUID, status: LiveActivityStatus) -> LiveActivityStartResult {
        if let current {
            return current.sessionID == sessionID && current.isActive ? .reused : .busy
        }
        guard backend.areActivitiesEnabled else {
            onEvent(.unavailable(sessionID, .disabled))
            return .unavailable
        }
        let handle: any LiveActivityHandle
        do { handle = try backend.request(sessionID: sessionID, status: status) }
        catch {
            onEvent(.unavailable(sessionID, .requestFailed))
            return .unavailable
        }
        let ownership = LiveActivityOwnership(sessionID: sessionID, handle: handle)
        current = ownership
        handle.setStateObserver { [weak self, weak ownership] state in
            guard let self, let ownership else { return }
            self.receive(state, from: ownership)
        }
        // Read again after observer installation: an ended notification during
        // registration cannot become a later, fabricated active acknowledgement.
        guard handle.state == .active else {
            onEvent(.unavailable(sessionID, .notActive))
            return .unavailable
        }
        ownership.reportedActive = true
        onEvent(.active(sessionID))
        return .active
    }

    /// Ignore stale IDs and updates admitted after ending begins. An end must
    /// settle already-admitted updates before invoking the handle's real end.
    public func update(sessionID: UUID, status: LiveActivityStatus) async {
        guard let ownership = current, ownership.sessionID == sessionID,
              ownership.isActive else { return }
        let previous = ownership.lastUpdate
        let handle = ownership.handle
        let operation = Task {
            await previous?.value
            _ = await handle.update(status: status)
        }
        ownership.lastUpdate = operation
        await operation.value
    }

    /// Matching duplicate ends share cleanup. Emit ended exactly once and only
    /// after the real async end settles, even if an ended state arrives earlier.
    /// Retired handle callbacks cannot affect a replacement using the same ID.
    public func end(sessionID: UUID, status: LiveActivityStatus) async {
        guard let ownership = current, ownership.sessionID == sessionID else { return }
        let operation: Task<Void, Never>
        if let ending = ownership.ending {
            operation = ending
        } else {
            let pendingUpdate = ownership.lastUpdate
            let handle = ownership.handle
            operation = Task {
                await pendingUpdate?.value
                _ = await handle.end(status: status)
            }
            // Close update/start admission before the first suspension.
            ownership.ending = operation
        }
        await operation.value
        guard current === ownership else { return }
        ownership.handle.setStateObserver(nil)
        current = nil
        onEvent(.ended(sessionID))
    }

    private func receive(_ state: LiveActivityResourceState, from ownership: LiveActivityOwnership) {
        guard current === ownership, ownership.reportedActive,
              !ownership.reportedLost, ownership.ending == nil else { return }
        switch state {
        case .ended, .dismissed:
            ownership.reportedLost = true
            onEvent(.lost(ownership.sessionID))
        case .active, .stale, .pending: break
        }
    }

    public func snapshot() -> LiveActivityResourceSnapshot {
        LiveActivityResourceSnapshot(sessionID: current?.sessionID,
            isActive: current?.isActive ?? false, isEnding: current?.ending != nil)
    }
}
