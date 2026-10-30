#if os(iOS)
import AppIntents
import Foundation

typealias RecordingNativeResult = IntentResultContainer<String, Never, Never, IntentDialog>

/// Shared values contain no owner, microphone engine or meeting content.
enum RecordingNativeIntentError: Error, Equatable, Sendable, LocalizedError {
    case applicationUnavailable
    case invalidSession
    case foregroundUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable: "Open LocalMinutes to control recording."
        case .invalidSession: "This recording control has an invalid session."
        case .foregroundUnavailable:
            "Open LocalMinutes and select Record to see recording status and setup."
        }
    }

}

/// Compile this declaration into app AND extension. The extension only creates
/// the parameterized value for Button(intent:); normal execution belongs to the
/// app process under LiveActivityIntent. No actual OS dispatch is claimed yet.
struct StopRecordingActivityIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop This LocalMinutes Recording" }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Recording session")
    var sessionID: String

    #if !LOCALMINUTES_EXTENSION
    private var injectedApplication: RecordingApplication?
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }
    #endif

    init() { sessionID = "" }
    init(sessionID: String) { self.sessionID = sessionID }

    #if !LOCALMINUTES_EXTENSION
    init(sessionID: String, application: RecordingApplication) {
        self.sessionID = sessionID
        injectedApplication = application
    }
    #endif

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        #if LOCALMINUTES_EXTENSION
        // The extension constructs the control; it never creates capture state.
        throw RecordingNativeIntentError.applicationUnavailable
        #else
        guard let sessionID = UUID(uuidString: sessionID) else {
            throw RecordingNativeIntentError.invalidSession
        }
        let outcome = try await application.perform(.stop(expectedSessionID: sessionID),
                                                     allowForegroundContinuation: false)
        return RecordingIntentReplies.result(for: outcome)
        #endif
    }
}

@available(*, deprecated)
extension StopRecordingActivityIntent {
    static var openAppWhenRun: Bool { false }
}
#endif
