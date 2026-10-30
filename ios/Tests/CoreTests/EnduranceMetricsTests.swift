import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesCore

private final class EnduranceTestClock: MetricsMonotonicClock, Sendable {
    private let tick = Atomic<UInt64>(1_000_000_000)
    func nowNanoseconds() -> UInt64 { tick.load(ordering: .relaxed) }
    func advance(_ amount: UInt64) { tick.store(nowNanoseconds() + amount, ordering: .relaxed) }
    func set(_ value: UInt64) { tick.store(value, ordering: .relaxed) }
}

final class EnduranceMetricsTests: XCTestCase {
    private let identity = MetricsBuildIdentity(sourceCommit: String(repeating: "a", count: 40),
        modelRevision: String(repeating: "b", count: 40), runtimeVersion: "coreml-parakeet-tdt-v2-fluid-c79c4106", buildNumber: 7)
    private let ordinary = EnduranceSystemFacts(residentMemoryBytes: 100_000_000,
        thermal: .nominal, batteryLevelPercent: 80, batteryState: .unplugged,
        route: .builtInMicrophone, visibility: .foreground)

    func testRollingSixtySecondRTFUsesRecentActualCounterDeltasRatherThanCumulativeAverage() throws {
        let clock = EnduranceTestClock()
        let source = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        let recorder = try EnduranceMetricsRecorder(transcription: source, clock: clock)
        XCTAssertNil(recorder.snapshot().rollingRealTimeFactor)
        try recorder.sample(ordinary)
        for index in 0..<15 {
            try processOneSecond(source, clock: clock, work: 2_000_000_000); try recorder.sample(ordinary)
            if index == 0 {
                XCTAssertNil(recorder.snapshot().rollingRealTimeFactor, "Four seconds is insufficient for a60s rolling rate")
                XCTAssertEqual(recorder.snapshot().rollingCoverageNanoseconds, 4_000_000_000)
            }
        }
        let slow = recorder.snapshot()
        XCTAssertEqual(try XCTUnwrap(slow.rollingRealTimeFactor), 2, accuracy: 1e-9)
        XCTAssertEqual(slow.rollingCoverageNanoseconds, 60_000_000_000)
        for _ in 0..<15 { try processOneSecond(source, clock: clock, work: 250_000_000); try recorder.sample(ordinary) }
        let changed = recorder.snapshot()
        XCTAssertEqual(changed.transcription, source.snapshot())
        XCTAssertEqual(changed.transcription.identity, identity)
        XCTAssertEqual(try XCTUnwrap(changed.transcription.realTimeFactor), 1.125, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(changed.rollingRealTimeFactor), 0.25, accuracy: 1e-9)
        XCTAssertEqual(changed.rollingWindowNanoseconds, 60_000_000_000)
        XCTAssertEqual(changed.rollingCoverageNanoseconds, 60_000_000_000)
        XCTAssertLessThan(try XCTUnwrap(changed.rollingRealTimeFactor), 1)
        XCTAssertGreaterThan(try XCTUnwrap(changed.transcription.realTimeFactor), 1)
    }

    func testCurrentRecentP95AndLifetimeSampledPeakBacklogAreCorrectAndBounded() throws {
        let clock = EnduranceTestClock()
        let source = try TranscriptionMetricsRecorder(identity: identity, capacity: 2, clock: clock)
        XCTAssertThrowsError(try EnduranceMetricsRecorder(transcription: source, clock: clock, capacity: 0))
        XCTAssertThrowsError(try EnduranceMetricsRecorder(transcription: source, clock: clock, capacity: 129))
        let recorder = try EnduranceMetricsRecorder(transcription: source, clock: clock, capacity: 4)
        var captured: Int64 = 0
        var processed: Int64 = 0
        for seconds in [10, 1, 2, 3, 4, 2] {
            let wanted = Int64(seconds) * 16_000
            while captured - processed < wanted {
                try source.audioQueued(startSample: captured, frameCount: 16_000, queueDepth: Int((captured - processed) / 16_000) + 1)
                captured += 16_000
            }
            while captured - processed > wanted {
                let began = clock.nowNanoseconds(); clock.advance(1_000_000)
                try source.processed(startSample: processed, frameCount: 16_000, workStartedAtNanoseconds: began)
                processed += 16_000
            }
            clock.advance(1_000_000_000)
            try recorder.sample(ordinary)
        }
        let result = recorder.snapshot()
        XCTAssertEqual(result.currentSampledBacklogSeconds, 2)
        XCTAssertEqual(result.recentP95SampledBacklogSeconds, 4,
            "Nearest-rank p95 covers only the recent four sampled values [2,3,4,2]")
        XCTAssertEqual(result.peakSampledBacklogSeconds, 10,
            "The lifetime sampled peak survives eviction from the recent buffer")
        XCTAssertEqual(result.totalSampleCount, 6)
        XCTAssertEqual(result.recentBacklogSampleCount, 4)
        XCTAssertEqual(result.backlogSampleCapacity, 4)
        XCTAssertEqual(result.samples.count, 4)
        XCTAssertEqual(result.samples.map(\.backlogSeconds), [2, 3, 4, 2])
        XCTAssertEqual(result.wholeMeetingP95SampledBacklogUpperBoundSeconds, 16,
            "Whole-meeting p95 includes the evicted10s observation; the explicit histogram bucket upper bound is16s")
        XCTAssertLessThanOrEqual(result.backlogHistogram.count, 64)
        XCTAssertEqual(result.backlogHistogram.reduce(UInt64(0)) { $0 + $1.sampleCount }, 6)
        XCTAssertEqual(source.firstAudioQueuedAtNanoseconds, 1_000_000_000,
            "First PCM provenance must survive eviction from the source recorder's completed-input ring")
    }

