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

/// Test-first interface only. No admission algorithm or native player behavior
/// exists here until compatible native tests have a recorded behavioral RED.
@MainActor
final class PlaybackOwnershipController {
    private let owner: RecordingSessionOwner
    private let hardware: any PlaybackHardware
    private let afterSnapshot: (@MainActor @Sendable (RecordingSnapshot) async -> Void)?
    private(set) var hasPlaybackOwnership = false

    init(owner: RecordingSessionOwner, hardware: any PlaybackHardware,
         afterSnapshot: (@MainActor @Sendable (RecordingSnapshot) async -> Void)? = nil) {
        self.owner = owner
        self.hardware = hardware
        self.afterSnapshot = afterSnapshot
    }

    func play(at location: MeetingPlaybackLocation) async -> PlaybackOwnershipResult {
        // Only a real observation and a deterministic test scheduling boundary.
        // There is deliberately no working guard/reservation/activation yet.
        let snapshot = await owner.snapshot()
        await afterSnapshot?(snapshot)
        return .notImplemented
    }

    func stop() -> PlaybackOwnershipResult { .notImplemented }

    func prepareForRecording() -> PlaybackRecordingAdmission { .notImplemented }
}
#endif
