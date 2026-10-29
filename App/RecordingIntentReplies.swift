#if os(iOS)
import AppIntents
import AVFoundation
import Foundation

enum RecordingIntentReplies {
    static func message(for outcome: RecordingIntentOutcome,
                        diagnostic: CaptureFailureDiagnostic? = nil) -> LocalizedStringResource {
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
            captureMessage(diagnostic: diagnostic)
        case .requiresForeground(let failure):
            message(for: .blocked(failure), diagnostic: diagnostic)
        case .staleSession: "This control belongs to an earlier recording."
        }
    }

    private static func captureMessage(diagnostic: CaptureFailureDiagnostic?) -> LocalizedStringResource {
        if let diagnostic, diagnostic.stage == .sessionActivation,
           diagnostic.errorDomain == NSOSStatusErrorDomain {
            switch diagnostic.errorCode {
            case Int(AVAudioSession.ErrorCode.cannotStartRecording.rawValue),
                 Int(AVAudioSession.ErrorCode.cannotStartPlaying.rawValue),
                 Int(AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue):
                return "iOS did not allow the audio session to start. Background starts can be restricted even with microphone access. No recording was started."
            case Int(AVAudioSession.ErrorCode.insufficientPriority.rawValue),
                 Int(AVAudioSession.ErrorCode.siriIsRecording.rawValue):
                return "Audio could not start because another audio session has priority. Finish the call, Siri request, or recording in another app, then try again."
            default: break
            }
        }
        return "Audio could not start. Open LocalMinutes → Record and try again."
    }

    @MainActor static func result(for outcome: RecordingIntentOutcome,
                                 diagnostic: CaptureFailureDiagnostic? = nil) -> RecordingNativeResult {
        let resource = message(for: outcome, diagnostic: diagnostic)
        return .result(value: String(localized: resource), dialog: IntentDialog(resource))
    }
}
#endif
