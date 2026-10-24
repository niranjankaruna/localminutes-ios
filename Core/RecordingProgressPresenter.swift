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
    // TEST-FIRST interface only. No clock arithmetic or recognition status is
    // implemented until actual hosted assertions establish this slice's RED.
    public static func make(recording: RecordingSnapshot,
                            firstAudioQueuedAtNanoseconds: UInt64?, observedAtNanoseconds: UInt64,
                            metrics: TranscriptionMetricsSnapshot?) -> RecordingProgress {
        .init(elapsedSeconds: nil, backlogSeconds: nil, status: .unknown)
    }
}
