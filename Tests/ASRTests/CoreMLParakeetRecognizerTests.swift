import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
@testable import LocalMinutesTranscription

/// Actual pinned native Core ML inference and exact licensed speech. Missing model
/// bytes or fixture setup fails the test rather than skipping inference.
@MainActor
final class CoreMLParakeetRecognizerTests: XCTestCase {
    func testActualParakeetProductionDefaultRequestsCPUOnlyWithoutAnExplicitOverride() async throws {
        let fixture = try CoreMLParakeetFixture.load()
        // Exercise the same default argument used by production composition;
        // passing .cpuOnly here would conceal an unapproved default change.
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files)
        do {
            try await recognizer.load()
            let state = await recognizer.snapshot()
            XCTAssertEqual(state.phase, .ready)
            XCTAssertEqual(state.computePolicy, .cpuOnly,
                "Production live ASR must request the CPU-only policy required by the project contract")
            // Configuration/observation proves the requested policy, not actual
            // chip placement. Existing actual-CPU decoding cases remain separate.
            await recognizer.unload()
            let unloaded = await recognizer.snapshot()
            XCTAssertEqual(unloaded.phase, .unloaded)
        } catch {
            await recognizer.unload()
            throw error
        }
    }

    func testActualParakeetLoadsOnCPUAndNativeCallsStayOnOwnedWorker() async throws {
        let fixture = try CoreMLParakeetFixture.load()
        let calls = CoreMLParakeetExecutionRecords()
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly) { op, main, worker, policy in
            calls.append(op, main, worker, policy)
        }
        try await recognizer.load()
        let state = await recognizer.snapshot()
        XCTAssertEqual(state.phase, .ready); XCTAssertEqual(state.computePolicy, .cpuOnly); XCTAssertEqual(state.modelRevision, ParakeetCoreMLModel.revision)
        XCTAssertNil(state.epochID); XCTAssertEqual(state.acceptedSampleCount, 0)
        try await recognizer.start(epochID: UUID())
        _ = try await recognizer.accept(fixture.samples, at: 0)
        let result = try await recognizer.finish()
        XCTAssertTrue(words(result.finalized.map(\.text).joined(separator: " ")).contains("returned"))
        let observed = calls.read()
        XCTAssertTrue(observed.contains { $0.0 == .load })
        XCTAssertTrue(observed.contains { $0.0 == .denoise }, "Default transcription must run gentle enhancement on its worker")
        XCTAssertTrue(observed.contains { $0.0 == .decode })
        XCTAssertTrue(observed.allSatisfy { !$0.1 && $0.2 && $0.3 == .cpuOnly }, "Each actual Core ML load/decode must run on the dedicated serial worker")
        await recognizer.unload()
        let unloaded = await recognizer.snapshot()
        XCTAssertEqual(unloaded.phase, .unloaded); XCTAssertNil(unloaded.computePolicy)
    }

    func testDisablingNoiseReductionFeedsOriginalPCMThroughActualRecognition() async throws {
        let fixture = try CoreMLParakeetFixture.load()
        let calls = CoreMLParakeetExecutionRecords()
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly,
            noiseReduction: .off) { op, main, worker, policy in calls.append(op, main, worker, policy) }
        do {
            try await recognizer.load()
            try await recognizer.start(epochID: UUID())
            _ = try await recognizer.accept(fixture.samples, at: 0)
            let result = try await recognizer.finish()
            XCTAssertTrue(words(result.finalized.map(\.text).joined(separator: " ")).contains("returned"))
            XCTAssertFalse(calls.read().contains { $0.0 == .denoise })
            await recognizer.unload()
        } catch { await recognizer.unload(); throw error }
    }

    func testDisjointWindowsPublishRealSpeechBeforeStopAndFlushTailExactlyOnce() async throws {
        let fixture = try CoreMLParakeetFixture.load()
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly)
        try await recognizer.load()
        let epoch = UUID(); try await recognizer.start(epochID: epoch)
        XCTAssertLessThan(fixture.samples.count, CoreMLParakeetRecognizer.stepSamples)
        let firstWindow = fixture.samples + Array(repeating: Float(0), count: CoreMLParakeetRecognizer.stepSamples - fixture.samples.count)
        let samples = firstWindow + fixture.samples
        var finalized: [SpeechSegment] = []
        var firstWindowWasVisible = false
        for offset in stride(from: 0, to: samples.count, by: 3_200) {
            let end = min(offset + 3_200, samples.count)
            let update = try await recognizer.accept(Array(samples[offset..<end]), at: Int64(offset))
            XCTAssertEqual(update.epochID, epoch)
            finalized += update.finalized
            if end == CoreMLParakeetRecognizer.stepSamples {
                firstWindowWasVisible = words((finalized.map(\.text) + [update.partial]).joined(separator: " ")).contains("tents")
            }
            let state = await recognizer.snapshot()
            XCTAssertEqual(state.acceptedSampleCount, Int64(end))
            XCTAssertLessThanOrEqual(state.bufferedSampleCount, CoreMLParakeetRecognizer.maximumWindowSamples)
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
        let fixture = try CoreMLParakeetFixture.load()
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly)
        try await recognizer.load()
        let old = UUID(); try await recognizer.start(epochID: old)
        _ = try await recognizer.accept(Array(fixture.samples.prefix(3_200)), at: 0)
        await recognizer.cancel(epochID: old)
        do { _ = try await recognizer.accept([0], at: 3_200); XCTFail("Cancelled PCM reached a native stream") }
        catch { XCTAssertEqual(error as? SpeechRecognitionError, .cancelled) }
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
        let fixture = try CoreMLParakeetFixture.load()
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly)
        try await recognizer.load(); try await recognizer.start(epochID: UUID())
        let invalidInputs: [[Float]] = [[], [.nan], [.infinity], [1.01], Array(repeating: 0, count: 80_001)]
        for samples in invalidInputs {
            do { _ = try await recognizer.accept(samples, at: 0); XCTFail("Invalid PCM was accepted") }
            catch { XCTAssertEqual(error as? SpeechRecognitionError, .invalidSamples) }
        }
        do { _ = try await recognizer.accept([0], at: 1); XCTFail("Source discontinuity silently collapsed") }
        catch { XCTAssertEqual(error as? SpeechRecognitionError, .discontinuity(expected: 0, actual: 1)) }
        let state = await recognizer.snapshot()
        XCTAssertEqual(state.acceptedSampleCount, 0); XCTAssertEqual(state.bufferedSampleCount, 0)
        await recognizer.unload()
    }

    func testUnverifiedModelIsRejectedBeforeAnyNativeConstructor() async throws {
        let root = try CoreMLParakeetFixture.temporaryRoot("invalid")
        defer { try? CoreMLParakeetFixture.remove(root, suffix: "invalid") }
        let calls = CoreMLParakeetExecutionRecords()
        for artifact in ParakeetCoreMLModel.manifest.artifacts {
            let destination = root.appendingPathComponent(artifact.fileName)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0, 1, 2]).write(to: destination)
        }
        let recognizer = CoreMLParakeetRecognizer(files: CoreMLParakeetFixture.files(in: root), computePolicy: .cpuOnly) { op, main, worker, policy in
            calls.append(op, main, worker, policy)
        }
        do { try await recognizer.load(); XCTFail("Tiny unverified bytes entered native Core ML loading") }
        catch { XCTAssertEqual(error as? SpeechRecognitionError, .invalidModel) }
        XCTAssertTrue(calls.read().isEmpty)
        let state = await recognizer.snapshot(); XCTAssertEqual(state.phase, .unloaded)
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

private final class CoreMLParakeetExecutionRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(CoreMLParakeetNativeOperation, Bool, Bool, CoreMLParakeetComputePolicy)] = []
    func append(_ op: CoreMLParakeetNativeOperation, _ main: Bool, _ worker: Bool, _ policy: CoreMLParakeetComputePolicy) {
        lock.withLock { values.append((op, main, worker, policy)) }
    }
    func read() -> [(CoreMLParakeetNativeOperation, Bool, Bool, CoreMLParakeetComputePolicy)] { lock.withLock { values } }
}

@MainActor
struct CoreMLParakeetFixture {
    static let reference = "CONCORD RETURNED TO ITS PLACE AMIDST THE TENTS"
    var windowSamples: [Float] { samples + [Float](repeating: 0, count: CoreMLParakeetRecognizer.stepSamples - samples.count) }
    let directory: URL
    let files: CoreMLParakeetModelFiles
    let samples: [Float]
    private static var cached: CoreMLParakeetFixture?

    static func load() throws -> Self {
        if let cached { return cached }
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_COREML_MODEL_DIRECTORY"]))
        let audioURL = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_PARAKEET_COREML_FIXTURE_PATH"]))
        for artifact in ParakeetCoreMLModel.manifest.artifacts {
            let url = directory.appendingPathComponent(artifact.fileName)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            guard size == artifact.byteCount, try sha256(url) == artifact.sha256 else {
                XCTFail("Actual Parakeet fixture integrity failed: \(artifact.fileName)")
                throw SpeechRecognitionError.invalidModel
            }
        }
        let bytes = try Data(contentsOf: audioURL)
        guard bytes.count == 74_138, SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined()
            == "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23" else {
            XCTFail("Exact licensed LibriSpeech fixture missing or corrupt")
            throw SpeechRecognitionError.invalidSamples
        }
        let audio = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
              audio.length > 0, audio.length < 80_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else {
            throw SpeechRecognitionError.invalidSamples
        }
        try audio.read(into: buffer)
        XCTAssertEqual(Int64(buffer.frameLength), audio.length)
        let pointer = try XCTUnwrap(buffer.floatChannelData?.pointee)
        let value = Self(directory: directory, files: files(in: directory),
                         samples: Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength))))
        cached = value
        return value
    }

    static func files(in directory: URL) -> CoreMLParakeetModelFiles {
        .init(directory: directory, revision: ParakeetCoreMLModel.revision,
              runtimeVersion: ParakeetCoreMLModel.runtimeVersion)
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
            throw SpeechRecognitionError.invalidModel
        }
        try FileManager.default.removeItem(at: root)
    }
}
