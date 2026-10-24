import AVFoundation
import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary

@MainActor
final class MeetingRecoveryCoordinatorTests: XCTestCase {
    func testRecoveryReconcilesActualClosedCAFWithSQLiteWithoutInventingCompletion() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let originalRows = try await f.store.transcript(meetingID: f.id)
        let report = try await f.coordinator().recover(meetingID: f.id)
        XCTAssertEqual(report.meetingID, f.id)
        XCTAssertEqual(report.durableFrameCount, 12)
        XCTAssertEqual(report.timelineEndSample, 12)
        XCTAssertEqual(report.resumeFromSample, 4)
        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertTrue(report.quarantinedFiles.isEmpty)
        let recovered = try await f.store.meeting(id: f.id)
        XCTAssertEqual(recovered?.recordingState, .recovered)
        XCTAssertEqual(recovered?.capturedSampleCount, 12)
        XCTAssertEqual(recovered?.title, "Original recovery fixture")
        let rows = try await f.store.transcript(meetingID: f.id)
        let note = try await f.store.manualNote(meetingID: f.id)
        XCTAssertEqual(rows, originalRows, "Recovery must not synthesize or duplicate recognizer output")
        XCTAssertEqual(note?.text, "Original manual recovery note")
        for segment in f.manifest.segments {
            XCTAssertEqual(try AVAudioFile(forReading: f.directory.appendingPathComponent(segment.relativePath)).length, 4)
        }
    }

    func testMissingAndCorruptSegmentsRemainExplicitGlobalGapsAndCorruptBytesAreQuarantined() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let missing = f.directory.appendingPathComponent(f.manifest.segments[1].relativePath)
        let corrupt = f.directory.appendingPathComponent(f.manifest.segments[2].relativePath)
        try FileManager.default.removeItem(at: missing)
        let badBytes = Data("Original corrupt tail fixture".utf8)
        try badBytes.write(to: corrupt)
        let report = try await f.coordinator().recover(meetingID: f.id)
        XCTAssertEqual(report.durableFrameCount, 4)
        XCTAssertEqual(report.timelineEndSample, 12, "Do not compress global time across lost audio")
        XCTAssertEqual(report.gaps.map(\.startSample), [4, 8])
        XCTAssertEqual(report.gaps.map(\.endSample), [8, 12])
        XCTAssertEqual(report.gaps.map(\.reason), [.missingAudio, .corruptAudio])
        XCTAssertEqual(report.quarantinedFiles, [f.manifest.segments[2].relativePath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("RecoveryQuarantine")
            .appendingPathComponent(corrupt.lastPathComponent)), badBytes)
        let row = try await f.store.meeting(id: f.id)
        XCTAssertEqual(row?.recordingState, .recovered)
        XCTAssertEqual(row?.capturedSampleCount, 4)
    }

    func testAnUncommittedNativeCAFTailIsQuarantinedWithoutGuessingItsGlobalPosition() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let tail = f.directory.appendingPathComponent("segment-000003.caf")
        try FileManager.default.copyItem(at: f.directory.appendingPathComponent(f.manifest.segments[0].relativePath), to: tail)
        let bytes = try Data(contentsOf: tail)
        XCTAssertEqual(try AVAudioFile(forReading: tail).length, 4)
        let report = try await f.coordinator().recover(meetingID: f.id)
        XCTAssertEqual(report.timelineEndSample, 12)
        XCTAssertEqual(report.durableFrameCount, 12, "Readable but uncommitted bytes have no proven timeline")
        XCTAssertEqual(report.quarantinedFiles, [tail.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tail.path))
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("RecoveryQuarantine")
            .appendingPathComponent(tail.lastPathComponent)), bytes)
        let persisted = try JSONDecoder().decode(AudioCaptureManifest.self,
            from: Data(contentsOf: f.manifestURL))
        XCTAssertEqual(persisted, f.manifest, "Retain the source checkpoint instead of inventing a completed tail")
    }

    func testRecoveryReopensIdempotentlyWithoutDuplicateRowsOrRepeatedTailMoves() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let tail = f.directory.appendingPathComponent("segment-000003.caf")
        try Data("Original uncommitted damaged CAF".utf8).write(to: tail)
        let first = try await f.coordinator().recover(meetingID: f.id)
        try await f.store.close()
        let reopened = try SQLiteMeetingStore(databaseURL: f.database)
        let second = try await MeetingRecoveryCoordinator(store: reopened, recordingsRoot: f.recordings)
            .recover(meetingID: f.id)
        XCTAssertEqual(second, first)
        let rows = try await reopened.transcript(meetingID: f.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text, "Original finalized recovery transcript")
        let files = try FileManager.default.contentsOfDirectory(atPath:
            f.directory.appendingPathComponent("RecoveryQuarantine").path)
        XCTAssertEqual(files, [tail.lastPathComponent])
        let row = try await reopened.meeting(id: f.id)
        XCTAssertEqual(row?.recordingState, .recovered)
        try await reopened.close()
    }

    func testRecoveryRejectsTraversalSymlinksAndAnotherMeetingsManifestBeforeAnyMutation() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let outside = f.root.appendingPathComponent("outside.caf")
        let sentinel = Data("Original outside sentinel".utf8)
        try sentinel.write(to: outside)
        for name in ["../outside.caf", outside.path, "linked.caf"] {
            if name == "linked.caf" {
                try FileManager.default.createSymbolicLink(at: f.directory.appendingPathComponent(name),
                    withDestinationURL: outside)
            }
            let unsafe = AudioCaptureManifest(schemaVersion: 1, sessionID: f.id, totalFrames: 4,
                segments: [.init(relativePath: name, startFrame: 0, frameCount: 4)])
            try JSONEncoder().encode(unsafe).write(to: f.manifestURL, options: .atomic)
            do { _ = try await f.coordinator().recover(meetingID: f.id); XCTFail("Unsafe recovery path was accepted") }
            catch { XCTAssertEqual(error as? MeetingRecoveryError, .unsafePath) }
            if name == "linked.caf" { try FileManager.default.removeItem(at: f.directory.appendingPathComponent(name)) }
        }
        let mismatch = AudioCaptureManifest(schemaVersion: 1, sessionID: UUID(),
            totalFrames: f.manifest.totalFrames, segments: f.manifest.segments)
        try JSONEncoder().encode(mismatch).write(to: f.manifestURL, options: .atomic)
        do { _ = try await f.coordinator().recover(meetingID: f.id); XCTFail("Mismatched manifest was accepted") }
        catch { XCTAssertEqual(error as? MeetingRecoveryError, .invalidManifest) }
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
        let row = try await f.store.meeting(id: f.id)
        XCTAssertEqual(row?.recordingState, .recording)
        XCTAssertEqual(row?.capturedSampleCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            f.directory.appendingPathComponent("RecoveryQuarantine").path))
    }

    func testRecoveryCannotTouchAnActiveSessionOrMutateAFinishedMeeting() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let original = try Data(contentsOf: f.manifestURL)
        do {
            _ = try await f.coordinator().recover(meetingID: f.id, activeMeetingIDs: [f.id])
            XCTFail("Active capture cannot be reconciled concurrently")
        } catch { XCTAssertEqual(error as? MeetingRecoveryError, .meetingInUse) }
        let before = try await f.store.meeting(id: f.id)
        XCTAssertEqual(before?.recordingState, .recording)
        try await f.store.updateRecordingState(id: f.id, state: .completed, capturedSampleCount: 12)
        _ = try await f.coordinator().recover(meetingID: f.id)
        let completed = try await f.store.meeting(id: f.id)
        XCTAssertEqual(completed?.recordingState, .completed)
        XCTAssertEqual(try Data(contentsOf: f.manifestURL), original)
    }

    func testUnavailableRealSQLitePreventsMovingAnyUncommittedTail() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let tail = f.directory.appendingPathComponent("segment-000003.caf")
        let bytes = Data("Original uncommitted fixture".utf8)
        try bytes.write(to: tail)
        try await f.store.close()
        do { _ = try await f.coordinator().recover(meetingID: f.id); XCTFail("Closed database was accepted") }
        catch { XCTAssertEqual(error as? MeetingRecoveryError, .metadataFailure) }
        XCTAssertEqual(try Data(contentsOf: tail), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            f.directory.appendingPathComponent("RecoveryQuarantine").path))
    }

    func testRecoveryJournalSurvivesActualMetadataFailureAfterQuarantineAndFinishesOnReopen() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let tail = f.directory.appendingPathComponent("segment-000003.caf")
        let bytes = Data("Original crash-recovery tail fixture".utf8)
        try bytes.write(to: tail)
        let actualStore = f.store
        let failing = MeetingRecoveryCoordinator(store: actualStore, recordingsRoot: f.recordings,
            beforeMetadataUpdate: { try? await actualStore.close() })
        do { _ = try await failing.recover(meetingID: f.id); XCTFail("A real closed metadata connection cannot acknowledge recovery") }
        catch { XCTAssertEqual(error as? MeetingRecoveryError, .metadataFailure) }
        let journalURL = f.directory.appendingPathComponent("recovery-report.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path),
            "A durable recovery plan must precede moving any original bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tail.path))
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("RecoveryQuarantine")
            .appendingPathComponent(tail.lastPathComponent)), bytes)
        let journal = try JSONDecoder().decode(MeetingRecoveryReport.self,
            from: Data(contentsOf: journalURL))
        let reopened = try SQLiteMeetingStore(databaseURL: f.database)
        let report = try await MeetingRecoveryCoordinator(store: reopened, recordingsRoot: f.recordings)
            .recover(meetingID: f.id)
        XCTAssertEqual(report, journal)
        let row = try await reopened.meeting(id: f.id)
        XCTAssertEqual(row?.recordingState, .recovered)
        let rows = try await reopened.transcript(meetingID: f.id)
        XCTAssertEqual(rows.count, 1)
        try await reopened.close()
    }

    func testRecoveryRejectsAlteredJournalPlansBeforeQuarantiningHealthyAudioOrChangingDuration() async throws {
        for alteration in ["healthyQuarantine", "falseDurableCount"] {
            let f = try RecoveryFixture(); defer { f.cleanup() }
            try await f.seed()
            _ = try await f.coordinator().recover(meetingID: f.id)
            let beforeRow = try await f.store.meeting(id: f.id)
            let beforeRows = try await f.store.transcript(meetingID: f.id)
            let originalBytes = try Dictionary(uniqueKeysWithValues: f.manifest.segments.map {
                ($0.relativePath, try Data(contentsOf: f.directory.appendingPathComponent($0.relativePath)))
            })
            let reportURL = f.directory.appendingPathComponent("recovery-report.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with:
                Data(contentsOf: reportURL)) as? [String: Any])
            // Preserve every other field, including any manifest binding. This
            // changes a legitimate bounded journal rather than fabricating one.
            if alteration == "healthyQuarantine" {
                object["quarantinedFiles"] = [f.manifest.segments[0].relativePath]
            } else {
                object["durableFrameCount"] = 0
            }
            let alteredData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try alteredData.write(to: reportURL, options: .atomic)
            do {
                _ = try await f.coordinator().recover(meetingID: f.id)
                XCTFail("An inconsistent \(alteration) journal must not authorize file moves or metadata changes")
            } catch { XCTAssertEqual(error as? MeetingRecoveryError, .invalidManifest) }
            for (name, bytes) in originalBytes {
                XCTAssertEqual(try? Data(contentsOf: f.directory.appendingPathComponent(name)), bytes)
            }
            let afterRow = try await f.store.meeting(id: f.id)
            let afterRows = try await f.store.transcript(meetingID: f.id)
            XCTAssertEqual(afterRow, beforeRow)
            XCTAssertEqual(afterRows, beforeRows)
            XCTAssertEqual(try Data(contentsOf: reportURL), alteredData,
                           "Rejecting an untrusted plan must not silently replace its evidence")
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                f.directory.appendingPathComponent("RecoveryQuarantine").path))
            try await f.store.close()
        }
    }

    func testExplicitGapUsesCapturedCountAndOneGlobalTimelineForRecoveryAndActualPlayback() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        try FileManager.default.removeItem(at:
            f.directory.appendingPathComponent(f.manifest.segments[2].relativePath))
        let gapped = AudioCaptureManifest(schemaVersion: 1, sessionID: f.id, totalFrames: 8,
            segments: [f.manifest.segments[0],
                StoredAudioSegment(relativePath: f.manifest.segments[1].relativePath,
                                   startFrame: 8, frameCount: 4)])
        try JSONEncoder().encode(gapped).write(to: f.manifestURL, options: .atomic)
        let report: MeetingRecoveryReport
        do { report = try await f.coordinator().recover(meetingID: f.id) }
        catch {
            XCTFail("A valid captured-count manifest with an explicit global gap must recover: \(type(of: error))")
            return
        }
        XCTAssertEqual(report.durableFrameCount, 8)
        XCTAssertEqual(report.timelineEndSample, 12)
        XCTAssertEqual(report.resumeFromSample, 4)
        XCTAssertEqual(report.gaps.map(\.startSample), [4])
        XCTAssertEqual(report.gaps.map(\.endSample), [8])
        XCTAssertEqual(report.gaps.map(\.reason), [.manifestGap])
        XCTAssertTrue(report.quarantinedFiles.isEmpty)
        let persisted = try JSONDecoder().decode(AudioCaptureManifest.self,
            from: Data(contentsOf: f.manifestURL))
        XCTAssertEqual(persisted, gapped, "Recovery must preserve the original sample mapping")
        let location = try XCTUnwrap(MeetingPlaybackMapper.locate(globalSample: 9,
            meetingID: f.id, manifest: persisted, meetingDirectory: f.directory))
        XCTAssertEqual(location.fileURL.lastPathComponent, gapped.segments[1].relativePath)
        XCTAssertEqual(location.frameOffset, 1)
        let audio = try AVAudioFile(forReading: location.fileURL)
        defer { audio.close() }
        audio.framePosition = location.frameOffset
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1))
        try audio.read(into: buffer, frameCount: 1)
        XCTAssertEqual(buffer.frameLength, 1)
        XCTAssertEqual(buffer.floatChannelData![0][0], Float(5) / 32, accuracy: 0.0002)
        let missing = try MeetingPlaybackMapper.locate(globalSample: 6,
            meetingID: f.id, manifest: persisted, meetingDirectory: f.directory)
        XCTAssertNil(missing, "The missing global samples must not be clamped onto real audio")
        let row = try await f.store.meeting(id: f.id)
        XCTAssertEqual(row?.capturedSampleCount, 8)
        try await f.store.close()
    }

    func testRecoveryCountsOnlyFullyDecodableFramesWhenAnActualCAFDataBodyIsTruncated() async throws {
        let f = try RecoveryFixture(); defer { f.cleanup() }
        try await f.seed()
        let segment = f.manifest.segments[2]
        let file = f.directory.appendingPathComponent(segment.relativePath)
        let original = try Data(contentsOf: file)
        let originalRead = observeNativeCAF(file)
        XCTAssertTrue(originalRead.opened)
        XCTAssertFalse(originalRead.readFailed)
        XCTAssertEqual(originalRead.samples.count, 4)
        let fixture = try truncateCAFDataBody(original, keepingPCMBytes: 2)
        XCTAssertEqual(fixture.bytes.prefix(fixture.audioStart), original.prefix(fixture.audioStart),
                       "Keep the real CAF headers/edit count while removing PCM body bytes")
        XCTAssertLessThan(fixture.bytes.count, original.count)
        try fixture.bytes.write(to: file, options: .atomic)
        let observation = observeNativeCAF(file)
        let samplesMatch = observation.samples.count == originalRead.samples.count &&
            zip(observation.samples, originalRead.samples).allSatisfy { pair in abs(pair.0 - pair.1) < 0.0002 }
        print("RECOVERY_TRUNCATED_CAF opened=\(observation.opened) headerFrames=\(observation.headerFrames.map { String($0) } ?? "unavailable") decodedFrames=\(observation.samples.count) readFailed=\(observation.readFailed) originalSamplesMatch=\(samplesMatch)")
        XCTAssertFalse(observation.opened && !observation.readFailed && samplesMatch,
                       "A physically truncated PCM body cannot supply all original native samples")
        let report = try await f.coordinator().recover(meetingID: f.id)
        XCTAssertEqual(report.durableFrameCount, 8,
                       "Container length alone must not claim all frames of the incomplete segment")
        XCTAssertEqual(report.timelineEndSample, 12)
        XCTAssertEqual(report.gaps.map(\.startSample), [8])
        XCTAssertEqual(report.gaps.map(\.endSample), [12])
        XCTAssertEqual(report.gaps.map(\.reason), [.corruptAudio])
        XCTAssertEqual(report.quarantinedFiles, [segment.relativePath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("RecoveryQuarantine")
            .appendingPathComponent(segment.relativePath)), fixture.bytes)
        var readable: Int64 = 0
        for healthy in f.manifest.segments where !report.quarantinedFiles.contains(healthy.relativePath) {
            let decoded = observeNativeCAF(f.directory.appendingPathComponent(healthy.relativePath))
            XCTAssertTrue(decoded.opened)
            XCTAssertFalse(decoded.readFailed)
            XCTAssertEqual(Int64(decoded.samples.count), healthy.frameCount)
            readable += Int64(decoded.samples.count)
        }
        XCTAssertEqual(report.durableFrameCount, readable)
        let row = try await f.store.meeting(id: f.id)
        XCTAssertEqual(row?.capturedSampleCount, readable)
        try await f.store.close()
    }
}

