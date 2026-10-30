import AVFoundation
import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesTranscription

/// Fixed 45.85-second public audiobook corpus with controlled-noise and quiet
/// conditions. This is not representative accent, technical-meeting, or device
/// validation. Missing assets/models fail; no skip or fake generation exists.
@MainActor
final class ASRCorpusQualityTests: XCTestCase {
    func testActualNativeParakeetCleanAnd15dBNoiseCorpusWordErrorRates() async throws {
        let fixture = try CoreMLParakeetFixture.load() // Existing exact native artifact hashes.
        let recognizer = CoreMLParakeetRecognizer(files: fixture.files, computePolicy: .cpuOnly)
        try await recognizer.load()
        do {
            try await evaluate(engine: "parakeet-cpu", modelRevision: fixture.files.revision,
                               runtimeVersion: fixture.files.runtimeVersion) { samples in
                try await recognizer.start(epochID: UUID())
                var text: [String] = []
                // The native adapter accepts at most five seconds per call and
                // performs its own bounded decoding; never feed a whole long clip.
                for offset in stride(from: 0, to: samples.count, by: CoreMLParakeetRecognizer.stepSamples) {
                    let update = try await recognizer.accept(
                        Array(samples[offset..<min(offset + CoreMLParakeetRecognizer.stepSamples, samples.count)]),
                        at: Int64(offset))
                    text += update.finalized.map(\.text)
                }
                let tail = try await recognizer.finish()
                text += tail.finalized.map(\.text)
                return text.joined(separator: " ")
            }
            await recognizer.unload()
        } catch { await recognizer.unload(); throw error }
    }

    func testActualGentleNoiseReductionComparedWithUnfilteredQuietSpeech() async throws {
        let model = try CoreMLParakeetFixture.load()
        let corpus = try ASRQualityCorpus.load()
        var totals: [String: [String: CorpusWordErrors]] = [:]
        var records: [[String: Any]] = []
        // -24 dB relative to each real source clip, with and without controlled
        // room noise. No artificial initial silence calibrates the filter.
        let quietGain: Float = 0.0630957344
        for mode in [SpeechNoiseReduction.off, .gentle] {
            let recognizer = CoreMLParakeetRecognizer(files: model.files, noiseReduction: mode)
            do {
                try await recognizer.load()
                var modeTotals: [String: CorpusWordErrors] = [:]
                for clip in corpus.manifest.clips {
                    let clean = try corpus.decode(clip)
                    let noisy = try corpusNoise(clean, sourceSHA256: clip.sha256)
                    for (condition, source) in [("quiet", clean), ("quietNoise15dB", noisy.samples)] {
                        let samples = source.map { $0 * quietGain }
                        try await recognizer.start(epochID: UUID())
                        let started = ContinuousClock.now
                        var text: [String] = []
                        for offset in stride(from: 0, to: samples.count, by: 3_200) {
                            let output = try await recognizer.accept(
                                Array(samples[offset..<min(offset + 3_200, samples.count)]), at: Int64(offset))
                            text += output.finalized.map(\.text)
                            for segment in output.finalized {
                                XCTAssertGreaterThanOrEqual(segment.startSample, 0)
                                XCTAssertLessThanOrEqual(segment.endSample, Int64(samples.count))
                            }
                        }
                        let tail = try await recognizer.finish()
                        text += tail.finalized.map(\.text)
                        for segment in tail.finalized {
                            XCTAssertGreaterThanOrEqual(segment.startSample, 0)
                            XCTAssertLessThanOrEqual(segment.endSample, Int64(samples.count))
                        }
                        let snapshot = await recognizer.snapshot()
                        XCTAssertEqual(snapshot.acceptedSampleCount, Int64(samples.count))
                        let hypothesis = corpusWords(text.joined(separator: " "))
                        XCTAssertFalse(hypothesis.isEmpty, "Quiet real speech must not disappear: \(clip.id)/\(mode)/\(condition)")
                        guard hypothesis.count <= 4_096 else { throw CorpusQualityError.invalidHypothesis }
                        let errors = corpusWordErrors(corpusWords(clip.text), hypothesis)
                        modeTotals[condition, default: .init()].add(errors)
                        let elapsed = started.duration(to: .now)
                        let record: [String: Any] = ["clip": clip.id, "condition": condition,
                            "noiseReduction": mode.rawValue, "modelRevision": model.files.revision,
                            "runtimeVersion": model.files.runtimeVersion, "sourceSHA256": clip.sha256,
                            "inputFloat32LESHA256": corpusFloatDigest(samples), "inputGainDB": -24,
                            "sampleFrames": samples.count, "referenceWords": errors.referenceWords,
                            "substitutions": errors.substitutions, "deletions": errors.deletions,
                            "insertions": errors.insertions, "wer": errors.wer,
                            "elapsedSeconds": Double(elapsed.components.seconds)
                                + Double(elapsed.components.attoseconds) / 1e18]
                        records.append(record)
                        try corpusLog("ASR_QUIET_COMPARISON", record)
                    }
                }
                totals[mode.rawValue] = modeTotals
                await recognizer.unload()
            } catch { await recognizer.unload(); throw error }
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: corpus.directory.appendingPathComponent("parakeet-quiet-noise-comparison.json"), options: .atomic)
        for (condition, ceiling) in [("quiet", 0.15), ("quietNoise15dB", 0.25)] {
            let baseline = try XCTUnwrap(totals[SpeechNoiseReduction.off.rawValue]?[condition])
            let enhanced = try XCTUnwrap(totals[SpeechNoiseReduction.gentle.rawValue]?[condition])
            XCTAssertEqual(baseline.referenceWords, 116)
            XCTAssertEqual(enhanced.referenceWords, baseline.referenceWords)
            XCTAssertLessThanOrEqual(enhanced.wer, ceiling)
            XCTAssertLessThanOrEqual(enhanced.distance, baseline.distance + 2,
                "Noise reduction must stay within two word errors of the unfiltered 116-word corpus")
            // Prefer preserving soft words over a cleaner-sounding signal.
            XCTAssertLessThanOrEqual(enhanced.deletions, baseline.deletions + 1)
        }
    }

