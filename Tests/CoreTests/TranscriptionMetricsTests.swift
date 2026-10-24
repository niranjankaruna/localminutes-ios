import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesCore

private final class MetricsTestClock: MetricsMonotonicClock, Sendable {
    private let value = Atomic<UInt64>(1_000_000_000)
    func nowNanoseconds() -> UInt64 { value.load(ordering: .relaxed) }
    func advance(_ nanoseconds: UInt64) {
        value.store(nowNanoseconds() + nanoseconds, ordering: .relaxed)
    }
    func set(_ nanoseconds: UInt64) { value.store(nanoseconds, ordering: .relaxed) }
}

final class TranscriptionMetricsTests: XCTestCase {
    private let identity = MetricsBuildIdentity(sourceCommit: String(repeating: "a", count: 40),
        modelRevision: String(repeating: "b", count: 40), runtimeVersion: "1.13.8", buildNumber: 1)

    func testMonotonicProcessingAndPublicationFactsUseNanosecondsAndCorrectPositiveRTF() throws {
        let clock = MetricsTestClock()
        let metrics = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        XCTAssertNil(metrics.snapshot().realTimeFactor)
        try metrics.audioQueued(startSample: 0, frameCount: 1_600, queueDepth: 2)
        let started = clock.nowNanoseconds()
        clock.advance(25_000_000)
        try metrics.processed(startSample: 0, frameCount: 1_600, workStartedAtNanoseconds: started)
        clock.advance(5_000_000)
        try metrics.partialPublished(endSample: 1_600)
        clock.advance(5_000_000)
        try metrics.finalPublished(endSample: 1_600)
        try metrics.checkpoint()
        let result = metrics.snapshot()
        XCTAssertEqual(result.capturedSampleCount, 1_600)
        XCTAssertEqual(result.processedSampleCount, 1_600)
        XCTAssertEqual(result.processingWallNanoseconds, 25_000_000)
        XCTAssertEqual(result.realTimeFactor, 0.25, "25ms processing /100ms accepted audio, never the reciprocal")
        XCTAssertEqual(result.peakQueueDepth, 2)
        XCTAssertEqual(result.partialLatency.sampleCount, 1)
        XCTAssertEqual(result.partialLatency.p50Nanoseconds, 30_000_000)
        XCTAssertEqual(result.partialLatency.p95Nanoseconds, 30_000_000)
        XCTAssertEqual(result.finalLatency.maxNanoseconds, 35_000_000)
        XCTAssertEqual(result.checkpoints.last?.processedSampleCount, 1_600)
        XCTAssertThrowsError(try metrics.processed(startSample: 0, frameCount: 1_600,
            workStartedAtNanoseconds: clock.nowNanoseconds())) { error in
            XCTAssertEqual(error as? MetricsValidationError, .invalidSampleRange)
        }
        XCTAssertThrowsError(try metrics.audioQueued(startSample: 1_600, frameCount: -1, queueDepth: 0))
        XCTAssertEqual(metrics.snapshot(), result)
    }

    func testRecentLatencyAndCheckpointRingsAreBoundedWhileCumulativeCountersRemainExact() throws {
        let clock = MetricsTestClock()
        XCTAssertThrowsError(try TranscriptionMetricsRecorder(identity: identity, capacity: 0, clock: clock))
        XCTAssertThrowsError(try TranscriptionMetricsRecorder(identity: identity, capacity: 129, clock: clock))
        let metrics = try TranscriptionMetricsRecorder(identity: identity, capacity: 3, clock: clock)
        for index in 1...5 {
            let start = Int64((index - 1) * 1_600)
            try metrics.audioQueued(startSample: start, frameCount: 1_600, queueDepth: index)
            let began = clock.nowNanoseconds()
            clock.advance(UInt64(index) * 1_000_000)
            try metrics.processed(startSample: start, frameCount: 1_600, workStartedAtNanoseconds: began)
            try metrics.partialPublished(endSample: start + 1_600)
            try metrics.finalPublished(endSample: start + 1_600)
            try metrics.checkpoint()
        }
        let result = metrics.snapshot()
        XCTAssertEqual(result.capturedSampleCount, 8_000)
        XCTAssertEqual(result.processedSampleCount, 8_000)
        XCTAssertEqual(result.processingWallNanoseconds, 15_000_000)
        XCTAssertEqual(result.peakQueueDepth, 5)
        XCTAssertEqual(result.checkpoints.count, 3)
        XCTAssertEqual(result.checkpoints.map(\.processedSampleCount), [4_800, 6_400, 8_000])
        XCTAssertEqual(result.partialLatency.sampleCount, 3)
        XCTAssertEqual(result.partialLatency.p50Nanoseconds, 4_000_000)
        XCTAssertEqual(result.partialLatency.p95Nanoseconds, 5_000_000)
        XCTAssertEqual(result.finalLatency.maxNanoseconds, 5_000_000)
        XCTAssertEqual(metrics.snapshot(), result, "Inspection cannot consume or reset evidence")
    }

