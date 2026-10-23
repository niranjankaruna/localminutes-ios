import AVFoundation
import Foundation

/// Synchronous borrowed input. Neither buffer nor timestamp may escape the call.
/// The eventual native tap captures only a stable Sendable callback context.
public typealias CaptureTapHandler = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

@MainActor
public protocol CapturePermissionSource: AnyObject {
    func requestRecordPermission() async -> Bool
}

/// Hardware boundary only. No queue, conversion or persistence doubles belong
/// behind this interface. Stop/removal do not claim callback quiescence.
@MainActor
public protocol CaptureHardware: AnyObject {
    func activateSession() throws
    func inputFormat() throws -> AVAudioFormat
    func installTap(_ handler: @escaping CaptureTapHandler) throws
    func startEngine() throws
    func stopEngine()
    func removeTap()
    func deactivateSession() throws
}

public enum CaptureRuntimeFailure: Error, Sendable, Equatable {
    case microphoneDenied
    case sessionUnavailable
    case captureUnavailable
    case preparationRejected
    case invalidTimestamp
    case queueLoss
    case conversionFailed
    case writeFailed
}

/// Audio-resource evidence only. RecordingCoordinator owns recording state.
/// No event asserts ActivityKit readiness, transcription or recording success.
public enum CaptureRuntimeEvent: Sendable, Equatable {
    case sessionActivated(UUID)
    case firstBufferAccepted(UUID)
    case cancelled(UUID)
    case failed(UUID, CaptureRuntimeFailure)
    /// Cleanup acknowledgement. A nil manifest conveys no successful media;
    /// failures remain separately latched. Emit after deactivation and drain.
    case stopped(UUID, AudioCaptureManifest?)
}

public struct CaptureRuntimeSnapshot: Sendable, Equatable {
    public let activeSessionID: UUID?
    public let audioSessionActive: Bool
    public let firstBufferAccepted: Bool
    public let cleanupPending: Bool
    public let failure: CaptureRuntimeFailure?

    public init(
        activeSessionID: UUID? = nil,
        audioSessionActive: Bool = false,
        firstBufferAccepted: Bool = false,
        cleanupPending: Bool = false,
        failure: CaptureRuntimeFailure? = nil
    ) {
        self.activeSessionID = activeSessionID
        self.audioSessionActive = audioSessionActive
        self.firstBufferAccepted = firstBufferAccepted
        self.cleanupPending = cleanupPending
        self.failure = failure
    }
}

/// Internal deterministic-test sizing only. Public construction uses the
/// defaults. The queue's existing checked 16 MiB bound still applies.
struct CaptureRuntimeTestConfiguration: Sendable {
    let queueCapacity: Int
    let maxFramesPerBuffer: Int
    let maximumSegmentFrames: Int64

    init(
        queueCapacity: Int = 8,
        maxFramesPerBuffer: Int = 8_192,
        maximumSegmentFrames: Int64 = 960_000
    ) {
        self.queueCapacity = queueCapacity
        self.maxFramesPerBuffer = maxFramesPerBuffer
        self.maximumSegmentFrames = maximumSegmentFrames
    }
}

@MainActor
private final class CaptureRuntimeEpoch {
    let id: UUID
    var permissionPending = true
    var sessionActive = false
    var tapInstalled = false
    var cleanupPending = false
    var cancelled = false
    var firstBufferAccepted = false
    var failure: CaptureRuntimeFailure?
    var context: CaptureTapContext?
    var worker: CaptureAudioWorker?
    var preparation: Task<CaptureRuntimeFailure?, Never>?
    var stopping: Task<Void, Never>?

    init(id: UUID) { self.id = id }
}

/// App-owned audio resources. RecordingCoordinator remains the recording state
/// authority. Only value facts cross back from the serial conversion/file worker;
/// the real-time tap captures its own stable context and no actor or Task.
@MainActor
public final class MicrophoneCaptureRuntime {
    private let permission: any CapturePermissionSource
    private let hardware: any CaptureHardware
    private let onEvent: @MainActor @Sendable (CaptureRuntimeEvent) -> Void
    private let configuration: CaptureRuntimeTestConfiguration
    private let afterAdmission: (@Sendable () -> Void)?
    private var current: CaptureRuntimeEpoch?
    private var lastFailure: CaptureRuntimeFailure?

