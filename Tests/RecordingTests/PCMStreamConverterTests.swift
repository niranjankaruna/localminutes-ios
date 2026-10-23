import AVFoundation
import Foundation
import XCTest
@testable import LocalMinutesRecording

// Only the SDK error boundary is doubled. All signal/format tests below use
// the public initializer and real AVAudioConverter, never this fault engine.
private final class FaultingPCMEngine: PCMConversionEngine {
    let failAppend: Bool
    var calls = 0
    var endCalls = 0
    init(failAppend: Bool = false) { self.failAppend = failAppend }

    func convert(into output: AVAudioPCMBuffer, input: @escaping AVAudioConverterInputBlock) throws -> AVAudioConverterOutputStatus {
        calls += 1
        var state = AVAudioConverterInputStatus.noDataNow
        _ = input(4_096, &state)
        if state == .endOfStream {
            endCalls += 1
            throw PCMConversionError.conversionFailed
        }
        if failAppend { throw PCMConversionError.conversionFailed }
        while state == .haveData { _ = input(4_096, &state) }
        output.frameLength = 0
        return .inputRanDry
    }
}

final class PCMStreamConverterTests: XCTestCase {
    func testFailedNativeDrainRemainsAnExplicitTerminalFailure() throws {
        let input = signal(rate: 48_000, frames: 256) { _, _ in 0.2 }
        let engine = FaultingPCMEngine()
        let converter = try PCMStreamConverter(inputFormat: input.format, engineFactory: { _, _ in engine })
        _ = try converter.append(input)
        for _ in 0..<3 {
            XCTAssertThrowsError(try converter.finish()) {
                XCTAssertEqual($0 as? PCMConversionError, .conversionFailed, "A failed tail cannot become an empty success")
            }
        }
        XCTAssertThrowsError(try converter.append(input)) {
            XCTAssertEqual($0 as? PCMConversionError, .conversionFailed)
        }
        XCTAssertEqual(engine.calls, 2, "A failed native stream must not be entered again")
        XCTAssertEqual(engine.endCalls, 1)
    }

    func testNativeAppendFailureCannotBeFinishedAsSuccessOrReentered() throws {
        let input = signal(rate: 48_000, frames: 256) { _, _ in 0.2 }
        let engine = FaultingPCMEngine(failAppend: true)
        let converter = try PCMStreamConverter(inputFormat: input.format, engineFactory: { _, _ in engine })
        for _ in 0..<2 {
            XCTAssertThrowsError(try converter.append(input)) { XCTAssertEqual($0 as? PCMConversionError, .conversionFailed) }
        }
        for _ in 0..<2 {
            XCTAssertThrowsError(try converter.finish()) { XCTAssertEqual($0 as? PCMConversionError, .conversionFailed) }
        }
        XCTAssertEqual(engine.calls, 1)
    }

    func testRealConversionProduces16kMonoAndPreservesDuration() throws {
        for rate in [8_000.0, 44_100.0, 48_000.0] {
            let input = signal(rate: rate, channels: 2, frames: Int(rate)) { frame, _ in
                Float(0.4 * sin(2 * .pi * 500 * Double(frame) / rate))
            }
            let converter = try PCMStreamConverter(inputFormat: input.format)
            let outputs = try converter.append(input) + converter.finish()
            for output in outputs {
                XCTAssertEqual(output.format.sampleRate, 16_000)
                XCTAssertEqual(output.format.channelCount, 1)
                XCTAssertEqual(output.format.commonFormat, .pcmFormatFloat32)
            }
            let samples = monoSamples(outputs)
            XCTAssertEqual(Double(samples.count), 16_000, accuracy: 2, "Conversion must preserve one second")
            let interior = samples.dropFirst(64).dropLast(64)
            XCTAssertFalse(interior.isEmpty)
            let energy = interior.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(interior.count, 1))
            XCTAssertEqual(sqrt(energy), 0.4 / sqrt(2), accuracy: 0.015, "Actual converted signal energy must survive")
        }
    }

    func testStereoDownmixUsesBothChannels() throws {
        let input = signal(rate: 48_000, channels: 2, frames: 4_800) { _, channel in channel == 0 ? 0.35 : -0.35 }
        let converter = try PCMStreamConverter(inputFormat: input.format)
        let output = monoSamples(try converter.append(input) + converter.finish())
        XCTAssertGreaterThan(output.count, 1_500)
        XCTAssertLessThan(output.map { abs($0) }.max() ?? 1, 0.001, "Opposite channels must cancel rather than selecting one")
    }

    func testChunkedConversionMatchesContinuousStreamWithoutBoundaryResets() throws {
        let rate = 44_100.0
        let tone: (Int, Int) -> Float = { frame, _ in Float(0.3 * sin(2 * .pi * 700 * Double(frame) / rate)) }
        let whole = signal(rate: rate, frames: 44_100, value: tone)
        let reference = try PCMStreamConverter(inputFormat: whole.format)
        let expected = monoSamples(try reference.append(whole) + reference.finish())
        let chunked = try PCMStreamConverter(inputFormat: whole.format)
        var actual: [Float] = []
        var position = 0
        while position < 44_100 {
            let length = min(1_024, 44_100 - position)
            actual += monoSamples(try chunked.append(signal(rate: rate, frames: length, startFrame: position, value: tone)))
            position += length
        }
        actual += monoSamples(try chunked.finish())
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertGreaterThan(actual.count, 15_900)
        let count = min(actual.count, expected.count)
        if count > 128 {
            let error = (64..<(count - 64)).reduce(0.0) { sum, index in
                let delta = Double(actual[index] - expected[index]); return sum + delta * delta
            }
            XCTAssertLessThan(sqrt(error / Double(count - 128)), 0.0005)
        }
    }

    func testEmptyAndFinishedConversionDoNotRepeatTail() throws {
        let input = signal(rate: 16_000, frames: 256) { _, _ in 0.25 }
        let converter = try PCMStreamConverter(inputFormat: input.format)
        XCTAssertTrue(try converter.append(signal(rate: 16_000, frames: 0) { _, _ in 0 }).isEmpty)
        let output = monoSamples(try converter.append(input) + converter.finish())
        XCTAssertEqual(output.count, 256)
        XCTAssertTrue(try converter.finish().isEmpty)
        XCTAssertThrowsError(try converter.append(input)) { XCTAssertEqual($0 as? PCMConversionError, .finished) }
    }

    func testRejectsFormatChangesBeforeConsumingInput() throws {
        let format = signal(rate: 48_000, channels: 2, frames: 1) { _, _ in 0 }.format
        let converter = try PCMStreamConverter(inputFormat: format)
        let wrong = signal(rate: 16_000, frames: 100) { _, _ in 0 }
        XCTAssertThrowsError(try converter.append(wrong)) { XCTAssertEqual($0 as? PCMConversionError, .formatMismatch) }
    }
}
