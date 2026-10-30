import Foundation
import XCTest
@testable import LocalMinutesTranscription

final class GentleSpeechDenoiserTests: XCTestCase {
    func testSilenceStaysSilentAndEveryTailKeepsItsOriginalSampleCount() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        for count in [0, 1, 255, 256, 511, 512, 513, 3_201, 79_999, 80_000] {
            filter.reset()
            let silence = [Float](repeating: 0, count: count)
            XCTAssertEqual(try filter.process(silence), silence)
        }
    }

    func testSteadyNoiseIsReducedGentlyWithoutMutingOrBoostingIt() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        let noise = DenoiserSignal.noise(count: 80_000, amplitude: 0.012)
        let original = noise
        let result = try filter.process(noise)
        let inputRMS = DenoiserSignal.rms(Array(noise.suffix(48_000)))
        let outputRMS = DenoiserSignal.rms(Array(result.suffix(48_000)))
        XCTAssertLessThan(outputRMS, inputRMS * 0.98)
        XCTAssertGreaterThanOrEqual(outputRMS, inputRMS * 0.70)
        XCTAssertEqual(noise, original, "The source PCM must never be edited in place")
        XCTAssertEqual(result.count, noise.count)
        XCTAssertTrue(result.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    func testSpeechFromFirstSampleIsNotTreatedAsAnInitialSilenceCalibration() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        // Quiet voiced harmonics plus short, much softer high-frequency bursts
        // stand in for the acoustic details that a hard noise gate would erase.
        let speech = DenoiserSignal.softSpeech(count: 80_000)
        let result = try filter.process(speech)
        XCTAssertEqual(result.count, speech.count)
        for start in stride(from: 0, to: speech.count, by: 1_600) {
            let input = Array(speech[start..<(start + 1_600)])
            let output = Array(result[start..<(start + 1_600)])
            XCTAssertGreaterThan(DenoiserSignal.projection(output, onto: input), 0.69,
                "Quiet voiced and unvoiced details must not be gated away")
        }
    }

    func testSoftSpeechBelowRoomNoiseRetainsItsContributionAfterNoiseLearning() throws {
        let withSpeech = try XCTUnwrap(GentleSpeechDenoiser())
        let noiseOnly = try XCTUnwrap(GentleSpeechDenoiser())
        let background = DenoiserSignal.noise(count: 80_000, amplitude: 0.006)
        _ = try withSpeech.process(background)
        _ = try noiseOnly.process(background)
        let speech = DenoiserSignal.softSpeech(count: background.count)
        let mixed = zip(background, speech).map { $0.0 + $0.1 }
        let enhanced = try withSpeech.process(mixed)
        let enhancedNoise = try noiseOnly.process(background)
        let retainedSpeech = zip(enhanced, enhancedNoise).map { $0.0 - $0.1 }
        XCTAssertGreaterThan(DenoiserSignal.projection(retainedSpeech, onto: speech), 0.69)
        XCTAssertEqual(enhanced.count, mixed.count)
    }

    func testVerySoftUnvoicedBurstsAreNotRemovedBetweenPauses() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        let consonants: [Float] = (0..<80_000).map { index in
            guard index % 1_600 < 320 else { return 0 }
            return Float(0.00005 * sin(2 * Double.pi * 4_117 * Double(index) / 16_000))
        }
        let result = try filter.process(consonants)
        for start in stride(from: 0, to: consonants.count, by: 1_600) {
            let input = Array(consonants[start..<(start + 320)])
            let output = Array(result[start..<(start + 320)])
            XCTAssertGreaterThan(DenoiserSignal.projection(output, onto: input), 0.95)
        }
    }

    func testImpulsePositionsAndFinalSamplesDoNotMove() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        _ = try filter.process(DenoiserSignal.noise(count: 80_000, amplitude: 0.001))
        for position in [0, 1, 255, 256, 512, 2_001, 4_096] {
            var samples = [Float](repeating: 0, count: 4_097)
            samples[position] = 0.25
            let result = try filter.process(samples)
            let peak = try XCTUnwrap(result.indices.max { abs(result[$0]) < abs(result[$1]) })
            XCTAssertEqual(peak, position, "Enhancement must not offset original citation timestamps")
            XCTAssertGreaterThan(result[position], 0.17)
            XCTAssertEqual(result.count, samples.count)
        }
    }

    func testResetDoesNotCarryAnotherMeetingsNoiseProfile() throws {
        let reused = try XCTUnwrap(GentleSpeechDenoiser())
        let fresh = try XCTUnwrap(GentleSpeechDenoiser())
        _ = try reused.process(DenoiserSignal.noise(count: 80_000, amplitude: 0.1))
        reused.reset()
        let speech = DenoiserSignal.softSpeech(count: 16_001)
        XCTAssertEqual(try reused.process(speech), try fresh.process(speech))
    }

    func testLoudInputNeverClipsAndInvalidPCMIsRejected() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        let loud = (0..<16_000).map { Float(sin(2 * Double.pi * 997 * Double($0) / 16_000)) }
        let result = try filter.process(loud)
        XCTAssertEqual(result.count, loud.count)
        XCTAssertTrue(result.allSatisfy { $0.isFinite && abs($0) <= 1 })
        let invalidInputs: [[Float]] = [[.nan], [.infinity], [1.001], Array(repeating: 0, count: 80_001)]
        for invalid in invalidInputs {
            XCTAssertThrowsError(try filter.process(invalid)) {
                XCTAssertEqual($0 as? SpeechRecognitionError, .invalidSamples)
            }
        }
    }

    func testCancellationIsCheckedWithinEachShortAnalysisFrame() throws {
        let filter = try XCTUnwrap(GentleSpeechDenoiser())
        var checks = 0
        XCTAssertThrowsError(try filter.process([Float](repeating: 0.001, count: 80_000), isCancelled: {
            checks += 1
            return checks == 4
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(checks, 4)
    }
}

private enum DenoiserSignal {
    static func noise(count: Int, amplitude: Float) -> [Float] {
        var seed: UInt64 = 0x95c61e2da8
        return (0..<count).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Double(seed >> 32) / 4_294_967_296 * 2 - 1) * amplitude
        }
    }

    static func softSpeech(count: Int) -> [Float] {
        (0..<count).map { index in
            let t = Double(index) / 16_000
            let voiced = 0.0007 * sin(2 * Double.pi * 193 * t)
                + 0.00035 * sin(2 * Double.pi * 386 * t)
            let consonant = index % 1_600 < 320 ? 0.0002 * sin(2 * Double.pi * 4_117 * t) : 0
            return Float(voiced + consonant)
        }
    }

    static func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    static func projection(_ output: [Float], onto input: [Float]) -> Double {
        let energy = input.reduce(0.0) { $0 + Double($1) * Double($1) }
        return zip(output, input).reduce(0.0) { $0 + Double($1.0) * Double($1.1) } / energy
    }
}
