import AVFoundation
import Foundation

public enum SegmentWriterError: Error, Equatable {
    case notImplemented, invalidConfiguration, directoryNotEmpty, formatMismatch, finished, ioFailed
}

public struct StoredAudioSegment: Codable, Equatable, Sendable {
    public let relativePath: String
    public let startFrame: Int64
    public let frameCount: Int64
}

public struct AudioCaptureManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sessionID: UUID
    public let totalFrames: Int64
    public let segments: [StoredAudioSegment]
}

// Minimal T05.2 interface. Durable file behavior follows recorded native RED.
public final class SegmentCAFWriter {
    public init(directory: URL, sessionID: UUID, maximumSegmentFrames: Int64 = 960_000) throws {}

    public func append(_ buffer: AVAudioPCMBuffer) throws {
        throw SegmentWriterError.notImplemented
    }

    public func finish() throws -> AudioCaptureManifest {
        throw SegmentWriterError.notImplemented
    }
}
