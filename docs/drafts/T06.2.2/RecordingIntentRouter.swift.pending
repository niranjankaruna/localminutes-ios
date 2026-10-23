import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// Values shared by future app-owned Shortcuts/Live Activity adapters.
/// A start/toggle UUID proposes a recording epoch, not a delivery identity.
public enum RecordingIntentAction: Sendable, Equatable {
    case start(UUID)
    case stop(expectedSessionID: UUID?)
    case toggle(UUID)
}

/// Facts about actual owner state; never evidence of real-model inference,
/// free signing, locked execution, or physical microphone success.
public enum RecordingIntentOutcome: Sendable, Equatable {
    case notImplemented
    case starting
    case recording
    case stopped
    case idle
    case cleanupPending
    case blocked(RecordingFailure)
    case requiresForeground(RecordingFailure)
    case staleSession
}

/// TEST-FIRST DRAFT ONLY. App Intents must eventually share this owner's
/// app-held lifetime. No dispatch, state mapping, or retry behavior exists here.
@MainActor
public final class RecordingIntentRouter {
    private let owner: RecordingSessionOwner

    public init(owner: RecordingSessionOwner) {
        self.owner = owner
    }

    public func perform(_ action: RecordingIntentAction) async -> RecordingIntentOutcome {
        .notImplemented
    }
}
