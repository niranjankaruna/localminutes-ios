#if os(iOS)
import AppIntents
import Foundation

typealias RecordingNativeResult = IntentResultContainer<String, Never, Never, IntentDialog>

/// Shared values contain no owner, microphone engine or meeting content.
enum RecordingNativeIntentError: Error, Equatable, Sendable, LocalizedError {
    case notImplemented
    case applicationUnavailable
    case invalidSession
    case foregroundUnavailable

    var errorDescription: String? {
        switch self {
        case .notImplemented: "Recording control is not implemented."
        case .applicationUnavailable: "Open LocalMinutes to control recording."
        case .invalidSession: "This recording control has an invalid session."
        case .foregroundUnavailable: "Open LocalMinutes to review recording permissions and status."
        }
    }

    /// Always throws. The following typed result is unreachable in each stub;
    /// it never turns the missing dispatcher into optimistic success.
    static func fail(_ error: RecordingNativeIntentError) throws { throw error }
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
        try RecordingNativeIntentError.fail(.applicationUnavailable)
        #else
        try RecordingNativeIntentError.fail(.notImplemented)
        #endif
        return .result(value: "Recording control is not implemented.",
                       dialog: "Recording control is not implemented.")
    }
}
#endif
