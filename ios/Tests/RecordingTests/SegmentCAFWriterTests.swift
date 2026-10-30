import AVFoundation
import AudioToolbox
import Foundation
import XCTest
@testable import LocalMinutesRecording

final class SegmentCAFWriterTests: XCTestCase {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    func testRealCAFSegmentsContain16BitMonoSamplesAndPersistManifest() throws {
        try withAudioDirectory { root in
            let directory = root.appendingPathComponent("meeting", isDirectory: true)
            let writer = try SegmentCAFWriter(directory: directory, sessionID: sessionID, maximumSegmentFrames: 160)
            let input = signal(rate: 16_000, frames: 450) { frame, _ in Float(frame % 100) / 200 - 0.25 }
            try writer.append(input)
            let manifest = try writer.finish()
            XCTAssertEqual(manifest.schemaVersion, 1)
            XCTAssertEqual(manifest.sessionID, sessionID)
            XCTAssertEqual(manifest.totalFrames, 450)
            XCTAssertEqual(manifest.segments.map(\.frameCount), [160, 160, 130])
            XCTAssertEqual(manifest.segments.map(\.startFrame), [0, 160, 320])
            var samples: [Float] = []
            for segment in manifest.segments {
                XCTAssertFalse(segment.relativePath.hasPrefix("/"))
                XCTAssertFalse(segment.relativePath.contains(".."))
                XCTAssertTrue(segment.relativePath.hasSuffix(".caf"))
                let file = try AVAudioFile(forReading: directory.appendingPathComponent(segment.relativePath))
                XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
                XCTAssertEqual(file.fileFormat.channelCount, 1)
                XCTAssertEqual((file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value, kAudioFormatLinearPCM)
                XCTAssertEqual((file.fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue, 16)
                XCTAssertEqual(file.length, segment.frameCount)
                let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: decoded)
                samples += monoSamples([decoded])
            }
            XCTAssertEqual(samples.count, 450)
            for (index, sample) in samples.prefix(Int(input.frameLength)).enumerated() {
                XCTAssertEqual(sample, input.floatChannelData![0][index], accuracy: 0.0002)
            }
            let persisted = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json")))
            XCTAssertEqual(persisted, manifest)
        }
    }

    func testAppendBoundariesDoNotDuplicateSamplesAndFinishIsIdempotent() throws {
        try withAudioDirectory { root in
            let writer = try SegmentCAFWriter(directory: root.appendingPathComponent("meeting"), sessionID: sessionID, maximumSegmentFrames: 4)
            try writer.append(signal(rate: 16_000, frames: 3) { _, _ in 0.2 })
            try writer.append(signal(rate: 16_000, frames: 5) { _, _ in -0.2 })
            let manifest = try writer.finish()
            XCTAssertEqual(manifest.totalFrames, 8)
            XCTAssertEqual(manifest.segments.map(\.frameCount), [4, 4])
            var samples: [Float] = []
            for segment in manifest.segments {
                let file = try AVAudioFile(forReading: root.appendingPathComponent("meeting").appendingPathComponent(segment.relativePath))
                let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: decoded)
                samples += monoSamples([decoded])
            }
            let expected: [Float] = [0.2, 0.2, 0.2, -0.2, -0.2, -0.2, -0.2, -0.2]
            XCTAssertEqual(samples.count, expected.count)
            for (actual, intended) in zip(samples, expected) {
                XCTAssertEqual(actual, intended, accuracy: 0.0002)
            }
            XCTAssertEqual(try writer.finish(), manifest)
            XCTAssertThrowsError(try writer.append(signal(rate: 16_000, frames: 1) { _, _ in 0 })) {
                XCTAssertEqual($0 as? SegmentWriterError, .finished)
            }
        }
    }

    func testEmptyWriterProducesNoPhantomAudioSegment() throws {
        try withAudioDirectory { root in
            let writer = try SegmentCAFWriter(directory: root.appendingPathComponent("meeting"), sessionID: sessionID)
            try writer.append(signal(rate: 16_000, frames: 0) { _, _ in 0 })
            let manifest = try writer.finish()
            XCTAssertEqual(manifest.totalFrames, 0)
            XCTAssertTrue(manifest.segments.isEmpty)
        }
    }

    func testCompletedSegmentIsReadableAndCheckpointedBeforeFinish() throws {
        try withAudioDirectory { root in
            let directory = root.appendingPathComponent("meeting")
            let writer = try SegmentCAFWriter(directory: directory, sessionID: sessionID, maximumSegmentFrames: 4)
            try writer.append(signal(rate: 16_000, frames: 6) { frame, _ in Float(frame) / 10 })
            let checkpoint = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json")))
            XCTAssertEqual(checkpoint.totalFrames, 4, "Only closed durable segments belong in a recording checkpoint")
            XCTAssertEqual(checkpoint.segments.map(\.frameCount), [4])
            if let segment = checkpoint.segments.first {
                let file = try AVAudioFile(forReading: directory.appendingPathComponent(segment.relativePath))
                XCTAssertEqual(file.length, 4)
                let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4)!
                try file.read(into: decoded)
                let actual = monoSamples([decoded])
                XCTAssertEqual(actual.count, 4)
                for (sample, expected) in zip(actual, [Float(0), 0.1, 0.2, 0.3]) {
                    XCTAssertEqual(sample, expected, accuracy: 0.0002)
                }
            }
            let final = try writer.finish()
            XCTAssertEqual(final.totalFrames, 6)
            XCTAssertEqual(final.segments.map(\.frameCount), [4, 2])
        }
    }

    func testRejectsWrongFormatWithoutWritingFrames() throws {
        try withAudioDirectory { root in
            let writer = try SegmentCAFWriter(directory: root.appendingPathComponent("meeting"), sessionID: sessionID)
            XCTAssertThrowsError(try writer.append(signal(rate: 48_000, channels: 2, frames: 10) { _, _ in 0 })) {
                XCTAssertEqual($0 as? SegmentWriterError, .formatMismatch)
            }
            XCTAssertEqual(try writer.finish().totalFrames, 0)
        }
    }

    func testRejectsInvalidSegmentLimitsAndExistingMeetingDirectory() throws {
        try withAudioDirectory { root in
            for limit in [Int64(0), -1, Int64.max] {
                XCTAssertThrowsError(try SegmentCAFWriter(directory: root.appendingPathComponent("invalid"), sessionID: sessionID, maximumSegmentFrames: limit)) {
                    XCTAssertEqual($0 as? SegmentWriterError, .invalidConfiguration)
                }
            }
            let directory = root.appendingPathComponent("existing"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let marker = directory.appendingPathComponent("keep.txt"); try Data("preserve".utf8).write(to: marker)
            XCTAssertThrowsError(try SegmentCAFWriter(directory: directory, sessionID: sessionID)) {
                XCTAssertEqual($0 as? SegmentWriterError, .directoryNotEmpty)
            }
            XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "preserve")
        }
    }

    func testRealFilesystemFailureIsReportedAsIOFailure() throws {
        try withAudioDirectory { root in
            let parentFile = root.appendingPathComponent("file"); try Data("fixture".utf8).write(to: parentFile)
            XCTAssertThrowsError(try SegmentCAFWriter(directory: parentFile.appendingPathComponent("meeting"), sessionID: sessionID)) {
                XCTAssertEqual($0 as? SegmentWriterError, .ioFailed)
            }
        }
    }
}
