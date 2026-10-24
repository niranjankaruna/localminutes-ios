import Foundation
import XCTest
@testable import LocalMinutesCore

final class RecordingProgressPresenterTests: XCTestCase {
    func testFirstPCMElapsedSurvivesPresenterRecreationAndDoesNotUseTranscribedDuration() {
        let origin: UInt64 = 50_000_000_000
        let now = origin + 7_201_999_999_999
        let recording = state()
        let sampled = metrics(captured: 16_000, processed: 160)
        let first = RecordingProgressPresenter.make(recording: recording,
            firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: now, metrics: sampled)
        let recreated = RecordingProgressPresenter.make(recording: recording,
            firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: now, metrics: sampled)
        XCTAssertEqual(first.elapsedSeconds, 7_201, "Elapsed is actual accepted-audio uptime, not the160 processed samples")
        XCTAssertEqual(recreated, first, "View/presenter recreation cannot relatch a recording start")
        let later = RecordingProgressPresenter.make(recording: recording,
            firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: now + 1_000_000_000, metrics: sampled)
        XCTAssertEqual(later.elapsedSeconds, 7_202)
        XCTAssertEqual(later.backlogSeconds, first.backlogSeconds)
    }

    func testMeasuredBacklogWarnsStrictlyAboveFiveSecondsAndReportsRealCatchUp() {
        let cases: [(Int64, Int64, Double, RecordingProgressStatus)] = [
            (160_000, 80_000, 5, .processing),
            (160_001, 80_000, 5.0000625, .lagging),
            (320, 320, 0, .caughtUp)
        ]
        for (captured, processed, seconds, status) in cases {
            let result = RecordingProgressPresenter.make(recording: state(),
                firstAudioQueuedAtNanoseconds: 10_000_000_000, observedAtNanoseconds: 20_000_000_000,
                metrics: metrics(captured: captured, processed: processed))
            XCTAssertEqual(result.elapsedSeconds, 10)
            XCTAssertEqual(result.status, status)
            XCTAssertNotNil(result.backlogSeconds)
            if let measured = result.backlogSeconds { XCTAssertEqual(measured, seconds, accuracy: 0.0000001) }
        }
    }

    func testMissingAndNonmonotonicMeasurementsRemainUnknownInsteadOfInventingZero() {
        let sampled = metrics(captured: 320, processed: 160)
        for (origin, now) in [(nil as UInt64?, UInt64(20_000_000_000)),
                              (UInt64(30_000_000_000), UInt64(20_000_000_000)),
                              (UInt64.max, UInt64(0))] {
            let result = RecordingProgressPresenter.make(recording: state(),
                firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: now, metrics: sampled)
            XCTAssertNil(result.elapsedSeconds); XCTAssertNil(result.backlogSeconds)
            XCTAssertEqual(result.status, .unknown)
        }
        let noRecognitionMeasurement = RecordingProgressPresenter.make(recording: state(),
            firstAudioQueuedAtNanoseconds: 10_000_000_000, observedAtNanoseconds: 20_000_000_000, metrics: nil)
        XCTAssertEqual(noRecognitionMeasurement.elapsedSeconds, 10, "Known capture time does not invent ASR progress")
        XCTAssertNil(noRecognitionMeasurement.backlogSeconds)
        XCTAssertEqual(noRecognitionMeasurement.status, .unknown)
        let noAcceptedSamples = RecordingProgressPresenter.make(recording: state(),
            firstAudioQueuedAtNanoseconds: 10_000_000_000, observedAtNanoseconds: 20_000_000_000,
            metrics: metrics(captured: 0, processed: 0))
        XCTAssertNil(noAcceptedSamples.backlogSeconds)
        XCTAssertEqual(noAcceptedSamples.status, .unknown)
    }

    func testInvalidCountersInactiveAndReplacementEpochCannotReusePriorProgress() {
        for (captured, processed) in [(Int64(-1), Int64(0)), (320, -1), (320, 640),
                                      (Int64.max, Int64.min), (Int64.min, Int64.max)] {
            let result = RecordingProgressPresenter.make(recording: state(),
                firstAudioQueuedAtNanoseconds: 10_000_000_000, observedAtNanoseconds: 20_000_000_000,
                metrics: metrics(captured: captured, processed: processed))
            XCTAssertNil(result.elapsedSeconds); XCTAssertNil(result.backlogSeconds)
            XCTAssertEqual(result.status, .unknown, "Malformed subtraction must fail closed without integer overflow")
        }
        for phase in [RecordingPhase.idle, .preparing, .completed, .interrupted, .recoverableFailure, .failed] {
            let stale = RecordingProgressPresenter.make(recording: state(phase: phase),
                firstAudioQueuedAtNanoseconds: 10_000_000_000, observedAtNanoseconds: 20_000_000_000,
                metrics: metrics(captured: 160_000, processed: 0))
            XCTAssertNil(stale.elapsedSeconds); XCTAssertNil(stale.backlogSeconds)
            XCTAssertEqual(stale.status, .unknown)
        }
        let replacement = RecordingProgressPresenter.make(recording: state(id: UUID()),
            firstAudioQueuedAtNanoseconds: 100_000_000_000, observedAtNanoseconds: 101_000_000_000,
            metrics: metrics(captured: 320, processed: 0))
        XCTAssertEqual(replacement.elapsedSeconds, 1)
        XCTAssertEqual(replacement.backlogSeconds, 0.02)
        XCTAssertEqual(replacement.status, .processing)
    }

    private func state(phase: RecordingPhase = .recording, id: UUID = UUID()) -> RecordingSnapshot {
        .init(phase: phase, sessionID: id,
            readiness: .init(audioSessionActive: true, firstBufferAccepted: true, activityActive: true),
            failure: nil, cleanupPending: phase == .stopping)
    }
    private func metrics(captured: Int64, processed: Int64) -> TranscriptionMetricsSnapshot {
        let latency = MetricsLatencySummary(sampleCount: 0, p50Nanoseconds: nil, p95Nanoseconds: nil, maxNanoseconds: nil)
        return .init(schemaVersion: 1, identity: .init(sourceCommit: String(repeating: "a", count: 40),
            modelRevision: String(repeating: "b", count: 40), runtimeVersion: "whisper.cpp-1.7.5", buildNumber: 3),
            capturedSampleCount: captured, processedSampleCount: processed, processingWallNanoseconds: 0,
            realTimeFactor: nil, peakQueueDepth: 0, partialLatency: latency, finalLatency: latency,
            checkpoints: [], errors: [])
    }
}
