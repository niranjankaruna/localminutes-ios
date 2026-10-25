import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
@testable import LocalMinutesTranscription

@MainActor
final class V3ParakeetReplayIntegrationTests: XCTestCase {
    func testDurableCAFReplaysCapturedV3PackPreservingItsPinAndOriginals() async throws {
        let fixture = try ParakeetV3Fixture.load()
        let root = try CoreMLParakeetFixture.temporaryRoot("v3-replay")
        let database = root.appendingPathComponent("meetings.sqlite")
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
        let initial = try SQLiteMeetingStore(databaseURL: database)
        var reopened: SQLiteMeetingStore?
        do {
            let installed = try await models.importDirectory(fixture.directory, manifest: fixture.manifest)
            let manifests = try await models.installedManifests()
            XCTAssertEqual(manifests, [fixture.manifest], "No alternative speech engine is installed")
            let id = UUID()
            let recordings = root.appendingPathComponent("Meetings")
            let directory = recordings.appendingPathComponent(id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await initial.createMeeting(.init(id: id, title: "Native replay fixture",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recovered))
            let pin = StoredMeetingSpeechModelPin(meetingID: id, selection: .init(
                manifest: installed.manifest, profile: .parakeetTDTCoreML, installationID: installed.installationID))
            try await initial.saveSpeechModelPin(pin)
            let prefix: Int64 = 16_000
            let samples = Array(repeating: Float(0), count: Int(prefix)) + fixture.samples
                + Array(repeating: Float(0), count: 32_000)
            let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 16_000)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            for offset in stride(from: 0, to: samples.count, by: 3_200) {
                let count = min(3_200, samples.count - offset)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                pcm.frameLength = AVAudioFrameCount(count)
                let plane = try XCTUnwrap(pcm.floatChannelData?.pointee)
                for index in 0..<count { plane[index] = samples[offset + index] }
                try writer.append(pcm)
            }
            let audio = try writer.finish()
            XCTAssertEqual(audio.totalFrames, Int64(samples.count))
            let original = StoredTranscriptSegment(id: UUID(), meetingID: id, sequence: 0,
                startSample: 0, endSample: prefix, text: "Original synthetic prefix, never new ASR output.",
                modelRevision: "original-prefix")
            let note = StoredManualNote(meetingID: id, text: "Original owner note — Café.", editRevision: 3,
                                        modifiedAt: Date(timeIntervalSince1970: 2_000))
            try await initial.appendFinalizedSegments([original], to: id)
            try await initial.saveManualNote(note)
            try await initial.updateRecordingState(id: id, state: .recovered, capturedSampleCount: audio.totalFrames)
            let originals = try sourceDigests(directory)
            try await initial.close()
            let store = try SQLiteMeetingStore(databaseURL: database); reopened = store
            let usage = MeetingUsageRegistry()
            let admission = HeavyModelAdmission()
            let replay = MeetingTranscriptionReplayCoordinator(store: store, models: models,
                recordingsRoot: recordings, usage: usage, admission: admission, modelPolicy: .capturedPinRequired)
            var report: TranscriptionReplayReport?
            do { report = try await replay.replay(meetingID: id) }
            catch { XCTFail("Captured native Core ML recovery must use the actual TDT model: \(type(of: error))") }
            XCTAssertEqual(report?.replayedFrameCount, audio.totalFrames - prefix)
            XCTAssertEqual(report?.timelineEndSample, audio.totalFrames)
            let rows = try await store.transcript(meetingID: id)
            XCTAssertEqual(rows.first, original)
            XCTAssertGreaterThan(rows.count, 1)
            XCTAssertTrue(rows.dropFirst().contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            var cursor = prefix
            for row in rows.dropFirst() {
                XCTAssertEqual(row.modelRevision, installed.manifest.revision)
                XCTAssertGreaterThanOrEqual(row.startSample, cursor)
                XCTAssertGreaterThan(row.endSample, row.startSample)
                XCTAssertLessThanOrEqual(row.endSample, audio.totalFrames)
                cursor = row.endSample
            }
            let savedPin = try await store.speechModelPin(meetingID: id)
            let savedNote = try await store.manualNote(meetingID: id)
            let checkpoint = try await replay.checkpoint(meetingID: id)
            XCTAssertEqual(savedPin, pin); XCTAssertEqual(savedNote, note)
            XCTAssertEqual(checkpoint?.nextGlobalSample, audio.totalFrames)
            XCTAssertEqual(checkpoint?.modelRevision, pin.selection.manifest.revision)
            XCTAssertEqual(checkpoint?.committedSequence, rows.count - 1)
            XCTAssertEqual(try sourceDigests(directory), originals)
            XCTAssertEqual(admission.snapshot().phase, .idle)
            if report != nil {
                let again = try await replay.replay(meetingID: id)
                XCTAssertEqual(again.replayedFrameCount, 0)
                XCTAssertTrue(again.insertedSegmentIDs.isEmpty)
                let unchangedRows = try await store.transcript(meetingID: id)
                XCTAssertEqual(unchangedRows, rows)
                XCTAssertEqual(try sourceDigests(directory), originals)
            }
            try await store.close(); reopened = nil
        } catch {
            try? await reopened?.close(); try? await initial.close()
            try? CoreMLParakeetFixture.remove(root, suffix: "v3-replay")
            throw error
        }
        try CoreMLParakeetFixture.remove(root, suffix: "v3-replay")
    }

    private func sourceDigests(_ directory: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "caf" || url.lastPathComponent == "capture-manifest.json" {
            result[url.lastPathComponent] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
}
