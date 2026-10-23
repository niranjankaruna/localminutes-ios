import AVFoundation
import Foundation
import XCTest

// Original generated signals only; no recordings, speech or confidential data.
func signal(rate: Double, channels: UInt32 = 1, frames: Int, startFrame: Int = 0,
            value: (Int, Int) -> Float) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                               channels: channels, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frames, 1)))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for channel in 0..<Int(channels) {
        for frame in 0..<frames { buffer.floatChannelData![channel][frame] = value(startFrame + frame, channel) }
    }
    return buffer
}

func monoSamples(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
    buffers.flatMap { buffer in
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

func withAudioDirectory(_ body: (URL) throws -> Void) throws {
    let parent = FileManager.default.temporaryDirectory.standardizedFileURL
    let root = parent.appendingPathComponent("localminutes-audio-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        if root.deletingLastPathComponent().standardizedFileURL == parent && root.lastPathComponent.hasPrefix("localminutes-audio-test-") {
            do { try FileManager.default.removeItem(at: root) }
            catch { XCTFail("Owned audio fixture cleanup failed") }
        } else { XCTFail("Unsafe audio fixture cleanup target") }
    }
    try body(root)
}
