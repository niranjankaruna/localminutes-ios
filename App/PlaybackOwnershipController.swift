#if os(iOS)
import Foundation

/// OS player/audio-session operations only. The app retains admission; this
/// boundary neither reads recording state nor fabricates media/model readiness.
@MainActor
protocol PlaybackHardware: AnyObject {
    func startPlayback(at location: MeetingPlaybackLocation) throws
    /// A throw means deactivation did not settle. Ownership must remain held
    /// until an explicit retry succeeds, even when the player already stopped.
    func stopPlayback() throws
}

enum PlaybackOwnershipResult: Sendable, Equatable {
    case notImplemented, playing, stopped, blockedByRecording, cleanupPending, unavailable
}

enum PlaybackRecordingAdmission: Sendable, Equatable {
    case notImplemented, allowed, cleanupPending
}

/// One application-held admission point for the shared OS audio session. The
/// coordinator still owns recording phase; reservations protect the interval
/// before an asynchronous coordinator snapshot can observe a new recording.
@MainActor
final class PlaybackOwnershipController {
    private let owner: RecordingSessionOwner
    private let hardware: any PlaybackHardware
    private let afterSnapshot: (@MainActor @Sendable (RecordingSnapshot) async -> Void)?
    private(set) var hasPlaybackOwnership = false
    private var recordingOperations: Set<UUID> = []
    private var admissionGeneration = UUID()

    init(owner: RecordingSessionOwner, hardware: any PlaybackHardware,
         afterSnapshot: (@MainActor @Sendable (RecordingSnapshot) async -> Void)? = nil) {
        self.owner = owner
        self.hardware = hardware
        self.afterSnapshot = afterSnapshot
    }

    func play(at location: MeetingPlaybackLocation) async -> PlaybackOwnershipResult {
        let generation = admissionGeneration
        let snapshot = await owner.snapshot()
        await afterSnapshot?(snapshot)
        // A start can reserve while the domain actor still reports idle. Even
        // a start which has already settled invalidates this older observation.
        // There is no suspension between these checks and native activation.
        guard generation == admissionGeneration, recordingOperations.isEmpty,
              !snapshot.cleanupPending,
              ![.preparing, .recording, .stopping].contains(snapshot.phase) else {
            return .blockedByRecording
        }
        guard stop() == .stopped else { return .cleanupPending }

        // Claim before calling the SDK: a throwing player initialization may
        // follow a successful session activation and still require cleanup.
        hasPlaybackOwnership = true
        do {
            try hardware.startPlayback(at: location)
            return .playing
        } catch {
            return stop() == .stopped ? .unavailable : .cleanupPending
        }
    }

    /// With no playback claim, cleanup never invokes SDK deactivation and
    /// therefore cannot deactivate the recording resource's audio session.
    func stop() -> PlaybackOwnershipResult {
        guard hasPlaybackOwnership else { return .stopped }
        do {
            try hardware.stopPlayback()
            hasPlaybackOwnership = false
            return .stopped
        } catch {
            // The player may be stopped, but its session remains owned until
            // native deactivation succeeds on an explicit caller's retry.
            return .cleanupPending
        }
    }

    /// Test-first scoped interface only. Preserve the working unscoped API
    /// until native regressions establish RED for request-bound cleanup.
    func play(at location: MeetingPlaybackLocation, requestID: UUID) async -> PlaybackOwnershipResult {
        .notImplemented
    }

    func stop(expectedRequestID: UUID) -> PlaybackOwnershipResult { .notImplemented }

    /// MainActor-synchronous admission precedes every Start/Toggle suspension.
    /// Failure is returned before any recording preparation or hardware call.
    func prepareForRecording(operationID: UUID) -> PlaybackRecordingAdmission {
        admissionGeneration = UUID()
        recordingOperations.insert(operationID)
        return stop() == .stopped ? .allowed : .cleanupPending
    }

    func recordingActionCompleted(operationID: UUID) {
        recordingOperations.remove(operationID)
    }
}
#endif