    private func evaluate(engine: String, modelRevision: String, runtimeVersion: String,
                          recognize: @MainActor ([Float]) async throws -> String) async throws {
        let fixture = try ASRQualityCorpus.load()
        var totals = ["clean": CorpusWordErrors(), "noise15dB": CorpusWordErrors()]
        var records: [[String: Any]] = []
        for clip in fixture.manifest.clips {
            let clean = try fixture.decode(clip)
            let noisy = try corpusNoise(clean, sourceSHA256: clip.sha256)
            for (condition, samples) in [("clean", clean), ("noise15dB", noisy.samples)] {
                let started = ContinuousClock.now
                let hypothesis = corpusWords(try await recognize(samples))
                let elapsed = started.duration(to: .now)
                let reference = corpusWords(clip.text)
                XCTAssertFalse(hypothesis.isEmpty, "Actual inference must produce speech for \(clip.id)/\(condition)")
                guard hypothesis.count <= 4_096 else { throw CorpusQualityError.invalidHypothesis }
                let errors = corpusWordErrors(reference, hypothesis)
                totals[condition, default: .init()].add(errors)
                var record: [String: Any] = ["engine": engine, "clip": clip.id, "condition": condition,
                    "modelRevision": modelRevision, "runtimeVersion": runtimeVersion,
                    "sourceSHA256": clip.sha256, "referenceWords": errors.referenceWords,
                    "substitutions": errors.substitutions, "deletions": errors.deletions,
                    "insertions": errors.insertions, "wer": errors.wer,
                    "sampleFrames": samples.count, "elapsedSeconds": Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18,
                    "decodedFloat32LESHA256": corpusFloatDigest(samples)]
                if condition == "noise15dB" {
                    record["noiseSeedHex"] = noisy.seedHex
                    record["noiseAlgorithm"] = "LCG64-uniform-v1; full-clip-RMS15dB; common-peak-gain0.99; Float32LE"
                    record["requestedSNRdB"] = 15
                    record["commonPeakGain"] = noisy.peakGain
                    record["measuredSNRdB"] = noisy.measuredSNRdB
                }
                records.append(record)
                try corpusLog("ASR_CORPUS_CLIP", record)
            }
        }
        for (condition, ceiling) in [("clean", 0.15), ("noise15dB", 0.25)] {
            let total = try XCTUnwrap(totals[condition])
            XCTAssertEqual(total.referenceWords, 116)
            try corpusLog("ASR_CORPUS_TOTAL", ["engine": engine, "condition": condition,
                "referenceWords": total.referenceWords, "substitutions": total.substitutions,
                "deletions": total.deletions, "insertions": total.insertions,
                "wer": total.wer, "maximumWER": ceiling])
        }
        // Persist observed derivation hashes before quality assertions so an
        // honest quality failure still retains every completed observation.
        let data = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: fixture.directory.appendingPathComponent(engine + "-evaluation.json"), options: .atomic)
        XCTAssertLessThanOrEqual(try XCTUnwrap(totals["clean"]).wer, 0.15,
            "Fixed clean corpus target; do not normalize or remove recognition errors")
        XCTAssertLessThanOrEqual(try XCTUnwrap(totals["noise15dB"]).wer, 0.25,
            "Controlled-noise target; this does not establish representative meeting or owner-accent quality")
    }
}

