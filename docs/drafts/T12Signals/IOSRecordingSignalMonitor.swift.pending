#if os(iOS)
import AVFoundation
import Foundation

/// Future application-held native notification boundary. No observer, task,
/// interruption delivery or resource cleanup exists before actual native RED.
@MainActor
final class IOSRecordingSignalMonitor {
    init(owner: RecordingSessionOwner, center: NotificationCenter = .default) {}
    func beginEpoch(sessionID: UUID) {}
    func endEpoch(sessionID: UUID) {}
    /// Deterministic join for already-admitted native notifications, not a
    /// fabricated acknowledgement of microphone/Activity/device success.
    func flush() async {}
}
#endif
