import AVFoundation
import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesRecording
import LocalMinutesModels
import LocalMinutesPersistence
#endif

public struct LiveTranscriptSnapshot: Equatable, Sendable {
    public let sessionID: UUID?
    public let partial: String
    public let finalized: [StoredTranscriptSegment]
    public let receivedSampleCount: Int64
    public let failure: RecordingFailure?

    public init(sessionID: UUID? = nil, partial: String = "",
                finalized: [StoredTranscriptSegment] = [], receivedSampleCount: Int64 = 0,
                failure: RecordingFailure? = nil) {
        self.sessionID = sessionID; self.partial = partial; self.finalized = finalized
        self.receivedSampleCount = receivedSampleCount; self.failure = failure
    }
}

private final class UnimplementedTranscriptSink: NormalizedCaptureSink {
    func offer(_ buffer: AVAudioPCMBuffer, sourceStartSample: Int64) -> Bool { false }
}

/// Test-first interface only. Readiness requires an actual leased native model.
@MainActor @Observable
public final class LiveTranscriptionSession: RecordingPreparationSource {
    public let normalizedSink: (any NormalizedCaptureSink)? = UnimplementedTranscriptSink()
    public private(set) var transcript = LiveTranscriptSnapshot()

    public init(models: ModelInstallationManager, store: SQLiteMeetingStore,
                meetingsDirectory: URL) {}

    public func prepare(sessionID: UUID) async -> RecordingPreparationResult { .rejected(.modelUnavailable) }
    public func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure? { nil }
}
