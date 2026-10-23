#if os(iOS)
import AppIntents
import Foundation

// TEST-FIRST DECLARATIONS ONLY. Application selection/retention and real SDK
// metadata exist, but no intent dispatches, requests foreground, or reports success.
struct StartMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Start LocalMinutes Recording" }
    static var description: IntentDescription {
        IntentDescription("Start a meeting when the required local models are ready.")
    }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try RecordingNativeIntentError.fail(.notImplemented)
        return .result(value: "Recording control is not implemented.",
                       dialog: "Recording control is not implemented.")
    }
}

struct StopMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop LocalMinutes Recording" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try RecordingNativeIntentError.fail(.notImplemented)
        return .result(value: "Recording control is not implemented.",
                       dialog: "Recording control is not implemented.")
    }
}

struct ToggleMeetingIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Toggle LocalMinutes Recording" }
    static var isDiscoverable: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    private var injectedApplication: RecordingApplication?
    init() { injectedApplication = nil }
    init(application: RecordingApplication) { injectedApplication = application }
    @MainActor var application: RecordingApplication { injectedApplication ?? .shared }

    @MainActor
    func perform() async throws -> RecordingNativeResult {
        try RecordingNativeIntentError.fail(.notImplemented)
        return .result(value: "Recording control is not implemented.",
                       dialog: "Recording control is not implemented.")
    }
}

// Apple's documented compatibility conformance. These declarations do not yet
// call either legacy foreground continuation or the guarded iOS 26 APIs.
@available(*, deprecated)
extension StartMeetingIntent: ForegroundContinuableIntent {}
@available(*, deprecated)
extension StopMeetingIntent: ForegroundContinuableIntent {}
@available(*, deprecated)
extension ToggleMeetingIntent: ForegroundContinuableIntent {}

struct LocalMinutesShortcuts: AppShortcutsProvider {
    // Explicit return keeps the test-first provider empty. Real SDK AppShortcut
    // values/phrases belong after metadata/provider tests have actual RED.
    static var appShortcuts: [AppShortcut] { return [] }
}
#endif
