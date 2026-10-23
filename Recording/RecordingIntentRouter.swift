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
    case starting
    case recording
    case stopped
    case idle
    case cleanupPending
    case blocked(RecordingFailure)
    case requiresForeground(RecordingFailure)
    case staleSession
}

/// App Intents and foreground controls share one application-held owner.
/// Results describe settled resource facts, without promising OS activation.
@MainActor
public final class RecordingIntentRouter {
    private let owner: RecordingSessionOwner
    private let afterOperation: (@MainActor @Sendable () async -> Void)?

    public convenience init(owner: RecordingSessionOwner) {
        self.init(owner: owner, afterOperation: nil)
    }

    /// Test scheduling only; public application construction always uses nil.
    init(owner: RecordingSessionOwner,
         afterOperation: (@MainActor @Sendable () async -> Void)?) {
        self.owner = owner
        self.afterOperation = afterOperation
    }

    public func perform(_ action: RecordingIntentAction) async -> RecordingIntentOutcome {
        let before = await owner.snapshot()
        let wasActive = before.cleanupPending ||
            [.preparing, .recording, .stopping].contains(before.phase)
        let completionSessionID: UUID?
        let controlledSessionID: UUID?
        switch action {
        case .start(let sessionID):
            completionSessionID = nil
            controlledSessionID = nil
            await owner.start(sessionID: sessionID)
        case .stop(let expectedSessionID):
            completionSessionID = wasActive ? before.sessionID : nil
            controlledSessionID = expectedSessionID ?? before.sessionID
            if let expectedSessionID {
                guard before.sessionID == expectedSessionID else { return .staleSession }
                // The owner repeats the epoch guard and closes admission before
                // suspension. This snapshot alone cannot authorize cleanup.
                await owner.stop(sessionID: expectedSessionID)
            } else {
                await owner.stop()
            }
        case .toggle(let sessionID):
            completionSessionID = wasActive ? before.sessionID : nil
            controlledSessionID = completionSessionID
            await owner.toggle(sessionID: sessionID)
        }

        await afterOperation?()
        let state = await owner.snapshot()
        if let controlledSessionID, let currentSessionID = state.sessionID,
           controlledSessionID != currentSessionID {
            return .staleSession
        }
        if state.cleanupPending { return .cleanupPending }
        if let failure = state.failure {
            switch failure {
            case .microphoneDenied, .activityUnavailable, .captureUnavailable:
                return .requiresForeground(failure)
            case .modelUnavailable, .storageFull, .writeFailed:
                return .blocked(failure)
            }
        }
        switch state.phase {
        case .preparing: return .starting
        case .recording: return .recording
        case .stopping: return .cleanupPending
        case .completed:
            // A prior saved recording does not turn an idle/duplicate stop into
            // a new completion. Only the completed matching media can do so.
            if let completionSessionID, let manifest = owner.completedManifest,
               manifest.sessionID == completionSessionID,
               manifest.sessionID == state.sessionID, manifest.totalFrames > 0 {
                return .stopped
            }
            return .idle
        case .idle, .interrupted, .recoverableFailure, .failed:
            return .idle
        }
    }
}
