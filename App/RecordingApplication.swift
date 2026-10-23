#if os(iOS)
import Foundation

/// OS foreground-transition boundary only. Production must use the real intent
/// context/API; tests may observe or reject a requested transition.
@MainActor
protocol RecordingForegroundContinuation: AnyObject {
    func requestContinuation(for failure: RecordingFailure) async throws
}

/// TEST-FIRST DECLARATION ONLY. Default composition is intentionally absent;
/// injection only retains the existing concrete owner and an optional OS bound.
@MainActor
final class RecordingApplication {
    static let shared = RecordingApplication()

    let owner: RecordingSessionOwner?
    let foreground: (any RecordingForegroundContinuation)?
    private(set) var lastOutcome: RecordingIntentOutcome?

    private init() {
        owner = nil
        foreground = nil
    }

    init(owner: RecordingSessionOwner,
         foreground: (any RecordingForegroundContinuation)? = nil) {
        self.owner = owner
        self.foreground = foreground
    }

    func perform(_ action: RecordingIntentAction) async throws -> RecordingIntentOutcome {
        throw RecordingNativeIntentError.notImplemented
    }
}
#endif