    func testMemoryFactsRetainThirtyToOneTwentyMinuteTrendAfterRingEvictionWithoutInventingMissingTargets() throws {
        let clock = EnduranceTestClock()
        let origin = clock.nowNanoseconds()
        let source = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        let recorder = try EnduranceMetricsRecorder(transcription: source, clock: clock, capacity: 2)
        try recorder.sample(.init())
        XCTAssertNil(recorder.snapshot().epochOriginNanoseconds)
        XCTAssertNil(recorder.snapshot().samples.last?.elapsedNanoseconds)
        XCTAssertNil(recorder.snapshot().currentResidentMemoryBytes)
        XCTAssertNil(recorder.snapshot().memoryGrowth30To120Bytes)
        try source.audioQueued(startSample: 0, frameCount: 16_000, queueDepth: 1)
        try source.processed(startSample: 0, frameCount: 16_000, workStartedAtNanoseconds: origin)
        clock.advance(1_800_000_000_000)
        try recorder.sample(.init(residentMemoryBytes: 100_000_000))
        clock.advance(1_800_000_000_000)
        try recorder.sample(.init(residentMemoryBytes: 300_000_000))
        clock.advance(3_600_000_000_000)
        try recorder.sample(.init(residentMemoryBytes: 110_000_000))
        let result = recorder.snapshot()
        XCTAssertEqual(result.epochOriginNanoseconds, origin)
        XCTAssertEqual(result.currentResidentMemoryBytes, 110_000_000)
        XCTAssertEqual(result.peakResidentMemoryBytes, 300_000_000)
        XCTAssertEqual(result.memoryAtMinute30?.residentMemoryBytes, 100_000_000)
        XCTAssertEqual(result.memoryAtMinute30?.monotonicNanoseconds, origin + 1_800_000_000_000)
        XCTAssertEqual(result.memoryAtMinute120?.residentMemoryBytes, 110_000_000)
        XCTAssertEqual(result.memoryAtMinute120?.elapsedNanoseconds, 7_200_000_000_000)
        XCTAssertEqual(result.memoryGrowth30To120Bytes, 10_000_000)
        XCTAssertEqual(result.samples.count, 2)

        let sparseClock = EnduranceTestClock()
        let sparseSource = try TranscriptionMetricsRecorder(identity: identity, clock: sparseClock)
        let sparse = try EnduranceMetricsRecorder(transcription: sparseSource, clock: sparseClock)
        try sparse.sample(.init())
        try sparseSource.audioQueued(startSample: 0, frameCount: 16_000, queueDepth: 1)
        try sparseSource.processed(startSample: 0, frameCount: 16_000, workStartedAtNanoseconds: sparseClock.nowNanoseconds())
        sparseClock.advance(7_200_000_000_000)
        try sparse.sample(.init(residentMemoryBytes: 110_000_000))
        XCTAssertNil(sparse.snapshot().memoryAtMinute30, "A120min observation must not fabricate the missed30min baseline")
        XCTAssertNil(sparse.snapshot().memoryGrowth30To120Bytes)
    }

