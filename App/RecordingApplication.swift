#if os(iOS)
import Foundation
import Observation

/// OS foreground-transition boundary only. Production must use the real intent
/// context/API; tests may observe or reject a requested transition.
@MainActor
protocol RecordingForegroundContinuation: AnyObject {
    func requestContinuation(for failure: RecordingFailure) async throws
}

/// Until verified installation and the real CPU recognizer are integrated, a
/// live start must reject rather than treating recording-only as readiness.
@MainActor
private final class RequiredSpeechModelPreparation: RecordingPreparationSource {
    func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        .rejected(.modelUnavailable)
    }
}

/// The application retains its resource owner independently of views. Each
/// caller receives its own result; UI state is only a projection of that result.
@MainActor
@Observable
final class RecordingApplication {
    static let shared = RecordingApplication()

    let owner: RecordingSessionOwner?
    let foreground: (any RecordingForegroundContinuation)?
    private(set) var lastOutcome: RecordingIntentOutcome?
    private let router: RecordingIntentRouter
    @ObservationIgnored
    private var toggleOperation: (id: UUID, task: Task<RecordingIntentOutcome, Never>)?

    private init() {
        let owner = RecordingSessionOwner(
            permission: IOSCapturePermissionSource(), hardware: IOSCaptureHardware(),
            activityBackend: IOSLiveActivityBackend(), preparation: RequiredSpeechModelPreparation()
        )
        self.owner = owner
        router = RecordingIntentRouter(owner: owner)
        foreground = nil
    }

    init(owner: RecordingSessionOwner,
         foreground: (any RecordingForegroundContinuation)? = nil) {
        self.owner = owner
        router = RecordingIntentRouter(owner: owner)
        self.foreground = foreground
    }

    func perform(_ action: RecordingIntentAction) async throws -> RecordingIntentOutcome {
        let outcome: RecordingIntentOutcome
        if case .toggle = action {
            if let operation = toggleOperation {
                // Cancelling a duplicate waiter must not cancel the creator's
                // operation. Keep only one bounded in-flight toggle slot.
                outcome = await operation.task.value
            } else {
                let operationID = UUID()
                let router = self.router
                let task = Task { @MainActor in
                    let result = await router.perform(action)
                    if self.toggleOperation?.id == operationID { self.toggleOperation = nil }
                    return result
                }
                toggleOperation = (operationID, task)
                // Unstructured coalescing tasks do not inherit cancellation.
                // Forward creator cancellation to actual owner preflight.
                outcome = await withTaskCancellationHandler {
                    await task.value
                } onCancel: {
                    task.cancel()
                }
            }
        } else {
            outcome = await router.perform(action)
        }
        lastOutcome = outcome
        if case .requiresForeground(let failure) = outcome {
            guard let foreground else { throw RecordingNativeIntentError.nativeForegroundRequired }
            try await foreground.requestContinuation(for: failure)
        }
        return outcome
    }
}
#endif