private enum CorpusQualityError: Error { case invalidManifest, invalidAudio, invalidHypothesis }
private struct ASRQualityCorpusManifest: Decodable {
    let dataset: String
    let datasetRevision: String
    let config: String
    let split: String
    let publisher: String
    let license: String
    let clips: [Clip]
    struct Clip: Decodable {
        let id: String
        let text: String
        let bytes: Int
        let sha256: String
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
        let sampleFrames: Int
    }
}

private struct ASRQualityCorpus {
    let directory: URL
    let manifest: ASRQualityCorpusManifest

    static func load() throws -> Self {
        let manifestURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/ASRQualityCorpus.json")
        let manifest = try JSONDecoder().decode(ASRQualityCorpusManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.dataset == "openslr/librispeech_asr",
              manifest.datasetRevision == "71cacbfb7e2354c4226d01e70d77d5fca3d04ba1",
              manifest.config == "all", manifest.split == "test.clean",
              manifest.license == "CC-BY-4.0", manifest.publisher == "https://www.openslr.org/12/",
              manifest.clips.count == 3, Set(manifest.clips.map(\.id)).count == 3,
              manifest.clips.map(\.sampleFrames).reduce(0, +) == 733_600,
              manifest.clips.allSatisfy({ $0.sampleRate == 16_000 && $0.channels == 1 && $0.bitsPerSample == 16
                  && $0.sampleFrames > 0 && $0.sampleFrames < 320_000
                  && $0.id.range(of: "^[0-9]+-[0-9]+-[0-9]+$", options: .regularExpression) != nil }) else {
            throw CorpusQualityError.invalidManifest
        }
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_ASR_CORPUS_DIRECTORY"])
        guard path.hasPrefix("/") else { throw CorpusQualityError.invalidManifest }
        return Self(directory: URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath(), manifest: manifest)
    }

    func decode(_ clip: ASRQualityCorpusManifest.Clip) throws -> [Float] {
        let url = directory.appendingPathComponent(clip.id + ".flac")
        guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else {
            throw CorpusQualityError.invalidAudio
        }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == clip.bytes, corpusDigest(bytes) == clip.sha256 else { throw CorpusQualityError.invalidAudio }
        let audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
              audio.length == Int64(clip.sampleFrames),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat,
                                            frameCapacity: AVAudioFrameCount(clip.sampleFrames)) else {
            throw CorpusQualityError.invalidAudio
        }
        try audio.read(into: buffer)
        guard Int(buffer.frameLength) == clip.sampleFrames, let plane = buffer.floatChannelData?.pointee else {
            throw CorpusQualityError.invalidAudio
        }
        let samples = Array(UnsafeBufferPointer(start: plane, count: clip.sampleFrames))
        guard samples.allSatisfy({ $0.isFinite && abs($0) <= 1 }) else { throw CorpusQualityError.invalidAudio }
        return samples
    }
}

/// Declared scoring: Unicode lowercase, split at every non-letter/non-number;
/// no stemming, number replacement, synonym mapping, or hypothesis cleanup.
private func corpusWords(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
}

private struct CorpusWordErrors {
    var substitutions = 0
    var deletions = 0
    var insertions = 0
    var referenceWords = 0
    var distance: Int { substitutions + deletions + insertions }
    var wer: Double { Double(distance) / Double(max(1, referenceWords)) }
    mutating func add(_ other: Self) {
        substitutions += other.substitutions; deletions += other.deletions
        insertions += other.insertions; referenceWords += other.referenceWords
    }
}

