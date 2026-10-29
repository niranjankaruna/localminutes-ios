#if os(iOS)
import AppIntents
import Foundation
import UIKit

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
        case .blocked(.microphoneDenied), .requiresForeground(.microphoneDenied):
            "Microphone access is needed. Open LocalMinutes → Settings → Recording permissions to allow access."
        case .blocked(.activityUnavailable), .requiresForeground(.activityUnavailable):
            "The recording Live Activity is unavailable. Open LocalMinutes → Settings → Recording permissions to check Live Activities, then try again from Record."
        case .blocked(.captureUnavailable), .requiresForeground(.captureUnavailable):
            "Audio could not start. Open LocalMinutes → Record and try again. If another app is using the microphone, finish that recording or call first."
        case .requiresForeground(let failure):
            message(for: .blocked(failure))
        case .staleSession: "This control belongs to an earlier recording."
        }
    }

    @MainActor static func result(for outcome: RecordingIntentOutcome) -> RecordingNativeResult {
        let resource = message(for: outcome)
        return .result(value: String(localized: resource), dialog: IntentDialog(resource))
    }

    @MainActor static func perform<I: ForegroundContinuableIntent>(
        _ action: RecordingIntentAction, application: RecordingApplication, intent: I
    ) async throws -> RecordingNativeResult {
        try Task.checkCancellation()
        // Publish before any await so a cold launch, an existing foreground
        // scene and a later manual open all land on the actual recording state.
        application.requestRecordingNavigation()
        do {
            // Use this caller's value, never a shared lastOutcome after a yield.
            let outcome = try await application.perform(action)
            return result(for: outcome)
        } catch let error as RecordingForegroundRequiredError {
            let outcome = RecordingIntentOutcome.requiresForeground(error.failure)
            let dialog = IntentDialog(message(for: outcome))
            if #available(iOS 26.0, *) {
                let mode = intent.systemContext.currentMode
                if mode != .background {
                    // Already in foreground: describe the failure without
                    // retrying capture or turning it into recording success.
                    return result(for: outcome)
                }
                guard mode.canContinueInForeground else {
                    throw error
                }
                throw intent.needsToContinueInForegroundError(dialog, alwaysConfirm: true)
            } else {
                if UIApplication.shared.applicationState == .active {
                    return result(for: outcome)
                }
                throw intent.needsToContinueInForegroundError(dialog, continuation: nil)
            }
        }
    }
}
#endif
