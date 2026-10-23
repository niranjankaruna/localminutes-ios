import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// A production ready result requires verified installed ASR resources and the
/// real streaming runtime. File presence or a recording-only fallback is not
/// sufficient. Tests may double this preparation boundary, never inference.
public enum RecordingPreparationResult: Sendable, Equatable {
    case ready(directory: URL)
    case rejected(RecordingFailure)
}

@MainActor
public protocol RecordingPreparationSource: AnyObject {
    var normalizedSink: (any NormalizedCaptureSink)? { get }
    func prepare(sessionID: UUID) async -> RecordingPreparationResult
    func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure?
}

public extension RecordingPreparationSource {
    var normalizedSink: (any NormalizedCaptureSink)? { nil }
    func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure? { nil }
}

@MainActor
private final class RecordingOwnerEpoch {
    let id: UUID
    let reservation: Task<RecordingCommand?, Never>
    var preparation: Task<RecordingPreparationResult, Never>?
    var cleanup: Task<Void, Never>?
    var cleanupRequested = false
    var cancelled = false
    var captureBegan = false
    var audioSessionActive = false
    var firstBufferAccepted = false
    var audioStopped = false
    var transcriptFinished = false
    var activityActive = false
    var activityWasOwned = false
    var activityEnded = false
    var recordingPublished = false
    var failure: RecordingFailure?
    var manifest: AudioCaptureManifest?

    init(id: UUID, reservation: Task<RecordingCommand?, Never>) {
        self.id = id
        self.reservation = reservation
    }
}

/// Resource callbacks contain value facts only. The weak owner breaks the
/// capture/activity closure cycle; it never participates in the audio tap.
@MainActor
private final class RecordingOwnerEventBridge {
    weak var owner: RecordingSessionOwner?
    func capture(_ event: CaptureRuntimeEvent) { owner?.receive(event) }
    func activity(_ event: LiveActivityResourceEvent) { owner?.receive(event) }
}

/// Lifetime is held by the application, independently of views. This owner
/// executes resource commands; the real coordinator remains phase authority.
/// A preparation-ready boundary must include the installed real CPU recognizer.
@MainActor
public final class RecordingSessionOwner {
    private let coordinator = RecordingCoordinator()
    private let preparation: any RecordingPreparationSource
    private let capture: MicrophoneCaptureRuntime
    private let activities: LiveActivityController
    private let beforeReservation: (@MainActor @Sendable () async -> Void)?
    private var current: RecordingOwnerEpoch?

    public private(set) var completedManifest: AudioCaptureManifest?