    func testMonotonicSensorFactsPreserveUnknownAndEnumsAndRejectInvalidSamplesWithoutMutation() throws {
        let clock = EnduranceTestClock()
        let source = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        XCTAssertNil(source.firstAudioQueuedAtNanoseconds)
        XCTAssertThrowsError(try source.audioQueued(startSample: 1, frameCount: 16_000, queueDepth: 1))
        XCTAssertNil(source.firstAudioQueuedAtNanoseconds, "Rejected input must not establish recording origin")
        let firstPCM = clock.nowNanoseconds()
        try source.audioQueued(startSample: 0, frameCount: 16_000, queueDepth: 1)
        try source.processed(startSample: 0, frameCount: 16_000, workStartedAtNanoseconds: firstPCM)
        XCTAssertEqual(source.firstAudioQueuedAtNanoseconds, firstPCM)
        source.beginEpoch()
        XCTAssertNil(source.firstAudioQueuedAtNanoseconds, "A later meeting must not inherit the first meeting's origin")
        let recorder = try EnduranceMetricsRecorder(transcription: source, clock: clock)
        try recorder.sample(.init())
        clock.advance(1_000_000_000)
        let observed = EnduranceSystemFacts(residentMemoryBytes: 123_456_789, thermal: .serious,
            batteryLevelPercent: 75, batteryState: .charging, route: .bluetoothMicrophone, visibility: .background)
        try recorder.sample(observed)
        let before = recorder.snapshot()
        XCTAssertEqual(before.samples.first?.facts, EnduranceSystemFacts())
        XCTAssertEqual(before.samples.last?.facts, observed)
        XCTAssertEqual(before.samples.map(\.monotonicNanoseconds), before.samples.map(\.monotonicNanoseconds).sorted())
        for invalid in [EnduranceSystemFacts(residentMemoryBytes: 0), .init(residentMemoryBytes: -1),
                        .init(batteryLevelPercent: -1), .init(batteryLevelPercent: 101)] {
            XCTAssertThrowsError(try recorder.sample(invalid)) { XCTAssertEqual($0 as? EnduranceMetricsError, .invalidFacts) }
            XCTAssertEqual(recorder.snapshot(), before)
        }
        source.beginEpoch()
        recorder.beginEpoch()
        let reset = recorder.snapshot()
        XCTAssertEqual(reset.transcription.identity, identity)
        XCTAssertEqual(reset.totalSampleCount, 0)
        XCTAssertTrue(reset.samples.isEmpty)
        XCTAssertNil(reset.wholeMeetingP95SampledBacklogUpperBoundSeconds)
        XCTAssertNil(reset.peakResidentMemoryBytes)
        XCTAssertNil(reset.epochOriginNanoseconds)
        clock.set(clock.nowNanoseconds() - 1)
        XCTAssertThrowsError(try recorder.sample(ordinary)) { XCTAssertEqual($0 as? EnduranceMetricsError, .nonMonotonicTime) }
        XCTAssertEqual(recorder.snapshot(), reset)
    }

    func testBoundedDiagnosticEnvelopeRetainsExistingPinsAndRejectsPrivateFieldsAtEveryLevel() throws {
        let clock = EnduranceTestClock()
        let source = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        let recorder = try EnduranceMetricsRecorder(transcription: source, clock: clock)
        try recorder.sample(ordinary)
        let original = recorder.snapshot()
        let data = try EnduranceMetricsExportCodec.encode(original)
        XCTAssertLessThanOrEqual(data.count, 131_072)
        XCTAssertEqual(try EnduranceMetricsExportCodec.decodeValidated(data), original)
        XCTAssertEqual(original.transcription, source.snapshot())
        let encodedSource = try MetricsExportCodec.encode(original.transcription)
        XCTAssertEqual(try MetricsExportCodec.decodeValidated(encodedSource).identity, identity)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["transcript", "audio", "privatePath", "credentials", "deviceLocked", "routeName"] {
            var top = object; top[key] = "Original synthetic private marker"
            XCTAssertThrowsError(try EnduranceMetricsExportCodec.decodeValidated(JSONSerialization.data(withJSONObject: top))) {
                XCTAssertEqual($0 as? EnduranceMetricsError, .restrictedPayload)
            }
            var nested = object
            var samples = try XCTUnwrap(nested["samples"] as? [[String: Any]])
            var facts = try XCTUnwrap(samples[0]["facts"] as? [String: Any])
            facts[key] = "Original synthetic private marker"; samples[0]["facts"] = facts; nested["samples"] = samples
            XCTAssertThrowsError(try EnduranceMetricsExportCodec.decodeValidated(JSONSerialization.data(withJSONObject: nested))) {
                XCTAssertEqual($0 as? EnduranceMetricsError, .restrictedPayload)
            }
        }
        var nested = object
        var transcription = try XCTUnwrap(nested["transcription"] as? [String: Any])
        var identity = try XCTUnwrap(transcription["identity"] as? [String: Any])
        identity["accountAddress"] = "synthetic-not-an-account"; transcription["identity"] = identity; nested["transcription"] = transcription
        XCTAssertThrowsError(try EnduranceMetricsExportCodec.decodeValidated(JSONSerialization.data(withJSONObject: nested))) {
            XCTAssertEqual($0 as? EnduranceMetricsError, .restrictedPayload)
        }
        XCTAssertThrowsError(try EnduranceMetricsExportCodec.decodeValidated(Data(repeating: 0x20, count: 131_073))) {
            XCTAssertEqual($0 as? EnduranceMetricsError, .oversizedExport)
        }
    }

    private func processOneSecond(_ source: TranscriptionMetricsRecorder, clock: EnduranceTestClock,
                                  work: UInt64) throws {
        let start = source.snapshot().capturedSampleCount
        try source.audioQueued(startSample: start, frameCount: 16_000, queueDepth: 1)
        let began = clock.nowNanoseconds(); clock.advance(work)
        try source.processed(startSample: start, frameCount: 16_000, workStartedAtNanoseconds: began)
        clock.advance(4_000_000_000 - work)
    }
}
