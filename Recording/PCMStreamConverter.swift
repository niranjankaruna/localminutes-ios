import AVFoundation
import Foundation

public enum PCMConversionError: Error, Equatable {
    case unsupportedFormat, formatMismatch, finished, conversionFailed
}

/// Native conversion boundary. Fault tests can exercise SDK error handling;
/// the public initializer always constructs the real AVFoundation engine.
protocol PCMConversionEngine: AnyObject {
    func convert(into output: AVAudioPCMBuffer, input: @escaping AVAudioConverterInputBlock) throws -> AVAudioConverterOutputStatus
}

private final class AVFoundationPCMConversionEngine: PCMConversionEngine {
    private let converter: AVAudioConverter

    init(input: AVAudioFormat, output: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw PCMConversionError.unsupportedFormat
        }
        converter.primeMethod = .normal
        self.converter = converter
    }

    func convert(into output: AVAudioPCMBuffer, input: @escaping AVAudioConverterInputBlock) throws -> AVAudioConverterOutputStatus {
        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: input)
        guard error == nil, status != .error else { throw PCMConversionError.conversionFailed }
        return status
    }
}

/// AVFoundation marks its input block Sendable. The block may outlive its
/// lexical scope, so it owns an immutable PCM buffer and a protected cursor.
/// Every SDK access and snapshot uses this lock. This is conversion-worker
/// work, never the real-time microphone tap or OwnedPCMQueue producer.
private final class PCMConversionInputCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let input: AVAudioPCMBuffer?
    private let format: AVAudioFormat
    private let ending: Bool
    private var offset = 0
    private var failed = false

    init(input: AVAudioPCMBuffer?, format: AVAudioFormat, ending: Bool) {
        self.input = input
        self.format = format
        self.ending = ending
    }

    func supply(_ requested: AVAudioPacketCount,
                status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let input, offset < Int(input.frameLength) else {
            status.pointee = ending ? .endOfStream : .noDataNow
            return nil
        }
        let count = min(Int(requested), Int(input.frameLength) - offset)
        guard count > 0,
              let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let source = input.floatChannelData?[0],
              let target = slice.floatChannelData?[0] else {
            failed = true
            status.pointee = .endOfStream
            return nil
        }
        slice.frameLength = AVAudioFrameCount(count)
        target.update(from: source.advanced(by: offset), count: count)
        offset += count
        status.pointee = .haveData
        return slice
    }

    func snapshot() -> (consumed: Bool, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (offset == Int(input?.frameLength ?? 0), failed)
    }
}

/// Single conversion-worker ownership. Never call from the engine tap.
/// One converter lives for the entire fixed-format epoch; no per-chunk reset.
public final class PCMStreamConverter {
    public let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private let monoFormat: AVAudioFormat
    private let converter: (any PCMConversionEngine)?
    private var didFinish = false
    private var hasInput = false
    private var failed = false

    public convenience init(inputFormat: AVAudioFormat) throws {
        try self.init(inputFormat: inputFormat, engineFactory: { input, output in
            try AVFoundationPCMConversionEngine(input: input, output: output)
        })
    }

    init(inputFormat: AVAudioFormat,
         engineFactory: (AVAudioFormat, AVAudioFormat) throws -> any PCMConversionEngine) throws {
        guard inputFormat.commonFormat == .pcmFormatFloat32,
              !inputFormat.isInterleaved, inputFormat.channelCount > 0,
              inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1),
              let output = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw PCMConversionError.unsupportedFormat
        }
        self.inputFormat = inputFormat
        monoFormat = mono
        outputFormat = output
        if inputFormat.sampleRate == output.sampleRate {
            converter = nil
        } else {
            converter = try engineFactory(mono, output)
        }
    }

    public func append(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
        guard !failed else { throw PCMConversionError.conversionFailed }
        guard !didFinish else { throw PCMConversionError.finished }
        guard input.format == inputFormat else { throw PCMConversionError.formatMismatch }
        guard input.frameLength > 0 else { return [] }
        guard let channels = input.floatChannelData,
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: input.frameLength),
              let destination = mono.floatChannelData?[0] else {
            throw PCMConversionError.conversionFailed
        }
        mono.frameLength = input.frameLength
        let channelCount = Int(inputFormat.channelCount)
        for frame in 0..<Int(input.frameLength) {
            var sum: Double = 0
            for channel in 0..<channelCount { sum += Double(channels[channel][frame]) }
            destination[frame] = Float(sum / Double(channelCount))
        }
        hasInput = true
        if converter == nil { return [mono] }
        do { return try convert(mono, ending: false) }
        catch {
            failed = true
            throw PCMConversionError.conversionFailed
        }
    }

    public func finish() throws -> [AVAudioPCMBuffer] {
        guard !failed else { throw PCMConversionError.conversionFailed }
        guard !didFinish else { return [] }
        guard converter != nil, hasInput else {
            didFinish = true
            return []
        }
        do {
            let tail = try convert(nil, ending: true)
            didFinish = true
            return tail
        } catch {
            failed = true
            throw PCMConversionError.conversionFailed
        }
    }

    private func convert(_ input: AVAudioPCMBuffer?, ending: Bool) throws -> [AVAudioPCMBuffer] {
        guard let converter else { return [] }
        let inputFrames = Int(input?.frameLength ?? 0)
        let estimate = Double(inputFrames) * outputFormat.sampleRate / inputFormat.sampleRate
        guard estimate.isFinite, estimate < Double(Int.max / 2) else {
            throw PCMConversionError.conversionFailed
        }
        // Bounded SDK progress, including prime/tail output. A stalled native
        // converter becomes an explicit error rather than an infinite worker.
        let limit = Int(ceil(estimate / 4_096)) + 8
        let cursor = PCMConversionInputCursor(input: input, format: monoFormat, ending: ending)
        var outputs: [AVAudioPCMBuffer] = []
        for _ in 0..<limit {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                throw PCMConversionError.conversionFailed
            }
            let status = try converter.convert(into: output) { [cursor] requested, state in
                cursor.supply(requested, status: state)
            }
            let supplied = cursor.snapshot()
            guard !supplied.failed else { throw PCMConversionError.conversionFailed }
            if output.frameLength > 0 { outputs.append(output) }
            switch status {
            case .haveData:
                guard output.frameLength > 0 else { throw PCMConversionError.conversionFailed }
            case .inputRanDry:
                guard !ending, supplied.consumed else { throw PCMConversionError.conversionFailed }
                return outputs
            case .endOfStream:
                guard ending else { throw PCMConversionError.conversionFailed }
                return outputs
            case .error:
                throw PCMConversionError.conversionFailed
            @unknown default:
                throw PCMConversionError.conversionFailed
            }
        }
        throw PCMConversionError.conversionFailed
    }
}
