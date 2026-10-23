#if os(iOS)
import AppIntents
import Foundation

@MainActor
enum RecordingIntentReplies {
    static func message(for outcome: RecordingIntentOutcome) -> LocalizedStringResource {
        switch outcome {
        case .starting: "Preparing recording."
        case .recording: "Recording is active."
        case .stopped: "Recording saved."
        case .idle: "No recording is active."
        case .cleanupPending: "Stopping is still pending. Open LocalMinutes."
        case .blocked(.modelUnavailable): "A verified speech model is required before recording."
        case .blocked(.storageFull): "There is not enough free storage to record."
        case .blocked(.writeFailed): "Recording could not be saved. Open LocalMinutes."
        case .blocked, .requiresForeground:
            "Open LocalMinutes to review recording permissions and status."
        case .staleSession: "This control belongs to an earlier recording."
        }
    }

    static func result(for outcome: RecordingIntentOutcome) -> RecordingNativeResult {
        let resource = message(for: outcome)
        return .result(value: String(localized: resource), dialog: IntentDialog(resource))
    }

    static func perform<I: ForegroundContinuableIntent>(
        _ action: RecordingIntentAction, application: RecordingApplication, intent: I
    ) async throws -> RecordingNativeResult {
        do {
            // Use this caller's value, never a shared lastOutcome after a yield.
            let outcome = try await application.perform(action)
            return result(for: outcome)
        } catch RecordingNativeIntentError.nativeForegroundRequired {
            let dialog = IntentDialog(message(for: .requiresForeground(.captureUnavailable)))
            if #available(iOS 26.0, *) {
                let mode = intent.systemContext.currentMode
                if mode != .background {
                    // Already in foreground: describe the failure without
                    // retrying capture or turning it into recording success.
                    return result(for: .requiresForeground(.captureUnavailable))
                }
                guard mode.canContinueInForeground else {
                    throw RecordingNativeIntentError.foregroundUnavailable
                }
                throw intent.needsToContinueInForegroundError(dialog, alwaysConfirm: true)
            } else {
                throw intent.needsToContinueInForegroundError(dialog, continuation: nil)
            }
        }
    }
}
#endif
