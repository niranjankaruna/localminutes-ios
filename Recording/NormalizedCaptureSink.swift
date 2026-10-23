import AVFoundation

/// Called synchronously only on the conversion worker, after durable append.
/// Implementations copy into bounded owned storage; they never retain the buffer
/// or execute inference here. False means the live pipeline cannot keep up.
public protocol NormalizedCaptureSink: AnyObject, Sendable {
    func offer(_ buffer: AVAudioPCMBuffer, sourceStartSample: Int64) -> Bool
}
