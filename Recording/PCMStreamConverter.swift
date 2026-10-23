import AVFoundation

public enum PCMConversionError: Error, Equatable {
    case notImplemented, unsupportedFormat, formatMismatch, finished
}

// Minimal T05.2 interface. Real conversion follows recorded native RED.
public final class PCMStreamConverter {
    public let outputFormat: AVAudioFormat

    public init(inputFormat: AVAudioFormat) throws {
        outputFormat = inputFormat
    }

    public func append(_ input: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
        throw PCMConversionError.notImplemented
    }

    public func finish() throws -> [AVAudioPCMBuffer] {
        throw PCMConversionError.notImplemented
    }
}
