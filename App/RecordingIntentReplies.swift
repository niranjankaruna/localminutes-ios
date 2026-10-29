#if os(iOS)
import AppIntents
import Foundation

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

    @MainActor static func perform(
        _ action: RecordingIntentAction, application: RecordingApplication
    ) async throws -> RecordingNativeResult {
        try Task.checkCancellation()
        // Select Record for the next manual open without presenting the app.
        application.requestRecordingNavigation()
        // Setup failures remain truthful results. They never request a scene
        // activation, launch the app or retry a recording in the foreground.
        let outcome = try await application.perform(action, allowForegroundContinuation: false)
        return result(for: outcome)
    }
}
#endif
