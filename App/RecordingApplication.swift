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
    let services: LocalMinutesServices?
    let playbackOwnership: PlaybackOwnershipController?
    private(set) var lastOutcome: RecordingIntentOutcome?
    private let router: RecordingIntentRouter
    @ObservationIgnored
    private var toggleOperation: (id: UUID, task: Task<RecordingIntentOutcome, Never>)?
    @ObservationIgnored
    private var preparationStop: (id: UUID, task: Task<RecordingIntentOutcome, Never>)?

    private convenience init() {
        self.init(services: try? LocalMinutesServices())
    }

    /// Storage injection only. This is the actual default Live/OS composition;
    /// startup execution and shared admission remain unwired before native RED.
    init(services: LocalMinutesServices?) {
        let preparation: any RecordingPreparationSource
        if let services { preparation = services.live }
        else { preparation = RequiredSpeechModelPreparation() }
        let owner = RecordingSessionOwner(
            permission: IOSCapturePermissionSource(), hardware: IOSCaptureHardware(),
            activityBackend: IOSLiveActivityBackend(), preparation: preparation
        )
        self.services = services
        if let services {
            playbackOwnership = PlaybackOwnershipController(owner: owner, hardware: services)
        } else {
            playbackOwnership = nil
        }
        self.owner = owner
        router = RecordingIntentRouter(owner: owner)
        foreground = nil
    }

    init(owner: RecordingSessionOwner,
         foreground: (any RecordingForegroundContinuation)? = nil,
         playbackOwnership: PlaybackOwnershipController? = nil) {
        services = nil
        self.playbackOwnership = playbackOwnership
        self.owner = owner
        router = RecordingIntentRouter(owner: owner)
        self.foreground = foreground
    }

    func perform(_ action: RecordingIntentAction) async throws -> RecordingIntentOutcome {
        var audioReservation: UUID?
        defer {
            if let audioReservation {
                playbackOwnership?.recordingActionCompleted(operationID: audioReservation)
            }
        }
        switch action {
        case .start, .toggle:
            if let playbackOwnership {
                let operationID = UUID()
                audioReservation = operationID
                guard playbackOwnership.prepareForRecording(operationID: operationID) == .allowed else {
                    lastOutcome = .cleanupPending
                    return .cleanupPending
                }
            }
        case .stop: break
        }
        let outcome: RecordingIntentOutcome
        if case .toggle = action {
            if let operation = toggleOperation {
                if let stop = preparationStop, stop.id == operation.id {
                    outcome = await stop.task.value
                } else {
                    let state = await owner?.snapshot()
                    // Recheck after the actor hop: another toggle may already
                    // have admitted the same scoped preparation cancellation.
                    if let stop = preparationStop, stop.id == operation.id {
                        outcome = await stop.task.value
                    } else if state?.phase == .preparing, let sessionID = state?.sessionID {
                        let router = self.router
                        let task = Task { @MainActor in
                            await router.perform(.stop(expectedSessionID: sessionID))
                        }
                        if toggleOperation?.id == operation.id {
                            preparationStop = (operation.id, task)
                        }
                        outcome = await task.value
                    } else {
                        // Concurrent stops share their existing barrier. A
                        // duplicate waiter's cancellation cannot cancel it.
                        outcome = await operation.task.value
                    }
                }
            } else {
                let operationID = UUID()
                let router = self.router
                let task = Task { @MainActor in
                    let result = await router.perform(action)
                    let settled: RecordingIntentOutcome
                    if let stop = self.preparationStop, stop.id == operationID {
                        // A cancelled preflight may return before its cleanup
                        // task settles. Both native callers await that barrier.
                        settled = await stop.task.value
                    } else {
                        settled = result
                    }
                    if self.toggleOperation?.id == operationID { self.toggleOperation = nil }
                    if self.preparationStop?.id == operationID { self.preparationStop = nil }
                    return settled
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

    func playAudio(at location: MeetingPlaybackLocation) async -> PlaybackOwnershipResult {
        guard let playbackOwnership else { return .unavailable }
        return await playbackOwnership.play(at: location)
    }

    func stopPlayback() -> PlaybackOwnershipResult {
        playbackOwnership?.stop() ?? .stopped
    }

    func playAudio(at location: MeetingPlaybackLocation,
                   requestID: UUID) async -> PlaybackOwnershipResult {
        guard let playbackOwnership else { return .unavailable }
        return await playbackOwnership.play(at: location, requestID: requestID)
    }

    func stopPlayback(expectedRequestID: UUID) -> PlaybackOwnershipResult {
        playbackOwnership?.stop(expectedRequestID: expectedRequestID) ?? .stopped
    }
}
#endif
