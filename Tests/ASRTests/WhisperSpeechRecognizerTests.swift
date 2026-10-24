import AVFoundation
import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesTranscription

/// Actual pinned GGML model and licensed audio. No inference/network doubles,
/// optional environment switch, skipped test or physical-device claim.
@MainActor
final class WhisperSpeechRecognizerTests: XCTestCase {
    func testWhisperLoadsActualPinnedModelOnCPUOutsideMainThread() async throws {
        let fixture = try WhisperFixture.load()
        let executions = WhisperExecutionRecords()
        let recognizer = WhisperSpeechRecognizer(files: fixture.files) { operation, main, gpu in
            executions.append(operation, main, gpu)
        }
        try await recognizer.load()
        let loaded = await recognizer.snapshot()
        XCTAssertEqual(loaded.phase, .ready); XCTAssertEqual(loaded.provider, .cpu)
        XCTAssertNil(loaded.epochID); XCTAssertEqual(loaded.acceptedSampleCount, 0)
        let observed = executions.read()
        XCTAssertTrue(observed.contains { $0.0 == .load })
        XCTAssertTrue(observed.allSatisfy { !$0.1 && !$0.2 }, "Actual native call sites must be off MainActor with use_gpu=false")
        await recognizer.unload()
        let unloaded = await recognizer.snapshot()
        XCTAssertEqual(unloaded.phase, .unloaded)
    }

    func testWhisperRollingWindowsPublishActualSpeechGlobalRangesAndNoRepeatedFinals() async throws {
        let fixture = try WhisperFixture.load()
        let recognizer = WhisperSpeechRecognizer(files: fixture.files)
        try await recognizer.load()
        let epoch = UUID(); try await recognizer.start(epochID: epoch)
        // Two genuine utterances at distinct global positions, followed by
        // enough actual PCM silence to exercise30s window eviction.
        let samples = fixture.samples + Array(repeating: Float(0), count: 32_000)
            + fixture.samples + Array(repeating: Float(0), count: 560_000)
        var finalized: [WhisperSpeechSegment] = []
        var visibleBeforeFinish = false
        for offset in stride(from: 0, to: samples.count, by: 3_200) {
            let end = min(offset + 3_200, samples.count)
            let update = try await recognizer.accept(Array(samples[offset..<end]), at: Int64(offset))
            XCTAssertEqual(update.epochID, epoch)
            visibleBeforeFinish = visibleBeforeFinish || !update.partial.isEmpty || !update.finalized.isEmpty
            finalized += update.finalized
            let state = await recognizer.snapshot()
            XCTAssertEqual(state.acceptedSampleCount, Int64(end))
            XCTAssertLessThanOrEqual(state.bufferedSampleCount, 480_000)
        }
        let ending = try await recognizer.finish(); finalized += ending.finalized
        XCTAssertTrue(visibleBeforeFinish, "Real transcription must be visible during rolling capture")
        XCTAssertFalse(finalized.isEmpty)
        let text = words(finalized.map(\.text).joined(separator: " "))
        XCTAssertEqual(text.filter { $0 == "returned" }.count, 2, "Overlap must not repeat recognized speech; separate real utterances survive")
        XCTAssertEqual(text.filter { $0 == "tents" }.count, 2)
        XCTAssertEqual(Set(finalized.map(\.id)).count, finalized.count)
        var previousEnd: Int64 = 0
        for segment in finalized {
            XCTAssertGreaterThanOrEqual(segment.startSample, previousEnd)
            XCTAssertGreaterThan(segment.endSample, segment.startSample)
            XCTAssertLessThanOrEqual(segment.endSample, Int64(samples.count))
            previousEnd = segment.endSample
        }
        let replay = try await recognizer.finish()
        XCTAssertTrue(replay.finalized.isEmpty, "Idempotent finish must not publish duplicate durable segments")
        let finished = await recognizer.snapshot()
        XCTAssertEqual(finished.phase, .finished); XCTAssertEqual(finished.acceptedSampleCount, Int64(samples.count))
        await recognizer.unload()
    }

