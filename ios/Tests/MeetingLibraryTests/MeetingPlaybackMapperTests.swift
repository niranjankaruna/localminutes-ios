import AVFoundation
import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import LocalMinutesMeetingLibrary
@testable import LocalMinutesRecording
#else
@testable import LocalMinutes
#endif

final class MeetingPlaybackMapperTests: XCTestCase {
    func testPlaybackMappingSeeksIntoTheActualSecondCAFWithoutDuplicatingItsFirstFrames() throws {
        try withPlaybackFixture { directory, manifest in
            let location = try MeetingPlaybackMapper.locate(globalSample: 6,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)
            XCTAssertNotNil(location)
            guard let location else { return }
            XCTAssertEqual(location.fileURL.lastPathComponent, manifest.segments[1].relativePath)
            XCTAssertEqual(location.frameOffset, 2)
            XCTAssertEqual(location.remainingFrames, 2)
            let audio = try AVAudioFile(forReading: location.fileURL)
            audio.framePosition = location.frameOffset
            let decoded = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 2)!
            try audio.read(into: decoded, frameCount: 2)
            XCTAssertEqual(decoded.frameLength, 2)
            XCTAssertEqual(decoded.floatChannelData![0][0], 0.7, accuracy: 0.0002)
            XCTAssertEqual(decoded.floatChannelData![0][1], 0.8, accuracy: 0.0002)
        }
    }

    func testPlaybackUsesHalfOpenSegmentBoundsAndRejectsNegativePositions() throws {
        try withPlaybackFixture { directory, manifest in
            let zero = try MeetingPlaybackMapper.locate(globalSample: 0,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)
            XCTAssertEqual(zero?.fileURL.lastPathComponent, manifest.segments[0].relativePath)
            XCTAssertEqual(zero?.frameOffset, 0)
            let boundary = try MeetingPlaybackMapper.locate(globalSample: 4,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)
            XCTAssertEqual(boundary?.fileURL.lastPathComponent, manifest.segments[1].relativePath)
            XCTAssertEqual(boundary?.frameOffset, 0)
            let end = try MeetingPlaybackMapper.locate(globalSample: 8,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)
            XCTAssertNil(end)
            XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: -1,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)) {
                XCTAssertEqual($0 as? MeetingPlaybackError, .invalidPosition)
            }
        }
    }

    func testPlaybackDoesNotInventAudioOrClampASeekAcrossAnExplicitManifestGap() throws {
        try withPlaybackFixture { directory, manifest in
            let gapped = AudioCaptureManifest(schemaVersion: 1, sessionID: manifest.sessionID,
                totalFrames: 8, segments: [manifest.segments[0],
                    StoredAudioSegment(relativePath: manifest.segments[1].relativePath,
                                       startFrame: 8, frameCount: 4)])
            let gap = try MeetingPlaybackMapper.locate(globalSample: 6,
                meetingID: manifest.sessionID, manifest: gapped, meetingDirectory: directory)
            XCTAssertNil(gap, "Missing global samples must remain an explicit unavailable interval")
            let afterGap = try MeetingPlaybackMapper.locate(globalSample: 9,
                meetingID: manifest.sessionID, manifest: gapped, meetingDirectory: directory)
            XCTAssertEqual(afterGap?.frameOffset, 1)
            XCTAssertEqual(afterGap?.fileURL.lastPathComponent, manifest.segments[1].relativePath)
        }
    }

    func testPlaybackRejectsAnotherMeetingsManifestBeforeOpeningAnyAudio() throws {
        try withPlaybackFixture { directory, manifest in
            XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: 0,
                meetingID: UUID(), manifest: manifest,
                meetingDirectory: directory.appendingPathComponent("not-present", isDirectory: true))) {
                XCTAssertEqual($0 as? MeetingPlaybackError, .wrongMeeting)
            }
        }
    }

    func testPlaybackDistinguishesMissingAndUnreadableRealAudioFiles() throws {
        try withPlaybackFixture { directory, manifest in
            let first = directory.appendingPathComponent(manifest.segments[0].relativePath)
            try FileManager.default.removeItem(at: first)
            XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: 0,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)) {
                XCTAssertEqual($0 as? MeetingPlaybackError, .missingAudio)
            }
            try Data("Synthetic invalid CAF bytes".utf8).write(to: first)
            XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: 0,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: directory)) {
                XCTAssertEqual($0 as? MeetingPlaybackError, .unreadableAudio)
            }
        }
    }

    func testPlaybackRejectsTraversalSymlinkEscapeAndOverlappingManifestRanges() throws {
        try withPlaybackFixture { directory, manifest in
            let outside = directory.deletingLastPathComponent().appendingPathComponent("outside.caf")
            try Data("Synthetic outside file".utf8).write(to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            let link = directory.appendingPathComponent("linked.caf")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            for relativePath in ["../outside.caf", outside.path, "linked.caf"] {
                let unsafe = AudioCaptureManifest(schemaVersion: 1, sessionID: manifest.sessionID,
                    totalFrames: 4, segments: [StoredAudioSegment(relativePath: relativePath,
                                                                 startFrame: 0, frameCount: 4)])
                XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: 0,
                    meetingID: manifest.sessionID, manifest: unsafe, meetingDirectory: directory)) {
                    XCTAssertEqual($0 as? MeetingPlaybackError, .unsafePath)
                }
            }
            let overlapping = AudioCaptureManifest(schemaVersion: 1, sessionID: manifest.sessionID,
                totalFrames: 8, segments: [manifest.segments[0],
                    StoredAudioSegment(relativePath: manifest.segments[1].relativePath,
                                       startFrame: 2, frameCount: 4)])
            XCTAssertThrowsError(try MeetingPlaybackMapper.locate(globalSample: 2,
                meetingID: manifest.sessionID, manifest: overlapping, meetingDirectory: directory)) {
                XCTAssertEqual($0 as? MeetingPlaybackError, .invalidManifest)
            }
        }
    }
}

private func withPlaybackFixture(_ body: (URL, AudioCaptureManifest) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalMinutes-PlaybackTests-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("meeting", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try SegmentCAFWriter(directory: directory, sessionID: UUID(), maximumSegmentFrames: 4)
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
    buffer.frameLength = 8
    for index in 0..<8 { buffer.floatChannelData![0][index] = Float(index + 1) / 10 }
    try writer.append(buffer)
    let manifest = try writer.finish()
    XCTAssertEqual(manifest.segments.count, 2)
    try body(directory, manifest)
}