    func testForegroundBackgroundCheckpointsPreserveActualProgressAndRejectClockReversal() throws {
        let clock = MetricsTestClock()
        let metrics = try TranscriptionMetricsRecorder(identity: identity, capacity: 8, clock: clock)
        for index in 0..<2 {
            try metrics.visibilityChanged(index == 0 ? .foreground : .background)
            try metrics.audioQueued(startSample: Int64(index * 1_600), frameCount: 1_600, queueDepth: 1)
            let began = clock.nowNanoseconds()
            clock.advance(10_000_000)
            try metrics.processed(startSample: Int64(index * 1_600), frameCount: 1_600,
                                  workStartedAtNanoseconds: began)
            try metrics.checkpoint()
        }
        clock.advance(1_000_000)
        try metrics.visibilityChanged(.foreground)
        try metrics.checkpoint()
        let result = metrics.snapshot()
        XCTAssertEqual(result.checkpoints.map(\.visibility), [.foreground, .background, .foreground])
        XCTAssertEqual(result.checkpoints.map(\.processedSampleCount), [1_600, 3_200, 3_200])
        let times = result.checkpoints.map(\.monotonicNanoseconds)
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(Set(times).count, 3)
        clock.set(clock.nowNanoseconds() - 1)
        XCTAssertThrowsError(try metrics.checkpoint()) { error in
            XCTAssertEqual(error as? MetricsValidationError, .nonMonotonicTime)
        }
        XCTAssertEqual(metrics.snapshot(), result, "A bad clock cannot rewrite already accepted checkpoints")
    }

