import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesCore

final class ParakeetMetricsIdentityTests: XCTestCase {
    private let identity = MetricsBuildIdentity(sourceCommit: String(repeating: "a", count: 40),
        modelRevision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        runtimeVersion: "coreml-parakeet-tdt-v2-fluid-c79c4106", buildNumber: 3)

    func testExactNativeTDTIdentityAndMeasuredCountersRoundTripWithoutInventedComputeClaims() throws {
        let clock = ParakeetIdentityClock()
        let recorder = try TranscriptionMetricsRecorder(identity: identity, clock: clock)
        try recorder.audioQueued(startSample: 0, frameCount: 1_600, queueDepth: 1)
        let started = clock.nowNanoseconds()
        clock.advance(2_000_000)
        try recorder.processed(startSample: 0, frameCount: 1_600, workStartedAtNanoseconds: started)
        try recorder.checkpoint()
        let measured = recorder.snapshot()
        XCTAssertEqual(measured.identity, identity)
        XCTAssertEqual(measured.capturedSampleCount, 1_600)
        XCTAssertEqual(measured.processedSampleCount, 1_600)
        XCTAssertEqual(measured.processingWallNanoseconds, 2_000_000)
        let encoded = try MetricsExportCodec.encode(measured)
        XCTAssertEqual(try MetricsExportCodec.decodeValidated(encoded), measured)
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        // The current metrics schema does not measure actual Core ML device
        // placement. A runtime tag alone must never assert CPU/ANE/GPU usage.
        XCTAssertNil(fields["computeProvider"])
        XCTAssertNil(fields["gpuEnabled"])
        XCTAssertNil(fields["neuralEngineUsed"])
    }

    func testNativeRuntimeIdentityCannotAuthorizeUnmeasuredGPUOrPrivatePayloadFields() throws {
        let recorder = try TranscriptionMetricsRecorder(identity: identity, clock: ParakeetIdentityClock())
        let encoded = try MetricsExportCodec.encode(recorder.snapshot())
        let base = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (name, value) in [("computeProvider", "cpuAndGPU"), ("modelPath", "/private/model.mlmodelc"),
                              ("transcript", "private speech")] {
            var injected = base; injected[name] = value
            let bytes = try JSONSerialization.data(withJSONObject: injected)
            XCTAssertThrowsError(try MetricsExportCodec.decodeValidated(bytes)) { error in
                XCTAssertEqual(error as? MetricsValidationError, .restrictedPayload)
            }
        }
    }
}

private final class ParakeetIdentityClock: MetricsMonotonicClock, Sendable {
    private let time = Atomic<UInt64>(1_000_000_000)
    func nowNanoseconds() -> UInt64 { time.load(ordering: .relaxed) }
    func advance(_ delta: UInt64) { time.store(nowNanoseconds() + delta, ordering: .relaxed) }
}