private struct NativeCAFObservation {
    var opened = false
    var headerFrames: Int64?
    var samples: [Float] = []
    var readFailed = false
}

/// Actual AVFoundation open/read results are reported even if this platform
/// already rejects the incomplete body at open or reports its shorter length.
private func observeNativeCAF(_ file: URL) -> NativeCAFObservation {
    var result = NativeCAFObservation()
    do {
        let audio = try AVAudioFile(forReading: file)
        defer { audio.close() }
        result.opened = true
        result.headerFrames = audio.length
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 16) else {
            result.readFailed = true
            return result
        }
        // Fixture segments contain four frames. The bound protects this helper
        // from a malformed native header without treating a header as evidence.
        while result.samples.count < 64 {
            try audio.read(into: buffer, frameCount: 16)
            guard buffer.frameLength > 0 else { break }
            guard let plane = buffer.floatChannelData?[0] else {
                result.readFailed = true
                break
            }
            result.samples.append(contentsOf: UnsafeBufferPointer(start: plane, count: Int(buffer.frameLength)))
        }
    } catch { result.readFailed = true }
    return result
}

private enum CAFTruncationFixtureError: Error { case invalidNativeCAF }

/// Apple's CAF layout: 8-byte file header, then fourcc + big-endian Int64 chunk
/// length; data begins with a 4-byte edit count. The actual native header is kept.
/// https://developer.apple.com/library/archive/documentation/MusicAudio/Reference/CAFSpec/CAF_spec/CAF_spec.html
private func truncateCAFDataBody(_ original: Data, keepingPCMBytes: Int) throws -> (bytes: Data, audioStart: Int) {
    guard original.count >= 8, String(decoding: original.prefix(4), as: UTF8.self) == "caff",
          keepingPCMBytes >= 0 else { throw CAFTruncationFixtureError.invalidNativeCAF }
    var offset = 8
    while offset <= original.count - 12 {
        let type = String(decoding: original[offset..<(offset + 4)], as: UTF8.self)
        let lengthBits = original[(offset + 4)..<(offset + 12)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let bodyStart = offset + 12
        let length: Int
        if lengthBits == UInt64.max, type == "data" {
            length = original.count - bodyStart
        } else {
            guard let value = Int(exactly: lengthBits), value >= 0,
                  value <= original.count - bodyStart else { throw CAFTruncationFixtureError.invalidNativeCAF }
            length = value
        }
        if type == "data" {
            guard length >= 4, keepingPCMBytes < length - 4 else {
                throw CAFTruncationFixtureError.invalidNativeCAF
            }
            let audioStart = bodyStart + 4
            return (Data(original.prefix(audioStart + keepingPCMBytes)), audioStart)
        }
        offset = bodyStart + length
    }
    throw CAFTruncationFixtureError.invalidNativeCAF
}

@MainActor
private final class RecoveryFixture {
    let root: URL
    let recordings: URL
    let directory: URL
    let manifestURL: URL
    let database: URL
    let id: UUID
    let store: SQLiteMeetingStore
    let manifest: AudioCaptureManifest

    init() throws {
        id = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LocalMinutes-RecoveryTests-\(UUID().uuidString)", isDirectory: true)
        recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        directory = recordings.appendingPathComponent(id.uuidString, isDirectory: true)
        manifestURL = directory.appendingPathComponent("capture-manifest.json")
        database = root.appendingPathComponent("meetings.sqlite")
        let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 4)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 12))
        buffer.frameLength = 12
        for i in 0..<12 { buffer.floatChannelData![0][i] = Float(i) / 32 }
        try writer.append(buffer)
        manifest = try writer.finish()
        XCTAssertEqual(manifest.segments.count, 3)
        store = try SQLiteMeetingStore(databaseURL: database)
    }

    func seed() async throws {
        try await store.createMeeting(.init(id: id, title: "Original recovery fixture",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recording))
        try await store.appendFinalizedSegments([.init(id: UUID(), meetingID: id, sequence: 0,
            startSample: 0, endSample: 4, text: "Original finalized recovery transcript",
            modelRevision: "original-fixture-revision")], to: id)
        try await store.saveManualNote(.init(meetingID: id, text: "Original manual recovery note",
            editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 1_001)))
    }

    func coordinator() -> MeetingRecoveryCoordinator {
        MeetingRecoveryCoordinator(store: store, recordingsRoot: recordings)
    }

    func cleanup() {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        guard root.standardizedFileURL.deletingLastPathComponent() == temporary,
              root.lastPathComponent.hasPrefix("LocalMinutes-RecoveryTests-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("LocalMinutes-RecoveryTests-".count))) != nil else {
            XCTFail("Unsafe recovery fixture cleanup target"); return
        }
        try? FileManager.default.removeItem(at: root)
    }
}