    func testDiagnosticsRoundTripKeepsOnlyPinsCountersAndEnumsAndRejectsPrivateFields() throws {
        let clock = MetricsTestClock()
        let metrics = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        metrics.recordError(.queueOverflow)
        try metrics.checkpoint()
        let snapshot = metrics.snapshot()
        let data: Data
        do { data = try MetricsExportCodec.encode(snapshot) }
        catch { XCTFail("Typed privacy-safe export must produce actual JSON: \(type(of: error))"); return }
        XCTAssertLessThanOrEqual(data.count, 65_536)
        let restored = try MetricsExportCodec.decodeValidated(data)
        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.identity, identity)
        XCTAssertEqual(restored.errors.map(\.category), [.queueOverflow])
        XCTAssertEqual(restored.errors.map(\.count), [1])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in [("transcript", "Original synthetic private words"),
                             ("audio", "c3ludGhldGlj"), ("privatePath", "/private/fixture/recording.caf"),
                             ("credentials", "synthetic-not-a-secret"), ("deviceLocked", "true")] {
            var injected = object
            injected[key] = value
            let bytes = try JSONSerialization.data(withJSONObject: injected, options: [.sortedKeys])
            XCTAssertThrowsError(try MetricsExportCodec.decodeValidated(bytes)) { error in
                XCTAssertEqual(error as? MetricsValidationError, .restrictedPayload)
            }
            var nested = object
            var nestedIdentity = try XCTUnwrap(object["identity"] as? [String: Any])
            nestedIdentity[key] = value
            nested["identity"] = nestedIdentity
            let nestedBytes = try JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
            XCTAssertThrowsError(try MetricsExportCodec.decodeValidated(nestedBytes)) { error in
                XCTAssertEqual(error as? MetricsValidationError, .restrictedPayload)
            }
        }
        let invalidIdentity = MetricsBuildIdentity(sourceCommit: "/private/fixture", modelRevision: identity.modelRevision,
                                                   runtimeVersion: "synthetic-password", buildNumber: 1)
        let invalid = TranscriptionMetricsSnapshot(schemaVersion: snapshot.schemaVersion, identity: invalidIdentity,
            capturedSampleCount: snapshot.capturedSampleCount, processedSampleCount: snapshot.processedSampleCount,
            processingWallNanoseconds: snapshot.processingWallNanoseconds, realTimeFactor: snapshot.realTimeFactor,
            peakQueueDepth: snapshot.peakQueueDepth, partialLatency: snapshot.partialLatency,
            finalLatency: snapshot.finalLatency, checkpoints: snapshot.checkpoints, errors: snapshot.errors)
        XCTAssertThrowsError(try MetricsExportCodec.encode(invalid)) { error in
            XCTAssertEqual(error as? MetricsValidationError, .invalidIdentity)
        }
        XCTAssertThrowsError(try MetricsExportCodec.decodeValidated(Data(repeating: 0x20, count: 65_537))) { error in
            XCTAssertEqual(error as? MetricsValidationError, .oversizedExport)
        }
    }

    func testSelectedSpeechEpochUpdatesModelRuntimePinsAndClearsPriorMeetingEvidence() throws {
        let clock = MetricsTestClock()
        let metrics = try TranscriptionMetricsRecorder(identity: identity, capacity: 4, clock: clock)
        try metrics.visibilityChanged(.background)
        try metrics.audioQueued(startSample: 0, frameCount: 1_600, queueDepth: 3)
        let oldStarted = clock.nowNanoseconds()
        clock.advance(25_000_000)
        try metrics.processed(startSample: 0, frameCount: 1_600, workStartedAtNanoseconds: oldStarted)
        try metrics.partialPublished(endSample: 1_600)
        try metrics.finalPublished(endSample: 1_600)
        metrics.recordError(.queueOverflow)
        try metrics.checkpoint()
        let first = metrics.snapshot()
        XCTAssertEqual(first.identity, identity)
        XCTAssertEqual(first.processedSampleCount, 1_600)
        XCTAssertFalse(first.errors.isEmpty)

        let selectedRevision = "5359861c739e955e79d9a303bcbc70fb988958b1"
        let selectedIdentity = MetricsBuildIdentity(sourceCommit: identity.sourceCommit,
            modelRevision: selectedRevision, runtimeVersion: "1.7.5", buildNumber: identity.buildNumber)
        metrics.beginEpoch(modelRevision: selectedRevision, runtimeVersion: "1.7.5")
        let fresh = metrics.snapshot()
        XCTAssertEqual(fresh.identity, selectedIdentity,
            "A Whisper meeting must never be exported with its predecessor's Zipformer model/runtime pins")
        XCTAssertEqual(fresh.identity.sourceCommit, identity.sourceCommit)
        XCTAssertEqual(fresh.identity.buildNumber, identity.buildNumber)
        XCTAssertEqual(fresh.capturedSampleCount, 0); XCTAssertEqual(fresh.processedSampleCount, 0)
        XCTAssertEqual(fresh.processingWallNanoseconds, 0); XCTAssertNil(fresh.realTimeFactor)
        XCTAssertEqual(fresh.peakQueueDepth, 0)
        XCTAssertEqual(fresh.partialLatency.sampleCount, 0); XCTAssertEqual(fresh.finalLatency.sampleCount, 0)
        XCTAssertTrue(fresh.checkpoints.isEmpty); XCTAssertTrue(fresh.errors.isEmpty)
        XCTAssertThrowsError(try metrics.finalPublished(endSample: 1_600)) { error in
            XCTAssertEqual(error as? MetricsValidationError, .invalidSampleRange)
        }
        XCTAssertEqual(metrics.snapshot(), fresh, "Old completed input provenance must not satisfy a new epoch's publication")
        clock.advance(1_000)
        try metrics.checkpoint()
        XCTAssertEqual(metrics.snapshot().checkpoints.last?.visibility, .background)
        try metrics.audioQueued(startSample: 0, frameCount: 3_200, queueDepth: 1)
        let newStarted = clock.nowNanoseconds()
        clock.advance(10_000_000)
        try metrics.processed(startSample: 0, frameCount: 3_200, workStartedAtNanoseconds: newStarted)
        try metrics.finalPublished(endSample: 3_200)
        let second = metrics.snapshot()
        XCTAssertEqual(second.identity, selectedIdentity)
        XCTAssertEqual(second.capturedSampleCount, 3_200); XCTAssertEqual(second.processedSampleCount, 3_200)
        XCTAssertEqual(second.processingWallNanoseconds, 10_000_000)
        XCTAssertEqual(second.realTimeFactor, 0.05)
        XCTAssertEqual(second.finalLatency.sampleCount, 1)
        XCTAssertTrue(second.errors.isEmpty)
        XCTAssertEqual(try MetricsExportCodec.decodeValidated(MetricsExportCodec.encode(second)), second)
        XCTAssertEqual(first.identity, identity, "Already exported value snapshots retain their original model provenance")
        XCTAssertEqual(first.processingWallNanoseconds, 25_000_000)
    }

    func testLegacyEpochResetRetainsLatestSelectedPinsVisibilityAndMonotonicClockBoundary() throws {
        let clock = MetricsTestClock()
        let metrics = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        let selectedRevision = String(repeating: "e", count: 40)
        let selectedIdentity = MetricsBuildIdentity(sourceCommit: identity.sourceCommit,
            modelRevision: selectedRevision, runtimeVersion: "1.7.5", buildNumber: identity.buildNumber)
        try metrics.visibilityChanged(.foreground)
        metrics.beginEpoch(modelRevision: selectedRevision, runtimeVersion: "1.7.5")
        try metrics.audioQueued(startSample: 0, frameCount: 1_600, queueDepth: 1)
        let began = clock.nowNanoseconds()
        clock.advance(1_000_000)
        try metrics.processed(startSample: 0, frameCount: 1_600, workStartedAtNanoseconds: began)
        try metrics.checkpoint()
        XCTAssertEqual(metrics.snapshot().identity, selectedIdentity)
        metrics.beginEpoch()
        let reset = metrics.snapshot()
        XCTAssertEqual(reset.identity, selectedIdentity, "The existing no-argument API must keep the latest equipped model")
        XCTAssertEqual(reset.capturedSampleCount, 0); XCTAssertEqual(reset.processingWallNanoseconds, 0)
        XCTAssertTrue(reset.checkpoints.isEmpty)
        try metrics.checkpoint()
        XCTAssertEqual(metrics.snapshot().checkpoints.last?.visibility, .foreground)
        metrics.beginEpoch(modelRevision: identity.modelRevision, runtimeVersion: identity.runtimeVersion)
        let restored = metrics.snapshot()
        XCTAssertEqual(restored.identity, identity)
        XCTAssertEqual(restored.processedSampleCount, 0)
        clock.set(clock.nowNanoseconds() - 1)
        XCTAssertThrowsError(try metrics.checkpoint()) { error in
            XCTAssertEqual(error as? MetricsValidationError, .nonMonotonicTime)
        }
        XCTAssertEqual(metrics.snapshot(), restored, "Changing model provenance must not reset the accepted monotonic clock boundary")
    }

    func testDiagnosticCodecAcceptsReviewedEngineVersionPinsAndRejectsPrivateOrMalformedLabels() throws {
        for version in ["sherpa-onnx-1.13.8", "whisper.cpp-1.7.5", "llama.cpp-b5046"] {
            let expected = MetricsBuildIdentity(sourceCommit: identity.sourceCommit,
                modelRevision: identity.modelRevision, runtimeVersion: version, buildNumber: identity.buildNumber)
            let metrics = try TranscriptionMetricsRecorder(identity: expected, clock: MetricsTestClock())
            try metrics.checkpoint()
            let snapshot = metrics.snapshot()
            do {
                let bytes = try MetricsExportCodec.encode(snapshot)
                let restored = try MetricsExportCodec.decodeValidated(bytes)
                XCTAssertEqual(restored, snapshot)
                XCTAssertEqual(restored.identity.runtimeVersion, version,
                    "Retain the exact engine pin, rather than silently rewriting it into an unrelated numeric identity")
            } catch {
                XCTFail("Reviewed engine runtime pin must survive private diagnostics export: \(version)")
            }
        }
        for version in ["sherpa-onnx-", "sherpa-onnx-1..13", "sherpa-onnx-1.13.8/private",
                        "sherpa-onnx-1.13.8 secret", "whisper.cpp-v1.7.5", "whisper.cpp-1.7.5/token",
                        "llama.cpp-b", "llama.cpp-b5046-secret", "synthetic-password",
                        "/private/fixture/runtime", String(repeating: "1", count: 33)] {
            let restricted = MetricsBuildIdentity(sourceCommit: identity.sourceCommit,
                modelRevision: identity.modelRevision, runtimeVersion: version, buildNumber: identity.buildNumber)
            let metrics = try TranscriptionMetricsRecorder(identity: restricted, clock: MetricsTestClock())
            XCTAssertThrowsError(try MetricsExportCodec.encode(metrics.snapshot())) { error in
                XCTAssertEqual(error as? MetricsValidationError, .invalidIdentity)
            }
        }
    }
}
