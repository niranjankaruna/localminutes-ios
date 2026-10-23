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
