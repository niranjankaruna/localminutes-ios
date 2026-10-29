#if os(iOS)
import AppIntents
import Foundation

// Actual recording controls share the application-held resource owner. Public
// results describe its facts, never the success of locked or physical dispatch.
struct StartMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Start LocalMinutes Recording" }
    static var description: IntentDescription {
        IntentDescription("Start a meeting in the background when microphone access and the speech model are ready.")
    }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try await RecordingIntentReplies.perform(.start(UUID()), application: application)
    }
}

struct StopMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop LocalMinutes Recording" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try await RecordingIntentReplies.perform(.stop(expectedSessionID: nil),
                                                  application: application)
    }
}

struct ToggleMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Toggle LocalMinutes Recording" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try await RecordingIntentReplies.perform(.toggle(UUID()), application: application)
    }
}

// Earlier iOS versions also keep every recording action in the background.
// Only the separate Open Latest Meeting shortcut presents the application.
@available(*, deprecated)
extension StartMeetingIntent {
    static var openAppWhenRun: Bool { false }
}
@available(*, deprecated)
extension StopMeetingIntent {
    static var openAppWhenRun: Bool { false }
}
@available(*, deprecated)
extension ToggleMeetingIntent {
    static var openAppWhenRun: Bool { false }
}

struct LocalMinutesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartMeetingIntent(),
                    phrases: ["Start recording with \(.applicationName)"],
                    shortTitle: "Start Recording", systemImageName: "mic.fill")
        AppShortcut(intent: StopMeetingIntent(),
                    phrases: ["Stop recording with \(.applicationName)"],
                    shortTitle: "Stop Recording", systemImageName: "stop.fill")
        AppShortcut(intent: ToggleMeetingIntent(),
                    phrases: ["Toggle recording with \(.applicationName)"],
                    shortTitle: "Toggle Recording", systemImageName: "record.circle")
        AppShortcut(intent: OpenLatestMeetingIntent(),
                    phrases: ["Open latest meeting with \(.applicationName)"],
                    shortTitle: "Open Latest Meeting", systemImageName: "text.book.closed")
    }
}
#endif
