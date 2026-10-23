import AVFoundation
import Foundation

public enum PCMConversionError: Error, Equatable {
    case unsupportedFormat, formatMismatch, finished, conversionFailed
}

/// Single conversion-worker ownership. Never call from the engine tap.
/// One converter lives for the entire fixed-format epoch; no per-chunk reset.
public final class PCMStreamConverter {
    public let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private let monoFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private var didFinish = false
    private var hasInput = false

    public init(inputFormat: AVAudioFormat) throws {
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
            guard let native = AVAudioConverter(from: mono, to: output) else {
                throw PCMConversionError.unsupportedFormat
            }
            native.primeMethod = .normal
            converter = native
        }
    }

    public func append(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
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
        return try convert(mono, ending: false)
    }

    public func finish() throws -> [AVAudioPCMBuffer] {
        guard !didFinish else { return [] }
        didFinish = true
        guard converter != nil, hasInput else { return [] }
        return try convert(nil, ending: true)
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
        var inputOffset = 0
        var outputs: [AVAudioPCMBuffer] = []
        for _ in 0..<limit {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                throw PCMConversionError.conversionFailed
            }
            var nativeError: NSError?
            var failedToSupply = false
            let status = converter.convert(to: output, error: &nativeError) { requested, state in
                guard let input, inputOffset < inputFrames else {
                    state.pointee = ending ? .endOfStream : .noDataNow
                    return nil
                }
                let count = min(Int(requested), inputFrames - inputOffset)
                guard count > 0,
                      let slice = AVAudioPCMBuffer(pcmFormat: self.monoFormat, frameCapacity: AVAudioFrameCount(count)),
                      let source = input.floatChannelData?[0],
                      let target = slice.floatChannelData?[0] else {
                    failedToSupply = true
                    state.pointee = .endOfStream
                    return nil
                }
                slice.frameLength = AVAudioFrameCount(count)
                target.update(from: source.advanced(by: inputOffset), count: count)
                inputOffset += count
                state.pointee = .haveData
                return slice
            }
            guard !failedToSupply, nativeError == nil else { throw PCMConversionError.conversionFailed }
            if output.frameLength > 0 { outputs.append(output) }
            switch status {
            case .haveData:
                guard output.frameLength > 0 else { throw PCMConversionError.conversionFailed }
            case .inputRanDry:
                guard !ending, inputOffset == inputFrames else { throw PCMConversionError.conversionFailed }
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
