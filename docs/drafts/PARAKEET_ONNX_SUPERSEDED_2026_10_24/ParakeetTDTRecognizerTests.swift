import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
@testable import LocalMinutesTranscription

/// Actual pinned int8 ONNX inference and exact licensed speech. Missing model
/// bytes or fixture setup is an error, never an optional skip or a valid RED.
@MainActor
final class ParakeetTDTRecognizerTests: XCTestCase {
    func testActualParakeetLoadsOnCPUAndNativeCallsStayOnOwnedWorker() async throws {
        let fixture = try ParakeetTDTFixture.load()
        let calls = ParakeetExecutionRecords()
        let recognizer = ParakeetTDTRecognizer(files: fixture.files) { op, main, worker in
            calls.append(op, main, worker)
        }
        try await recognizer.load()
        let state = await recognizer.snapshot()
        XCTAssertEqual(state.phase, .ready); XCTAssertEqual(state.provider, .cpu)
        XCTAssertNil(state.epochID); XCTAssertEqual(state.acceptedSampleCount, 0)
        XCTAssertEqual(ParakeetTDTRecognizer.decodingMode, .chunkedOffline)
        try await recognizer.start(epochID: UUID())
        _ = try await recognizer.accept(fixture.samples, at: 0)
        let result = try await recognizer.finish()
        XCTAssertTrue(words(result.finalized.map(\.text).joined(separator: " ")).contains("returned"))
        let observed = calls.read()
        XCTAssertTrue(observed.contains { $0.0 == .load })
        XCTAssertTrue(observed.contains { $0.0 == .decode })
        XCTAssertTrue(observed.allSatisfy { !$0.1 && $0.2 }, "Each actual C load/decode must run on the dedicated serial worker")
        await recognizer.unload()
        let unloaded = await recognizer.snapshot()
        XCTAssertEqual(unloaded.phase, .unloaded); XCTAssertNil(unloaded.provider)
    }

    func testDisjointWindowsPublishRealSpeechBeforeStopAndFlushTailExactlyOnce() async throws {
        let fixture = try ParakeetTDTFixture.load()
        let recognizer = ParakeetTDTRecognizer(files: fixture.files)
        try await recognizer.load()
        let epoch = UUID(); try await recognizer.start(epochID: epoch)
        XCTAssertLessThan(fixture.samples.count, ParakeetTDTRecognizer.stepSamples)
        let firstWindow = fixture.samples + Array(repeating: Float(0), count: ParakeetTDTRecognizer.stepSamples - fixture.samples.count)
        let samples = firstWindow + fixture.samples
        var finalized: [WhisperSpeechSegment] = []
        var firstWindowWasVisible = false
        for offset in stride(from: 0, to: samples.count, by: 3_200) {
            let end = min(offset + 3_200, samples.count)
            let update = try await recognizer.accept(Array(samples[offset..<end]), at: Int64(offset))
            XCTAssertEqual(update.epochID, epoch)
            finalized += update.finalized
            if end == ParakeetTDTRecognizer.stepSamples {
                firstWindowWasVisible = words((finalized.map(\.text) + [update.partial]).joined(separator: " ")).contains("tents")
            }
            let state = await recognizer.snapshot()
            XCTAssertEqual(state.acceptedSampleCount, Int64(end))
            XCTAssertLessThanOrEqual(state.bufferedSampleCount, ParakeetTDTRecognizer.maximumWindowSamples)
        }
        XCTAssertTrue(firstWindowWasVisible, "The first real five-second window must decode before Stop")
        let final = try await recognizer.finish(); finalized += final.finalized
        let text = words(finalized.map(\.text).joined(separator: " "))
        XCTAssertEqual(text.filter { $0 == "returned" }.count, 2)
        XCTAssertEqual(text.filter { $0 == "tents" }.count, 2, "The final partial window must retain the second utterance")
        XCTAssertEqual(Set(finalized.map(\.id)).count, finalized.count)
        var previousEnd: Int64 = 0
        for segment in finalized {
            XCTAssertGreaterThanOrEqual(segment.startSample, previousEnd)
            XCTAssertGreaterThan(segment.endSample, segment.startSample)
            XCTAssertLessThanOrEqual(segment.endSample, Int64(samples.count))
            previousEnd = segment.endSample
        }
        let repeated = try await recognizer.finish()
        XCTAssertTrue(repeated.finalized.isEmpty)
        let finished = await recognizer.snapshot()
        XCTAssertEqual(finished.phase, .finished); XCTAssertEqual(finished.acceptedSampleCount, Int64(samples.count))
        await recognizer.unload()
    }

    func testCancellationIsEpochScopedAndUnloadAllowsFreshActualRecognition() async throws {
        let fixture = try ParakeetTDTFixture.load()
        let recognizer = ParakeetTDTRecognizer(files: fixture.files)
        try await recognizer.load()
        let old = UUID(); try await recognizer.start(epochID: old)
        _ = try await recognizer.accept(Array(fixture.samples.prefix(3_200)), at: 0)
        await recognizer.cancel(epochID: old)
        do { _ = try await recognizer.accept([0], at: 3_200); XCTFail("Cancelled PCM reached a native stream") }
        catch { XCTAssertEqual(error as? StreamingASRError, .cancelled) }
        let fresh = UUID(); try await recognizer.start(epochID: fresh)
        await recognizer.cancel(epochID: old)
        _ = try await recognizer.accept(fixture.samples, at: 0)
        let result = try await recognizer.finish()
        XCTAssertEqual(result.epochID, fresh)
        XCTAssertEqual(words(result.finalized.map(\.text).joined(separator: " ")).filter { $0 == "returned" }.count, 1)
        await recognizer.unload(); await recognizer.unload()
        let empty = await recognizer.snapshot()
        XCTAssertEqual(empty.phase, .unloaded); XCTAssertNil(empty.epochID)
        XCTAssertEqual(empty.acceptedSampleCount, 0); XCTAssertEqual(empty.bufferedSampleCount, 0)
        try await recognizer.load(); try await recognizer.start(epochID: UUID())
        _ = try await recognizer.accept(fixture.samples, at: 0)
        let reloaded = try await recognizer.finish()
        XCTAssertTrue(words(reloaded.finalized.map(\.text).joined(separator: " ")).contains("tents"))
        await recognizer.unload()
    }

