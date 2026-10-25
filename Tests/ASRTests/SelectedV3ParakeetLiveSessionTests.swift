import AVFoundation
import Dispatch
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
@testable import LocalMinutesTranscription

/// Native Core ML + Swift TDT decoder, real protected model installation, CAF
/// segments and SQLite. Synthetic scheduling is not a microphone/device test.
@MainActor
final class SelectedV3ParakeetLiveSessionTests: XCTestCase {
    func testEquippedV3PackPublishesDuringCaptureAndPersistsItsOwnManifest() async throws {
        let fixture = try ParakeetV3Fixture.load()
        let source = try XCTUnwrap(ProcessInfo.processInfo.environment["GITHUB_SHA"])
        let identity = MetricsBuildIdentity(sourceCommit: source,
            modelRevision: fixture.manifest.revision,
            runtimeVersion: fixture.manifest.runtimeVersion, buildNumber: 3)
        let metrics = try TranscriptionMetricsRecorder(identity: identity,
            clock: SelectedV3ParakeetMetricsClock())
        let root = try CoreMLParakeetFixture.temporaryRoot("v3-live")
        let manifest = fixture.manifest
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
        let database = root.appendingPathComponent("meetings.sqlite")
        let store = try SQLiteMeetingStore(databaseURL: database)
        let session = LiveTranscriptionSession(models: models, store: store,
            meetingsDirectory: root.appendingPathComponent("Meetings"), metrics: metrics,
            selectedSpeechModel: { manifest })
        let id = UUID()
        var capture: AudioCaptureManifest?
        do {
            // Only this equipped Core ML family is installed. There is no
            // Zipformer/Whisper fallback available to fabricate readiness.
            let installed = try await models.importDirectory(fixture.directory, manifest: manifest)
            let manifests = try await models.installedManifests()
            XCTAssertEqual(manifests, [manifest])
            let prepared = await session.prepare(sessionID: id)
            XCTAssertTrue({ if case .ready = prepared { true } else { false } }(),
                "The equipped native TDT model must prepare without loading another speech engine")
            guard case .ready(let directory) = prepared else {
                let history = try await store.history()
                XCTAssertTrue(history.isEmpty)
                try await store.close(); try CoreMLParakeetFixture.remove(root, suffix: "v3-live")
                return
            }
            let loadedPin = try await store.speechModelPin(meetingID: id)
            let pin = try XCTUnwrap(loadedPin)
            XCTAssertEqual(pin.selection.manifest, manifest)
            XCTAssertEqual(pin.selection.installationID, installed.installationID)
            XCTAssertEqual(pin.selection.profile.rawValue, "parakeetTDTCoreML")
            do { try await models.remove(modelID: manifest.modelID); XCTFail("Native model lease was released while capture still needs it") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }

            let firstWindow = fixture.samples + Array(repeating: Float(0), count: 80_000 - fixture.samples.count)
            let samples = firstWindow + fixture.samples
            let sink = try XCTUnwrap(session.normalizedSink)
            let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 32_000)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            for start in stride(from: 0, to: samples.count, by: 1_600) {
                let count = min(1_600, samples.count - start)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                pcm.frameLength = AVAudioFrameCount(count)
                let plane = try XCTUnwrap(pcm.floatChannelData?.pointee)
                for index in 0..<count { plane[index] = samples[start + index] }
                try writer.append(pcm)
                XCTAssertTrue(sink.offer(pcm, sourceStartSample: Int64(start)))
            }
            let captured = try writer.finish(); capture = captured
            XCTAssertEqual(captured.totalFrames, Int64(samples.count))
            XCTAssertGreaterThan(captured.segments.count, 1)
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while session.transcript.partial.isEmpty && session.transcript.finalized.isEmpty && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(!session.transcript.partial.isEmpty || !session.transcript.finalized.isEmpty,
                          "Native chunked speech must be visible before Stop; a final-only transcription is insufficient")
            let failure = await session.finish(sessionID: id, manifest: captured)
            XCTAssertNil(failure)
            XCTAssertEqual(session.transcript.receivedSampleCount, Int64(samples.count))
            XCTAssertEqual(session.transcript.partial, "")
            let measured = metrics.snapshot()
            XCTAssertEqual(measured.identity, identity)
            XCTAssertEqual(measured.capturedSampleCount, Int64(samples.count))
            XCTAssertEqual(measured.processedSampleCount, Int64(samples.count))
            XCTAssertGreaterThan(measured.processingWallNanoseconds, 0)
            XCTAssertEqual(try MetricsExportCodec.decodeValidated(MetricsExportCodec.encode(measured)), measured)
            let rows = try await store.transcript(meetingID: id)
            XCTAssertEqual(rows, session.transcript.finalized)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertEqual(rows.map(\.sequence), Array(0..<rows.count))
            XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
            XCTAssertTrue(rows.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            var previousEnd: Int64 = 0
            for row in rows {
                XCTAssertEqual(row.meetingID, id); XCTAssertEqual(row.modelRevision, manifest.revision)
                XCTAssertGreaterThanOrEqual(row.startSample, previousEnd)
                XCTAssertGreaterThan(row.endSample, row.startSample)
                XCTAssertLessThanOrEqual(row.endSample, Int64(samples.count))
                previousEnd = row.endSample
            }
            let repeated = await session.finish(sessionID: id, manifest: captured)
            XCTAssertNil(repeated)
            let unchanged = try await store.transcript(meetingID: id)
            XCTAssertEqual(unchanged, rows)
            let meeting = try await store.meeting(id: id)
            XCTAssertEqual(meeting?.recordingState, .completed)
            XCTAssertEqual(meeting?.capturedSampleCount, Int64(samples.count))
            try await models.remove(modelID: manifest.modelID)
            let removed = try await models.current(modelID: manifest.modelID)
            XCTAssertNil(removed)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            let durable = try await reopened.transcript(meetingID: id)
            let durablePin = try await reopened.speechModelPin(meetingID: id)
            XCTAssertEqual(durable, rows); XCTAssertEqual(durablePin, pin)
            try await reopened.close(); try CoreMLParakeetFixture.remove(root, suffix: "v3-live")
        } catch {
            _ = await session.finish(sessionID: id, manifest: capture)
            try? await store.close(); try? CoreMLParakeetFixture.remove(root, suffix: "v3-live")
            throw error
        }
    }
}

private struct SelectedV3ParakeetMetricsClock: MetricsMonotonicClock {
    func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}
