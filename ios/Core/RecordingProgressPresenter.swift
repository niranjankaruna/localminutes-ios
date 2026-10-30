import Foundation

public enum RecordingProgressStatus: Equatable, Sendable {
    case unknown, caughtUp, processing, lagging
}

public struct RecordingProgress: Equatable, Sendable {
    public let elapsedSeconds: Int64?
    public let backlogSeconds: Double?
    public let status: RecordingProgressStatus
}

/// Pure display input boundary. The retained metrics recorder supplies the
/// actual first accepted PCM uptime; neither a view's lifetime nor recognized
/// sample count establishes elapsed capture time. Missing observations stay nil.
public enum RecordingProgressPresenter {
    public static func make(recording: RecordingSnapshot,
                            firstAudioQueuedAtNanoseconds: UInt64?, observedAtNanoseconds: UInt64,
                            metrics: TranscriptionMetricsSnapshot?) -> RecordingProgress {
        let unknown = RecordingProgress(elapsedSeconds: nil, backlogSeconds: nil, status: .unknown)
        // End/cancellation times are not measured by this input boundary. Do
        // not let a previous meeting's counters extend a preparing/finished UI.
        guard recording.phase == .recording, recording.sessionID != nil,
              let origin = firstAudioQueuedAtNanoseconds, observedAtNanoseconds >= origin else { return unknown }
        if let metrics {
            guard metrics.schemaVersion == 1, metrics.capturedSampleCount >= 0,
                  metrics.processedSampleCount >= 0,
                  metrics.processedSampleCount <= metrics.capturedSampleCount else { return unknown }
        }
        guard let elapsed = Int64(exactly: (observedAtNanoseconds - origin) / 1_000_000_000) else { return unknown }
        guard let metrics, metrics.capturedSampleCount > 0 else {
            return .init(elapsedSeconds: elapsed, backlogSeconds: nil, status: .unknown)
        }
        let (pending, overflow) = metrics.capturedSampleCount.subtractingReportingOverflow(metrics.processedSampleCount)
        guard !overflow, pending >= 0 else { return unknown }
        let seconds = Double(pending) / 16_000
        guard seconds.isFinite else { return unknown }
        let status: RecordingProgressStatus = pending == 0 ? .caughtUp : (seconds > 5 ? .lagging : .processing)
        return .init(elapsedSeconds: elapsed, backlogSeconds: seconds, status: status)
    }
}