    public convenience init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
        activityBackend: any LiveActivityBackend,
        preparation: any RecordingPreparationSource
    ) {
        self.init(permission: permission, hardware: hardware, activityBackend: activityBackend,
                  preparation: preparation, beforeReservation: nil)
    }

    /// Deterministic scheduling hook only. Public production construction
    /// always supplies nil; the test still uses the real coordinator actor.
    init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
        activityBackend: any LiveActivityBackend,
        preparation: any RecordingPreparationSource,
        beforeReservation: (@MainActor @Sendable () async -> Void)?
    ) {
        let bridge = RecordingOwnerEventBridge()
        self.preparation = preparation
        self.beforeReservation = beforeReservation
        capture = MicrophoneCaptureRuntime(permission: permission, hardware: hardware,
                                            normalizedSink: preparation.normalizedSink) {
            bridge.capture($0)
        }
        activities = LiveActivityController(backend: activityBackend) {
            bridge.activity($0)
        }
        bridge.owner = self
    }

    public func start(sessionID: UUID) async {
        guard current == nil else { return }
        let coordinator = self.coordinator
        let beforeReservation = self.beforeReservation
        let reservation = Task {
            await beforeReservation?()
            return await coordinator.start(sessionID: sessionID)
        }
        let epoch = RecordingOwnerEpoch(id: sessionID, reservation: reservation)
        // Reserve before any suspension, so competing starts cannot create a
        // second preflight/resource set while the actor command is in flight.
        current = epoch
        completedManifest = nil
        guard let command = await reservation.value, case .prepare = command else {
            if current === epoch, !epoch.cleanupRequested { current = nil }
            return
        }
        guard current === epoch, !epoch.cancelled else { return }
        if Task.isCancelled { await stop(); return }

        let preparation = self.preparation
        let preparing = Task { await preparation.prepare(sessionID: sessionID) }
        epoch.preparation = preparing
        let result = await preparing.value
        guard current === epoch, !epoch.cancelled else { return }
        if Task.isCancelled { await stop(); return }
        switch result {
        case .rejected(let failure):
            epoch.failure = failure
            await reconcile(epoch)
        case .ready(let directory):
            guard let command = await coordinator.preparationSucceeded(for: sessionID),
                  case .activate = command, current === epoch, !epoch.cancelled else { return }
            let result = activities.start(sessionID: sessionID, status: .preparing)
            epoch.activityWasOwned = activities.snapshot().sessionID == sessionID
            guard result == .active || result == .reused else {
                epoch.failure = epoch.failure ?? .activityUnavailable
                await reconcile(epoch)
                return
            }
            guard current === epoch, !epoch.cancelled else { return }
            epoch.captureBegan = true
            await capture.start(sessionID: sessionID, directory: directory)
            await reconcile(epoch)
        }
    }

    public func stop() async {
        guard let epoch = current else { return }
        await requestCleanup(epoch)
    }

    /// A delayed Activity control can close only its exact current epoch.
    public func stop(sessionID: UUID) async {
        guard let epoch = current, epoch.id == sessionID else { return }
        // Latch the matched epoch before any suspension. Even if another caller
        // completes cleanup, this request cannot close its replacement.
        epoch.cancelled = true
        epoch.cleanupRequested = true
        epoch.preparation?.cancel()
        await requestCleanup(epoch)
    }

    public func toggle(sessionID: UUID) async {
        let state = await coordinator.snapshot()
        if state.cleanupPending {
            await stop()
            return
        }
        switch state.phase {
        case .preparing, .recording, .stopping: await stop()
        case .idle, .completed, .interrupted, .recoverableFailure, .failed:
            // A resource epoch may already reserve a start whose actor command
            // has not run yet. Stop closes it immediately and waits for that
            // reservation; silently attempting another start loses the toggle.
            if current != nil { await stop() }
            else { await start(sessionID: sessionID) }
        }
    }

    public func snapshot() async -> RecordingSnapshot {
        await coordinator.snapshot()
    }

    fileprivate func receive(_ event: CaptureRuntimeEvent) {
        let id: UUID
        switch event {
        case .sessionActivated(let value), .firstBufferAccepted(let value), .cancelled(let value),
             .failed(let value, _), .stopped(let value, _): id = value
        }
        guard let epoch = current, epoch.id == id else { return }
        switch event {
        case .sessionActivated: epoch.audioSessionActive = true
        case .firstBufferAccepted: epoch.firstBufferAccepted = true
        case .cancelled: epoch.cancelled = true
        case .failed(_, let failure): epoch.failure = epoch.failure ?? Self.map(failure)
        case .stopped(_, let manifest):
            epoch.audioStopped = true
            epoch.audioSessionActive = false
            epoch.manifest = manifest
        }
        scheduleReconciliation(epoch)
    }

    fileprivate func receive(_ event: LiveActivityResourceEvent) {
        let id: UUID
        switch event {
        case .active(let value), .unavailable(let value, _), .lost(let value),
             .ended(let value), .updateFailed(let value), .endFailed(let value): id = value
        }
        guard let epoch = current, epoch.id == id else { return }
        switch event {
        case .active: epoch.activityActive = true
        case .unavailable, .lost, .updateFailed:
            epoch.activityActive = false
            epoch.failure = epoch.failure ?? .activityUnavailable
        case .ended:
            epoch.activityActive = false
            epoch.activityEnded = true
        case .endFailed:
            epoch.activityActive = false
            epoch.failure = epoch.failure ?? .activityUnavailable
        }
        scheduleReconciliation(epoch)
    }

    private func scheduleReconciliation(_ epoch: RecordingOwnerEpoch) {
        // At most the one-time resource facts are emitted per epoch. These tasks
        // originate on the control/worker path, never inside the real-time tap.
        Task { @MainActor [weak self] in await self?.reconcile(epoch) }
    }

    private func reconcile(_ epoch: RecordingOwnerEpoch) async {
        guard current === epoch else { return }
        if let failure = epoch.failure {
            _ = await coordinator.fail(failure, for: epoch.id)
            guard current === epoch else { return }
            if !epoch.cleanupRequested {
                await requestCleanup(epoch)
            } else if let pending = epoch.cleanup {
                await pending.value
            }
            // A settled failed attempt needs an explicit stop/toggle retry.
            // Late facts must never create an automatic retry loop.
            return
        }
        if epoch.cancelled {
            // Capture cancellation is a cleanup request, not a failure or a
            // completed meeting. Await the same barrier as an explicit stop.
            if !epoch.cleanupRequested {
                await requestCleanup(epoch)
            } else if let pending = epoch.cleanup {
                await pending.value
            }
            return
        }
        await coordinator.updateReadiness(RecordingReadiness(
            audioSessionActive: epoch.audioSessionActive,
            firstBufferAccepted: epoch.firstBufferAccepted,
            activityActive: epoch.activityActive
        ), for: epoch.id)
        let state = await coordinator.snapshot()
        guard current === epoch, !epoch.cancelled, epoch.failure == nil,
              state.phase == .recording, !epoch.recordingPublished else { return }
        epoch.recordingPublished = true
        await activities.update(sessionID: epoch.id, status: .recording)
    }

    private func requestCleanup(_ epoch: RecordingOwnerEpoch) async {
        guard current === epoch else { return }
        if let pending = epoch.cleanup { await pending.value; return }
        epoch.cancelled = true
        epoch.cleanupRequested = true
        epoch.preparation?.cancel()
        let operation = Task { await self.finishCleanup(epoch) }
        epoch.cleanup = operation
        // Callers never clear/finalize this slot after awaiting it. Only the
        // shared attempt can do that, so old waiters cannot erase a new retry.
        await operation.value
    }

    private func finishCleanup(_ epoch: RecordingOwnerEpoch) async {
        _ = await epoch.reservation.value
        guard current === epoch else { return }
        if let failure = epoch.failure {
            _ = await coordinator.fail(failure, for: epoch.id)
        } else {
            _ = await coordinator.stop()
        }
        if let pending = epoch.preparation { _ = await pending.value }
        guard current === epoch else { return }

        if capture.snapshot().activeSessionID == epoch.id {
            await capture.stop(sessionID: epoch.id)
        }
        let audio = capture.snapshot()
        if epoch.captureBegan, let failure = audio.failure {
            epoch.failure = epoch.failure ?? Self.map(failure)
        }
        guard audio.activeSessionID != epoch.id,
              !epoch.captureBegan || epoch.audioStopped else {
            let failure = epoch.failure ?? .captureUnavailable
            epoch.failure = failure
            _ = await coordinator.fail(failure, for: epoch.id)
            epoch.cleanup = nil
            return
        }
        // Capture has closed admission and drained its final converted audio.
        // The transcript consumer must now flush SQLite and release native
        // resources before Saved, activity end, or another epoch is admitted.
        if !epoch.transcriptFinished {
            let failure = await preparation.finish(sessionID: epoch.id, manifest: epoch.manifest)
            guard current === epoch else { return }
            epoch.transcriptFinished = true
            epoch.failure = epoch.failure ?? failure
        }
        if let failure = epoch.failure {
            _ = await coordinator.fail(failure, for: epoch.id)
        }
        if activities.snapshot().sessionID == epoch.id {
            await activities.end(sessionID: epoch.id,
                                 status: epoch.failure == nil ? .finished : .failed)
        }
        guard activities.snapshot().sessionID != epoch.id,
              !epoch.activityWasOwned || epoch.activityEnded else {
            let failure = epoch.failure ?? .activityUnavailable
            epoch.failure = failure
            _ = await coordinator.fail(failure, for: epoch.id)
            epoch.cleanup = nil
            return
        }
        // Value callbacks latch failures synchronously; reconcile any failure
        // raised during drain/end before acknowledging the combined barrier.
        if let failure = epoch.failure {
            _ = await coordinator.fail(failure, for: epoch.id)
        }
        await coordinator.captureStopped(for: epoch.id)
        let final = await coordinator.snapshot()
        guard current === epoch else { return }
        completedManifest = final.phase == .completed && epoch.failure == nil ? epoch.manifest : nil
        current = nil
        epoch.cleanup = nil
    }

    private static func map(_ failure: CaptureRuntimeFailure) -> RecordingFailure {
        switch failure {
        case .microphoneDenied: .microphoneDenied
        case .writeFailed: .writeFailed
        case .sessionUnavailable, .captureUnavailable, .preparationRejected,
             .invalidTimestamp, .queueLoss, .conversionFailed: .captureUnavailable
        }
    }
}
