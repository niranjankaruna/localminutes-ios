import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
@testable import LocalMinutesTranscription

/// Actual selected tiny.en GGML + licensed LibriSpeech audio, real CAF files and
/// SQLite. No Zipformer installation, native recognizer double or generated text.
@MainActor
final class SelectedWhisperLiveSessionTests: XCTestCase {
    func testEquippedWhisperStreamsLicensedSpeechBeforeStopAndPersistsFinalGlobalRanges() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelURL = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_WHISPER_MODEL_PATH"]))
        let audioURL = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_WHISPER_FIXTURE_PATH"]))
        let modelSize = (try FileManager.default.attributesOfItem(atPath: modelURL.path)[.size] as? NSNumber)?.int64Value
        let digest = try sha256(modelURL)
        XCTAssertEqual(modelSize, 77_704_715)
        XCTAssertEqual(digest, "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        guard modelSize == 77_704_715,
              digest == "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f" else {
            throw StreamingASRError.invalidModel
        }
        let audioData = try Data(contentsOf: audioURL)
        XCTAssertEqual(audioData.count, 74_138)
        let audioDigest = SHA256.hash(data: audioData).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(audioDigest, "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23")
        guard audioData.count == 74_138,
              audioDigest == "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23" else {
            throw StreamingASRError.invalidSamples
        }
        // LibriSpeech6930-75918-0000, CC-BY-4.0; Panayotov/Povey,
        // LibriVox source. This is the existing pinned non-sensitive fixture.
        let audio = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
              (1...480_000).contains(audio.length) else { throw StreamingASRError.invalidSamples }
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: decoded)
        XCTAssertEqual(Int64(decoded.frameLength), audio.length)
        let plane = try XCTUnwrap(decoded.floatChannelData?.pointee)
        let speech = Array(UnsafeBufferPointer(start: plane, count: Int(decoded.frameLength)))
        let samples = speech + Array(repeating: Float(0), count: 48_000) + speech
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-selected-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let database = root.appendingPathComponent("meetings.sqlite")
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
        let store = try SQLiteMeetingStore(databaseURL: database)
        let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
        let repository = "https://huggingface.co/ggerganov/whisper.cpp"
        let manifest = ModelManifest(modelID: "whisper-tiny-en", purpose: .speechRecognition,
            upstreamRepository: URL(string: repository)!, revision: revision, licenseIdentifier: "MIT",
            licenseNotice: "Whisper by OpenAI; whisper.cpp GGML conversion by Georgi Gerganov. MIT License: https://github.com/openai/whisper/blob/main/LICENSE",
            runtimeVersion: "whisper.cpp-1.7.5", sampleRate: 16_000,
            artifacts: [.init(role: .whisper, fileName: "ggml-tiny.en.bin", byteCount: 77_704_715, sha256: digest,
                downloadURL: URL(string: repository + "/resolve/" + revision + "/ggml-tiny.en.bin")!,
                digestProvenance: .independentlyDownloaded)])
        let session = LiveTranscriptionSession(models: models, store: store,
            meetingsDirectory: root.appendingPathComponent("Meetings"), selectedSpeechModel: { manifest })
        let id = UUID()
        var capture: AudioCaptureManifest?
        do {
            let source = root.appendingPathComponent("Import")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try FileManager.default.copyItem(at: modelURL, to: source.appendingPathComponent("ggml-tiny.en.bin"))
            _ = try await models.importDirectory(source, manifest: manifest)
            let prepared = await session.prepare(sessionID: id)
            XCTAssertTrue({ if case .ready = prepared { true } else { false } }(),
                "An equipped verified Whisper model must reach live readiness without an installed Zipformer default")
            guard case .ready(let directory) = prepared else {
                let rows = try await store.history()
                XCTAssertTrue(rows.isEmpty)
                try await store.close(); try remove(root)
                return
            }
            do { try await models.remove(modelID: manifest.modelID); XCTFail("Live Whisper must retain its model lease") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
            let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 32_000)
            let sink = try XCTUnwrap(session.normalizedSink)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            for start in stride(from: 0, to: samples.count, by: 1_600) {
                let count = min(1_600, samples.count - start)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                buffer.frameLength = AVAudioFrameCount(count)
                let target = try XCTUnwrap(buffer.floatChannelData?.pointee)
                for index in 0..<count { target[index] = samples[start + index] }
                try writer.append(buffer)
                XCTAssertTrue(sink.offer(buffer, sourceStartSample: Int64(start)))
            }
            let captured = try writer.finish()
            capture = captured
            XCTAssertEqual(captured.totalFrames, Int64(samples.count))
            XCTAssertGreaterThan(captured.segments.count, 1, "The live inference path must coexist with real durable CAF segmentation")
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while session.transcript.partial.isEmpty && session.transcript.finalized.isEmpty && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(!session.transcript.partial.isEmpty || !session.transcript.finalized.isEmpty,
                "Actual selected Whisper must publish speech before finish, not defer all inference until Stop")
            let failure = await session.finish(sessionID: id, manifest: captured)
            XCTAssertNil(failure)
            XCTAssertEqual(session.transcript.receivedSampleCount, Int64(samples.count))
            XCTAssertEqual(session.transcript.partial, "")
            let rows = try await store.transcript(meetingID: id)
            XCTAssertEqual(rows, session.transcript.finalized)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertEqual(rows.map(\.sequence), Array(0..<rows.count))
            XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
            let words = rows.map(\.text).joined(separator: " ").lowercased().split { !$0.isLetter }
            XCTAssertEqual(words.filter { $0 == "returned" }.count, 2)
            XCTAssertEqual(words.filter { $0 == "tents" }.count, 2, "Final flush must retain the second utterance's trailing plural word")
            var previousEnd: Int64 = 0
            for row in rows {
                XCTAssertEqual(row.meetingID, id); XCTAssertEqual(row.modelRevision, revision)
                XCTAssertGreaterThanOrEqual(row.startSample, previousEnd)
                XCTAssertGreaterThan(row.endSample, row.startSample)
                XCTAssertLessThanOrEqual(row.endSample, Int64(samples.count))
                previousEnd = row.endSample
            }
            let again = await session.finish(sessionID: id, manifest: captured)
            XCTAssertNil(again)
            let repeated = try await store.transcript(meetingID: id)
            XCTAssertEqual(repeated, rows, "Repeated finish must not duplicate final text")
            let metadata = try await store.meeting(id: id)
            XCTAssertEqual(metadata?.recordingState, .completed)
            XCTAssertEqual(metadata?.capturedSampleCount, Int64(samples.count))
            try await models.remove(modelID: manifest.modelID)
            let removed = try await models.current(modelID: manifest.modelID)
            XCTAssertNil(removed)
            try await store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            let persisted = try await reopened.transcript(meetingID: id)
            XCTAssertEqual(persisted, rows)
            try await reopened.close(); try remove(root)
        } catch {
            _ = await session.finish(sessionID: id, manifest: capture)
            try? await store.close(); try? remove(root)
            throw error
        }
    }

    private func sha256(_ file: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var hash = SHA256()
        while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func remove(_ root: URL) throws {
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-selected-whisper-"),
              root.resolvingSymlinksInPath() == root else { throw StreamingASRError.invalidModel }
        try FileManager.default.removeItem(at: root)
    }
}
