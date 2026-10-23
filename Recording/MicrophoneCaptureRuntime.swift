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

/// UNCOMPILED TEST-FIRST STUB. No lifecycle, callback or pipeline behavior is
/// implemented here. Activate and prove hosted behavioral RED before behavior.
///
/// Eventual lifecycle/hardware ownership stays on MainActor. A separate serial
/// worker creates/owns the actual OwnedPCMQueue consumer, PCMStreamConverter and
/// SegmentCAFWriter. AVAudioPCMBuffer is never transferred in a Task: callback
/// input is copied synchronously through the stable admission/queue context.
@MainActor
public final class MicrophoneCaptureRuntime {
    public convenience init(
        permission: any CapturePermissionSource,
        hardware: any CaptureHardware,
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
    ) {}

    /// Resource-idempotent for duplicate or competing requests. Read actual
    /// format only after activation. Engine start alone is not first-buffer
    /// readiness. Permission cancellation closes the epoch before any late grant.
    public func start(sessionID: UUID, directory: URL) async {}

    /// Ignore stale IDs. Close admission, stop/remove hardware, wait outside the
    /// callback for quiescence, finish/drain queue and actual converter/writer,
    /// deactivate, then emit stopped once. Preserve failures; never invent output.
    public func stop(sessionID: UUID) async {}

    public func snapshot() -> CaptureRuntimeSnapshot {
        CaptureRuntimeSnapshot()
    }
}
