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
    private var currentRequestID: UUID?
    private var recordingOperations: Set<UUID> = []
    private var admissionGeneration = UUID()
    private var stopGeneration = UUID()

    init(owner: RecordingSessionOwner, hardware: any PlaybackHardware,
         afterSnapshot: (@MainActor @Sendable (RecordingSnapshot) async -> Void)? = nil) {
        self.owner = owner
        self.hardware = hardware
        self.afterSnapshot = afterSnapshot
    }

    func play(at location: MeetingPlaybackLocation) async -> PlaybackOwnershipResult {
        await play(at: location, requestID: UUID())
    }

    /// The caller retains the request ID across suspension and can later close
    /// only the native player admitted for that exact request.
    func play(at location: MeetingPlaybackLocation, requestID: UUID) async -> PlaybackOwnershipResult {
        let generation = admissionGeneration
        let observedStop = stopGeneration
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
        // Stop revokes requests which have not acquired native playback yet.
        // A cancelled task cannot activate merely because its snapshot arrives.
        guard observedStop == stopGeneration, !Task.isCancelled else { return .unavailable }
        guard releaseOwnedPlayback() == .stopped else { return .cleanupPending }

        // Claim before calling the SDK: a throwing player initialization may
        // follow a successful session activation and still require cleanup.
        hasPlaybackOwnership = true
        currentRequestID = requestID
        do {
            try hardware.startPlayback(at: location)
            return .playing
        } catch {
            return releaseOwnedPlayback() == .stopped ? .unavailable : .cleanupPending
        }
    }

    /// With no playback claim, cleanup never invokes SDK deactivation and
    /// therefore cannot deactivate the recording resource's audio session.
    func stop() -> PlaybackOwnershipResult {
        stopGeneration = UUID()
        return releaseOwnedPlayback()
    }

    func stop(expectedRequestID: UUID) -> PlaybackOwnershipResult {
        guard currentRequestID == expectedRequestID else { return .stopped }
        return releaseOwnedPlayback()
    }

    /// Internal replacement/recording cleanup does not revoke the request which
    /// is currently being admitted. Public global Stop revokes pending requests.
    private func releaseOwnedPlayback() -> PlaybackOwnershipResult {
        guard hasPlaybackOwnership else { return .stopped }
        do {
            try hardware.stopPlayback()
            hasPlaybackOwnership = false
            currentRequestID = nil
            return .stopped
        } catch {
            // The player may be stopped, but its session remains owned until
            // native deactivation succeeds on an explicit caller's retry.
            return .cleanupPending
        }
    }

    /// MainActor-synchronous admission precedes every Start/Toggle suspension.
    /// Failure is returned before any recording preparation or hardware call.
    func prepareForRecording(operationID: UUID) -> PlaybackRecordingAdmission {
        admissionGeneration = UUID()
        recordingOperations.insert(operationID)
        return releaseOwnedPlayback() == .stopped ? .allowed : .cleanupPending
    }

    func recordingActionCompleted(operationID: UUID) {
        recordingOperations.remove(operationID)
    }
}
#endif
