#if os(iOS)
import AppIntents
import Foundation

/// Action Button shortcuts only navigate. The visible Record button owns the
/// explicit user action that starts microphone capture.
struct OpenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource { "Open LocalMinutes Recording" }
    static var description: IntentDescription {
        IntentDescription("Open the Record screen. Tap Record in the app to start recording.")
    }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> MeetingNavigationIntentResult {
        try Task.checkCancellation()
        application.meetingNavigation.openRecording()
        return .result(value: "Opening recording controls.", dialog: IntentDialog("Opening recording controls."))
    }
}

struct OpenMeetingsIntent: AppIntent {
    static var title: LocalizedStringResource { "Open LocalMinutes Meetings" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.foreground(.immediate)] }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> MeetingNavigationIntentResult {
        try Task.checkCancellation()
        application.meetingNavigation.openMeetings()
        return .result(value: "Opening your meetings.", dialog: IntentDialog("Opening your meetings."))
    }
}

// Earlier OS versions use openAppWhenRun; iOS 26+ uses supportedModes.
@available(*, deprecated)
extension OpenRecordingIntent {
    static var openAppWhenRun: Bool { true }
}
@available(*, deprecated)
extension OpenMeetingsIntent {
    static var openAppWhenRun: Bool { true }
}

struct LocalMinutesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenRecordingIntent(),
                    phrases: ["Open recording in \(.applicationName)"],
                    shortTitle: "Open Recording", systemImageName: "mic")
        AppShortcut(intent: OpenMeetingsIntent(),
                    phrases: ["Open meetings in \(.applicationName)"],
                    shortTitle: "Open Meetings", systemImageName: "text.book.closed")
        AppShortcut(intent: OpenLatestMeetingIntent(),
                    phrases: ["Open last meeting in \(.applicationName)"],
                    shortTitle: "Open Last Meeting", systemImageName: "clock")
    }
}
#endif