    public convenience init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
        normalizedSink: (any NormalizedCaptureSink)? = nil,
        onEvent: @escaping @MainActor @Sendable (CaptureRuntimeEvent) -> Void
    ) {
        self.init(
            permission: permission,
            hardware: hardware,
            onEvent: onEvent,
            configuration: CaptureRuntimeTestConfiguration(),
            afterAdmission: nil
        )
    }

    /// Test scheduling hook only, after real admission and before real queue
    /// enqueue. The public initializer always supplies nil. Never install it in
    /// production: the test may deliberately wait, but production callbacks must
    /// not wait, allocate, create a Task, lock, convert or write files.
    init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
        onEvent: @escaping @MainActor @Sendable (CaptureRuntimeEvent) -> Void,
        configuration: CaptureRuntimeTestConfiguration,
        afterAdmission: (@Sendable () -> Void)?
    ) {
        self.permission = permission
        self.hardware = hardware
        self.onEvent = onEvent
        self.configuration = configuration
        self.afterAdmission = afterAdmission
    }

    /// Resource-idempotent for duplicate or competing requests. Read actual
    /// format only after activation. Engine start alone is not first-buffer
    /// readiness. Permission cancellation closes the epoch before any late grant.
    public func start(sessionID: UUID, directory: URL) async {
        guard current == nil else { return }
        let epoch = CaptureRuntimeEpoch(id: sessionID)
        current = epoch
        lastFailure = nil
        let granted = await permission.requestRecordPermission()
        guard current === epoch, !epoch.cleanupPending else { return }
        epoch.permissionPending = false
        if Task.isCancelled {
            cancel(epoch)
            await stop(sessionID: sessionID)
            return
        }
        guard granted else {
            fail(epoch, .microphoneDenied)
            await stop(sessionID: sessionID)
            return
        }
        do { try hardware.activateSession() }
        catch {
            fail(epoch, .sessionUnavailable)
            await stop(sessionID: sessionID)
            return
        }
        epoch.sessionActive = true
        onEvent(.sessionActivated(sessionID))

        let context: CaptureTapContext
        do {
            // Preferred rates are hints. The active device format determines
            // queue sizing, timestamp validation and the native converter.
            let input = try CaptureInputDescription(hardware.inputFormat())
            context = try CaptureTapContext(input: input, configuration: configuration,
                                            afterAdmission: afterAdmission)
        } catch {
            fail(epoch, .preparationRejected)
            await stop(sessionID: sessionID)
            return
        }
        epoch.context = context
        let worker = CaptureAudioWorker(context: context)
        epoch.worker = worker
        let maximumSegmentFrames = configuration.maximumSegmentFrames
        let preparation = Task {
            await worker.prepare(directory: directory, sessionID: sessionID,
                                 maximumSegmentFrames: maximumSegmentFrames)
        }
        epoch.preparation = preparation
        let preparationFailure = await preparation.value
        guard current === epoch, !epoch.cleanupPending else { return }
        if Task.isCancelled {
            cancel(epoch)
            await stop(sessionID: sessionID)
            return
        }
        if let preparationFailure {
            fail(epoch, preparationFailure)
            await stop(sessionID: sessionID)
            return
        }
        do {
            try hardware.installTap(context.makeHandler())
            epoch.tapInstalled = true
            try hardware.startEngine()
        } catch {
            fail(epoch, .captureUnavailable)
            await stop(sessionID: sessionID)
            return
        }
        worker.beginPolling { [weak self, weak epoch] facts in
            guard let self, let epoch else { return }
            // This Task is created on the conversion worker, never the tap.
            Task { @MainActor in
                await self.receive(facts, for: epoch)
            }
        }
    }

    /// Ignore stale IDs. Close admission, stop/remove hardware, wait outside the
    /// callback for quiescence, finish/drain queue and actual converter/writer,
    /// deactivate, then emit stopped once. Preserve failures; never invent output.
    public func stop(sessionID: UUID) async {
        guard let epoch = current, epoch.id == sessionID else { return }
        if let stopping = epoch.stopping { await stopping.value; return }
        epoch.cleanupPending = true
        if epoch.permissionPending { cancel(epoch) }
        epoch.context?.admission.close()
        if epoch.tapInstalled {
            hardware.stopEngine()
            hardware.removeTap()
            epoch.tapInstalled = false
        }
        let stopping = Task { await self.finish(epoch) }
        epoch.stopping = stopping
        await stopping.value
    }

    private func cancel(_ epoch: CaptureRuntimeEpoch) {
        guard !epoch.cancelled else { return }
        epoch.cancelled = true
        onEvent(.cancelled(epoch.id))
    }

    private func fail(_ epoch: CaptureRuntimeEpoch, _ failure: CaptureRuntimeFailure) {
        guard epoch.failure == nil else { return }
        epoch.failure = failure
        lastFailure = failure
        onEvent(.failed(epoch.id, failure))
    }

    private func publishFirstBuffer(_ epoch: CaptureRuntimeEpoch) {
        if !epoch.firstBufferAccepted, epoch.context?.firstBufferAccepted == true {
            epoch.firstBufferAccepted = true
            onEvent(.firstBufferAccepted(epoch.id))
        }
    }

    private func receive(_ facts: CaptureWorkerFacts, for epoch: CaptureRuntimeEpoch) async {
        guard current === epoch else { return }
        publishFirstBuffer(epoch)
        if let failure = facts.failure {
            fail(epoch, failure)
            if !epoch.cleanupPending { await stop(sessionID: epoch.id) }
        }
    }

    private func finish(_ epoch: CaptureRuntimeEpoch) async {
        // Preparation may be finishing off-thread. A concurrent stop owns all
        // subsequent cleanup; the resumed start sees cleanupPending and exits.
        if let preparation = epoch.preparation,
           let failure = await preparation.value { fail(epoch, failure) }
        if let context = epoch.context {
            while !context.admission.isClosedAndQuiescent {
                // Retain the epoch until the admitted callback has published
                // its exit, even if the caller cancels this shutdown request.
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        let result = await epoch.worker?.finish()
        publishFirstBuffer(epoch)
        if let failure = result?.failure ?? epoch.context?.failure { fail(epoch, failure) }
        if epoch.sessionActive {
            do {
                try hardware.deactivateSession()
                epoch.sessionActive = false
            } catch {
                // Failed deactivation is not a cleanup acknowledgement. Keep
                // resource state honest and allow an explicit retry later.
                fail(epoch, .sessionUnavailable)
                epoch.stopping = nil
                return
            }
        }
        guard current === epoch else { return }
        epoch.cleanupPending = false
        current = nil
        let manifest = epoch.failure == nil && !epoch.cancelled ? result?.manifest : nil
        onEvent(.stopped(epoch.id, manifest))
    }

    public func snapshot() -> CaptureRuntimeSnapshot {
        CaptureRuntimeSnapshot(activeSessionID: current?.id,
            audioSessionActive: current?.sessionActive ?? false,
            firstBufferAccepted: current?.firstBufferAccepted ?? false,
            cleanupPending: current?.cleanupPending ?? false,
            failure: current?.failure ?? lastFailure)
    }
}