    func testInvalidPCMAndGapsCannotAdvanceActualNativeTimeline() async throws {
        let fixture = try ParakeetTDTFixture.load()
        let recognizer = ParakeetTDTRecognizer(files: fixture.files)
        try await recognizer.load(); try await recognizer.start(epochID: UUID())
        for samples: [Float] in [[], [.nan], [.infinity], [1.01], Array(repeating: 0, count: 80_001)] {
            do { _ = try await recognizer.accept(samples, at: 0); XCTFail("Invalid PCM was accepted") }
            catch { XCTAssertEqual(error as? StreamingASRError, .invalidSamples) }
        }
        do { _ = try await recognizer.accept([0], at: 1); XCTFail("Source discontinuity silently collapsed") }
        catch { XCTAssertEqual(error as? StreamingASRError, .discontinuity(expected: 0, actual: 1)) }
        let state = await recognizer.snapshot()
        XCTAssertEqual(state.acceptedSampleCount, 0); XCTAssertEqual(state.bufferedSampleCount, 0)
        await recognizer.unload()
    }

    func testUnverifiedModelIsRejectedBeforeAnyNativeConstructor() async throws {
        let root = try ParakeetTDTFixture.temporaryRoot("invalid")
        defer { try? ParakeetTDTFixture.remove(root, suffix: "invalid") }
        let calls = ParakeetExecutionRecords()
        for artifact in ParakeetTDTModel.manifest.artifacts {
            try Data([0, 1, 2]).write(to: root.appendingPathComponent(artifact.fileName))
        }
        let recognizer = ParakeetTDTRecognizer(files: ParakeetTDTFixture.files(in: root)) { op, main, worker in
            calls.append(op, main, worker)
        }
        do { try await recognizer.load(); XCTFail("Tiny unverified bytes entered C++ model creation") }
        catch { XCTAssertEqual(error as? StreamingASRError, .invalidModel) }
        XCTAssertTrue(calls.read().isEmpty)
        let state = await recognizer.snapshot(); XCTAssertEqual(state.phase, .unloaded)
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private final class ParakeetExecutionRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(ParakeetTDTNativeOperation, Bool, Bool)] = []
    func append(_ op: ParakeetTDTNativeOperation, _ main: Bool, _ worker: Bool) {
        lock.withLock { values.append((op, main, worker)) }
    }
    func read() -> [(ParakeetTDTNativeOperation, Bool, Bool)] { lock.withLock { values } }
}

@MainActor
struct ParakeetTDTFixture {
    let directory: URL
    let files: StreamingASRModelFiles
    let samples: [Float]
    private static var cached: ParakeetTDTFixture?

    static func load() throws -> Self {
        if let cached { return cached }
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_MODEL_DIRECTORY"]))
        let audioURL = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_FIXTURE_PATH"]))
        for artifact in ParakeetTDTModel.manifest.artifacts {
            let url = directory.appendingPathComponent(artifact.fileName)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            guard size == artifact.byteCount, try sha256(url) == artifact.sha256 else {
                XCTFail("Actual Parakeet fixture integrity failed: \(artifact.fileName)")
                throw StreamingASRError.invalidModel
            }
        }
        let bytes = try Data(contentsOf: audioURL)
        guard bytes.count == 74_138, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined()
            == "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23" else {
            XCTFail("Exact licensed LibriSpeech fixture missing or corrupt")
            throw StreamingASRError.invalidSamples
        }
        let audio = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
              audio.length > 0, audio.length < 80_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else {
            throw StreamingASRError.invalidSamples
        }
        try audio.read(into: buffer)
        XCTAssertEqual(Int64(buffer.frameLength), audio.length)
        let pointer = try XCTUnwrap(buffer.floatChannelData?.pointee)
        let value = Self(directory: directory, files: files(in: directory),
                         samples: Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength))))
        cached = value
        return value
    }

    static func files(in directory: URL) -> StreamingASRModelFiles {
        .init(encoder: directory.appendingPathComponent("encoder.int8.onnx"),
              decoder: directory.appendingPathComponent("decoder.int8.onnx"),
              joiner: directory.appendingPathComponent("joiner.int8.onnx"),
              tokens: directory.appendingPathComponent("tokens.txt"),
              revision: ParakeetTDTModel.revision, runtimeVersion: "sherpa-onnx-1.13.8")
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func temporaryRoot(_ suffix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-parakeet-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    static func remove(_ root: URL, suffix: String) throws {
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-parakeet-\(suffix)-"), root.resolvingSymlinksInPath() == root else {
            throw StreamingASRError.invalidModel
        }
        try FileManager.default.removeItem(at: root)
    }
}