/// Full-reference Levenshtein; equal-cost paths prefer substitution, deletion,
/// insertion in that order. Counts explain the same minimum edit distance.
private func corpusWordErrors(_ reference: [String], _ hypothesis: [String]) -> CorpusWordErrors {
    var previous = (0...hypothesis.count).map { CorpusWordErrors(insertions: $0) }
    for (row, word) in reference.enumerated() {
        var current = [CorpusWordErrors(deletions: row + 1)]
        for (column, recognized) in hypothesis.enumerated() {
            if word == recognized { current.append(previous[column]); continue }
            var substitution = previous[column]; substitution.substitutions += 1
            var deletion = previous[column + 1]; deletion.deletions += 1
            var insertion = current[column]; insertion.insertions += 1
            var best = substitution
            for candidate in [deletion, insertion] where candidate.distance < best.distance { best = candidate }
            current.append(best)
        }
        previous = current
    }
    var result = previous[hypothesis.count]
    result.referenceWords = reference.count
    return result
}

private struct CorpusNoisySamples {
    let samples: [Float]
    let seedHex: String
    let peakGain: Double
    let measuredSNRdB: Double
}

private func corpusNoise(_ clean: [Float], sourceSHA256: String) throws -> CorpusNoisySamples {
    guard let seed = UInt64(sourceSHA256.prefix(16), radix: 16), !clean.isEmpty else { throw CorpusQualityError.invalidAudio }
    var state = seed
    let noise = clean.map { _ -> Double in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 32) / 4_294_967_296 * 2 - 1
    }
    let signalEnergy = clean.reduce(0.0) { $0 + Double($1) * Double($1) }
    let noiseEnergy = noise.reduce(0.0) { $0 + $1 * $1 }
    guard signalEnergy > 0, noiseEnergy > 0 else { throw CorpusQualityError.invalidAudio }
    let scale = sqrt(signalEnergy / noiseEnergy) / pow(10, 15.0 / 20)
    let mixed = zip(clean, noise).map { Double($0.0) + $0.1 * scale }
    let peak = mixed.reduce(0.0) { max($0, abs($1)) }
    let gain = peak > 0.99 ? 0.99 / peak : 1
    let samples = mixed.map { Float($0 * gain) }
    let resultingNoiseEnergy = zip(samples, clean).reduce(0.0) { value, pair in
        let difference = Double(pair.0) - Double(pair.1) * gain
        return value + difference * difference
    }
    return CorpusNoisySamples(samples: samples, seedHex: String(format: "%016llx", seed), peakGain: gain,
        measuredSNRdB: 10 * log10(signalEnergy * gain * gain / resultingNoiseEnergy))
}

private func corpusDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
private func corpusFloatDigest(_ samples: [Float]) -> String {
    var bytes = Data(capacity: samples.count * 4)
    for sample in samples {
        var littleEndian = sample.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
    }
    return corpusDigest(bytes)
}
private func corpusLog(_ prefix: String, _ record: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    try FileHandle.standardOutput.write(contentsOf: Data((prefix + " " + String(decoding: data, as: UTF8.self) + "\n").utf8))
}

final class ASRCorpusScoringTests: XCTestCase {
    func testDeclaredNormalizationAndFullReferenceEditCountsIncludeEveryError() {
        XCTAssertEqual(corpusWords("Café, API-v2: DON'T 42000."), ["café", "api", "v2", "don", "t", "42000"])
        let errors = corpusWordErrors(corpusWords("one two three four"), corpusWords("one wrong three extra four tail"))
        XCTAssertEqual(errors.substitutions, 1); XCTAssertEqual(errors.deletions, 0)
        XCTAssertEqual(errors.insertions, 2); XCTAssertEqual(errors.referenceWords, 4)
        XCTAssertEqual(errors.wer, 0.75)
        let missing = corpusWordErrors(corpusWords("one two three"), [])
        XCTAssertEqual(missing.deletions, 3); XCTAssertEqual(missing.wer, 1)
    }

    func testNoiseRecipeIsDeterministicBoundedAndActuallyFifteenDecibels() throws {
        let clean = (0..<1_600).map { Float(sin(Double($0) * 0.1) * 0.9) }
        let first = try corpusNoise(clean, sourceSHA256: String(repeating: "a", count: 64))
        let repeated = try corpusNoise(clean, sourceSHA256: String(repeating: "a", count: 64))
        let other = try corpusNoise(clean, sourceSHA256: String(repeating: "b", count: 64))
        XCTAssertEqual(first.samples, repeated.samples)
        XCTAssertEqual(corpusFloatDigest(first.samples), corpusFloatDigest(repeated.samples))
        XCTAssertNotEqual(corpusFloatDigest(first.samples), corpusFloatDigest(other.samples))
        XCTAssertTrue(first.samples.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertEqual(first.measuredSNRdB, 15, accuracy: 0.001)
        XCTAssertEqual(first.samples.count, clean.count)
    }
}
