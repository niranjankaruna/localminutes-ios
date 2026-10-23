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

/// ActivityKit handle boundary only. The actual adapter will observe the real
/// activityStateUpdates sequence and call real async update/end SDK methods.
@MainActor
public protocol LiveActivityHandle: AnyObject {
    var state: LiveActivityResourceState { get }
    func setStateObserver(_ observer: LiveActivityStateObserver?)
    func update(status: LiveActivityStatus) async
    func end(status: LiveActivityStatus) async
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

/// UNCOMPILED TEST-FIRST STUB. No lifecycle behavior or ActivityKit integration.
/// App-owned resource lifetime, independent of views. RecordingCoordinator
/// remains the authority for recording state and the combined readiness gate.
@MainActor
public final class LiveActivityController {
    public init(
        backend: any LiveActivityBackend,
        onEvent: @escaping @MainActor @Sendable (LiveActivityResourceEvent) -> Void
    ) {}

    /// Only a returned handle whose actual current state is active may produce
    /// readiness. Same-ID duplicates reuse ownership without a second request
    /// or active event. Any request while end is settling returns busy.
    /// A returned inactive handle remains owned for explicit end cleanup.
    public func start(sessionID: UUID, status: LiveActivityStatus) -> LiveActivityStartResult {
        .unavailable
    }

    /// Ignore stale IDs and updates admitted after ending begins. An end must
    /// settle already-admitted updates before invoking the handle's real end.
    public func update(sessionID: UUID, status: LiveActivityStatus) async {}

    /// Matching duplicate ends share cleanup. Emit ended exactly once and only
    /// after the real async end settles, even if an ended state arrives earlier.
    /// Retired handle callbacks cannot affect a replacement using the same ID.
    public func end(sessionID: UUID, status: LiveActivityStatus) async {}

    public func snapshot() -> LiveActivityResourceSnapshot {
        LiveActivityResourceSnapshot()
    }
}
