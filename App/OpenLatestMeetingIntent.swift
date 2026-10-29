#if os(iOS)
import AppIntents
import Foundation

typealias MeetingNavigationIntentResult = IntentResultContainer<String, Never, Never, IntentDialog>

/// Opening private history uses local authentication and foreground routing;
/// it deliberately has no AudioRecordingIntent or LiveActivityIntent role.
struct OpenLatestMeetingIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Last LocalMinutes Meeting" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    private var injectedApplication: RecordingApplication?
    private var injectedRouter: MeetingNavigationRouter?

    init() { injectedApplication = nil; injectedRouter = nil }
    init(application: RecordingApplication, router: MeetingNavigationRouter? = nil) {
        injectedApplication = application; injectedRouter = router
    }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> MeetingNavigationIntentResult {
        try Task.checkCancellation()
        let outcome = try await (injectedRouter ?? application.meetingNavigation).openLatest()
        try Task.checkCancellation()
        switch outcome {
        case .opened:
            return .result(value: "Opening your last meeting.",
                           dialog: IntentDialog("Opening your last meeting."))
        case .emptyLibrary:
            return .result(value: "No saved meetings yet.",
                           dialog: IntentDialog("No saved meetings yet."))
        case .unavailable:
            return .result(value: "Saved meetings are not available.",
                           dialog: IntentDialog("Saved meetings are not available."))
        case .superseded:
            return .result(value: "Opening LocalMinutes.", dialog: IntentDialog("Opening LocalMinutes."))
        }
    }
}

// Apple documents this guarded compatibility declaration for app-owned intents
// on earlier OS versions; iOS26 uses foreground(.immediate) above instead.
// https://developer.apple.com/documentation/appintents/appintent/openappwhenrun
@available(*, deprecated)
extension OpenLatestMeetingIntent {
    static var openAppWhenRun: Bool { true }
}
#endif