    func testWhisperCancellationRejectsStaleAudioAndFreshEpochRecognizesWithoutOldFinals() async throws {
        let fixture = try WhisperFixture.load()
        let recognizer = WhisperSpeechRecognizer(files: fixture.files)
        try await recognizer.load()
        let old = UUID(); try await recognizer.start(epochID: old)
        _ = try await recognizer.accept(Array(fixture.samples.prefix(3_200)), at: 0)
        await recognizer.cancel(epochID: old)
        do { _ = try await recognizer.accept([0], at: 3_200); XCTFail("Cancelled stream admitted late PCM") }
        catch { XCTAssertEqual(error as? StreamingASRError, .cancelled) }
        let fresh = UUID(); try await recognizer.start(epochID: fresh)
        var segments: [WhisperSpeechSegment] = []
        for offset in stride(from: 0, to: fixture.samples.count, by: 3_200) {
            let update = try await recognizer.accept(Array(fixture.samples[offset..<min(offset + 3_200, fixture.samples.count)]),
                                                      at: Int64(offset))
            XCTAssertEqual(update.epochID, fresh); segments += update.finalized
        }
        let result = try await recognizer.finish(); segments += result.finalized
        let text = words(segments.map(\.text).joined(separator: " "))
        XCTAssertTrue(text.contains("returned")); XCTAssertTrue(text.contains("place")); XCTAssertTrue(text.contains("tents"))
        XCTAssertEqual(text.filter { $0 == "returned" }.count, 1)
        await recognizer.unload()
    }

    func testWhisperInvalidAndDiscontinuousPCMDoesNotAdvanceAcceptedTimeline() async throws {
        let fixture = try WhisperFixture.load()
        let recognizer = WhisperSpeechRecognizer(files: fixture.files)
        try await recognizer.load(); try await recognizer.start(epochID: UUID())
        do { _ = try await recognizer.accept([.nan], at: 0); XCTFail("NaN entered native inference") }
        catch { XCTAssertEqual(error as? StreamingASRError, .invalidSamples) }
        do { _ = try await recognizer.accept([0], at: 99); XCTFail("A source gap was silently collapsed") }
        catch { XCTAssertEqual(error as? StreamingASRError, .discontinuity(expected: 0, actual: 99)) }
        let state = await recognizer.snapshot(); XCTAssertEqual(state.acceptedSampleCount, 0)
        await recognizer.unload()
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private final class WhisperExecutionRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(WhisperNativeOperation, Bool, Bool)] = []
    func append(_ operation: WhisperNativeOperation, _ main: Bool, _ gpu: Bool) { lock.withLock { values.append((operation, main, gpu)) } }
    func read() -> [(WhisperNativeOperation, Bool, Bool)] { lock.withLock { values } }
}

private struct WhisperFixture {
    let files: WhisperSpeechModelFiles
    let samples: [Float]
    static func load() throws -> WhisperFixture {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = try XCTUnwrap(environment["LOCALMINUTES_WHISPER_MODEL_PATH"])
        let audioPath = try XCTUnwrap(environment["LOCALMINUTES_WHISPER_FIXTURE_PATH"])
        let model = URL(fileURLWithPath: modelPath)
        let size = (try FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, 77_704_715)
        guard size == 77_704_715 else { throw StreamingASRError.invalidModel }
        let handle = try FileHandle(forReadingFrom: model)
        var hash = SHA256()
        do {
            while let bytes = try handle.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
            try handle.close()
        } catch { try? handle.close(); throw error }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f")
        guard digest == "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f" else { throw StreamingASRError.invalidModel }
        let audioURL = URL(fileURLWithPath: audioPath), data = try Data(contentsOf: audioURL)
        XCTAssertEqual(data.count, 74_138)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                       "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23")
        let audio = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
              audio.length > 0, audio.length <= 16_000 * 30,
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else {
            throw StreamingASRError.invalidSamples
        }
        try audio.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?.pointee)
        return .init(files: .init(model: model, revision: "5359861c739e955e79d9a303bcbc70fb988958b1",
                                 byteCount: 77_704_715, sha256: digest),
                     samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    }
}
