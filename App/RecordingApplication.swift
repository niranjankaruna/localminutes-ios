#if os(iOS)
import Foundation
import Observation
import SwiftUI

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

    private(set) var owner: RecordingSessionOwner?
    let foreground: (any RecordingForegroundContinuation)?
    private(set) var services: LocalMinutesServices?
    private(set) var meetingNavigation: MeetingNavigationRouter?
    private(set) var playbackOwnership: PlaybackOwnershipController?
    private(set) var isRestoringLibrary = false
    @ObservationIgnored private var libraryPlaybackReservation: (controller: PlaybackOwnershipController, id: UUID)?
    private(set) var lastOutcome: RecordingIntentOutcome?
    private var router: RecordingIntentRouter
    @ObservationIgnored private var signalMonitor: IOSRecordingSignalMonitor
    @ObservationIgnored
    private var toggleOperation: (id: UUID, task: Task<RecordingIntentOutcome, Never>)?
    @ObservationIgnored
    private var preparationStop: (id: UUID, task: Task<RecordingIntentOutcome, Never>)?

    private convenience init() {
        self.init(services: try? LocalMinutesServices())
    }

    /// Storage injection only; the default Live/OS composition and its shared
    /// startup/deletion admission remain identical for the app and native tests.
    init(services: LocalMinutesServices?) {
        let preparation: any RecordingPreparationSource
        if let services { preparation = services.live }
        else { preparation = RequiredSpeechModelPreparation() }
        let owner = RecordingSessionOwner(
            permission: IOSCapturePermissionSource(), hardware: IOSCaptureHardware(),
            activityBackend: IOSLiveActivityBackend(), preparation: preparation,
            usageAdmission: services?.recordingAdmission
        )
        self.services = services
        meetingNavigation = services.map { MeetingNavigationRouter(store: $0.store) }
        if let services {
            playbackOwnership = PlaybackOwnershipController(owner: owner, hardware: services)
        } else {
            playbackOwnership = nil
        }
        self.owner = owner
        services?.recordingAdmission?.bind(owner: owner)
        router = RecordingIntentRouter(owner: owner)
        foreground = nil
        let monitor = IOSRecordingSignalMonitor(owner: owner, storageDirectory: services?.meetingsDirectory)
        signalMonitor = monitor
        Self.bindSignals(monitor, to: owner, services: services)
    }

    init(owner: RecordingSessionOwner,
         foreground: (any RecordingForegroundContinuation)? = nil,
         playbackOwnership: PlaybackOwnershipController? = nil,
         signalCenter: NotificationCenter? = nil) {
        services = nil
        meetingNavigation = nil
        self.playbackOwnership = playbackOwnership
        self.owner = owner
        router = RecordingIntentRouter(owner: owner)
        self.foreground = foreground
        let monitor = IOSRecordingSignalMonitor(owner: owner, center: signalCenter ?? .default)
        signalMonitor = monitor
        Self.bindSignals(monitor, to: owner)
    }

    func flushSignals() async { await signalMonitor.flush() }
    func recordScenePhase(_ scenePhase: ScenePhase) throws {
        let visibility: MetricsVisibility
        switch scenePhase {
        case .active: visibility = .foreground
        case .background: visibility = .background
        default: visibility = .unknown
        }
        try services?.metrics?.visibilityChanged(visibility)
        try services?.metrics?.checkpoint()
        try services?.sampleEndurance(visibility: visibility)
    }

    private static func bindSignals(_ monitor: IOSRecordingSignalMonitor, to owner: RecordingSessionOwner,
                                    services: LocalMinutesServices? = nil) {
        var observedID: UUID?
        owner.setEpochObserver { [weak monitor, weak services] id in
            guard let monitor else { return }
            if let id {
                monitor.beginEpoch(sessionID: id)
                services?.beginEnduranceEpoch()
            } else if let previous = observedID {
                monitor.endEpoch(sessionID: previous)
                services?.endEnduranceEpoch()
            }
            observedID = id
        }
    }

    func perform(_ action: RecordingIntentAction) async throws -> RecordingIntentOutcome {
        guard !isRestoringLibrary, services?.maintainingLibrary != true else {
            lastOutcome = .cleanupPending; return .cleanupPending
        }
        switch action {
        case .start, .toggle:
            if let services {
                await services.initialize()
                guard services.startup.state == .ready else {
                    lastOutcome = .cleanupPending
                    return .cleanupPending
                }
                await services.cancelTranscriptRecoveryAndDrain()
                guard services.heavyAdmission?.snapshot().lease?.purpose != .libraryMaintenance else {
                    lastOutcome = .cleanupPending; return .cleanupPending
                }
                // A new capture action takes priority over post-recording
                // generation. The same shared gate remains held until its real
                // worker, runtime and installation lease are fully released.
                if let intelligence = services.intelligence,
                   let held = services.heavyAdmission?.snapshot().lease,
                   held.purpose != .streamingASR {
                    do { try await intelligence.cancelAndDrain(requestID: held.requestID) }
                    catch {
                        lastOutcome = .cleanupPending
                        return .cleanupPending
                    }
                }
            }
        case .stop: break
        }
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
        guard !isRestoringLibrary, services?.maintainingLibrary != true else { return .cleanupPending }
        guard let playbackOwnership else { return .unavailable }
        return await playbackOwnership.play(at: location)
    }

    func stopPlayback() -> PlaybackOwnershipResult {
        playbackOwnership?.stop() ?? .stopped
    }

    func playAudio(at location: MeetingPlaybackLocation,
                   requestID: UUID) async -> PlaybackOwnershipResult {
        guard !isRestoringLibrary, services?.maintainingLibrary != true else { return .cleanupPending }
        guard let playbackOwnership else { return .unavailable }
        return await playbackOwnership.play(at: location, requestID: requestID)
    }

    func stopPlayback(expectedRequestID: UUID) -> PlaybackOwnershipResult {
        playbackOwnership?.stop(expectedRequestID: expectedRequestID) ?? .stopped
    }

    func setLibraryRestoreActive(_ active: Bool) throws {
        if active {
            guard !isRestoringLibrary else { throw LibraryArchiveCoordinatorError.busy }
            if let controller = playbackOwnership {
                let id = UUID()
                guard controller.prepareForRecording(operationID: id) == .allowed else {
                    controller.recordingActionCompleted(operationID: id)
                    throw LibraryArchiveCoordinatorError.busy
                }
                libraryPlaybackReservation = (controller, id)
            }
            isRestoringLibrary = true
        } else {
            // Rebinding services creates a new controller. Release the original
            // controller's exact token, never a token on its replacement.
            if let reservation = libraryPlaybackReservation {
                reservation.controller.recordingActionCompleted(operationID: reservation.id)
            }
            libraryPlaybackReservation = nil
            isRestoringLibrary = false
        }
    }

    /// Replace the composition behind the stable App Intents entry object only
    /// after the new library opens. Old view tasks retain their closed old store.
    func activateLibraryServices(_ services: LocalMinutesServices) {
        let replacement = RecordingApplication(services: services)
        self.services = replacement.services
        meetingNavigation = replacement.meetingNavigation
        owner = replacement.owner
        playbackOwnership = replacement.playbackOwnership
        router = replacement.router
        signalMonitor = replacement.signalMonitor
        toggleOperation = nil; preparationStop = nil; lastOutcome = nil
    }
}
#endif
