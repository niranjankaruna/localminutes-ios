import AVFoundation
import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary

@MainActor
final class LibraryStartupCoordinatorTests: XCTestCase {
    func testStartupReplaysDurableDeletionBeforeEnumeratingUnfinishedAudioAndThenAllowsCapture() async throws {
        try await withStartupFixture { fixture in
            let deleting = try await fixture.seedMeeting(1)
            let healthy = try await fixture.seedMeeting(2)
            try fixture.quarantineForConfirmedDeletion(deleting)
            let usage = MeetingUsageRegistry(requiresStartup: true)
            let startup = LibraryStartupCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: usage)
            XCTAssertEqual(startup.state, .notStarted)
            XCTAssertThrowsError(try usage.beginRecording(meetingID: UUID()))
            let report: LibraryStartupReport
            do { report = try await startup.run() }
            catch { XCTFail("Confirmed deletion and healthy recovery must finish startup: \(type(of: error))"); return }
            XCTAssertEqual(report.deletedMeetingIDs, [deleting])
            XCTAssertEqual(report.recoveredMeetingIDs, [healthy])
            XCTAssertTrue(report.issues.isEmpty,
                          "Recovering the now-absent original before its pending deletion replay is the wrong order")
            XCTAssertEqual(startup.state, .ready)
            XCTAssertEqual(startup.report, report)
            let deletedRow = try await fixture.store.meeting(id: deleting)
            let healthyRow = try await fixture.store.meeting(id: healthy)
            XCTAssertNil(deletedRow)
            XCTAssertEqual(healthyRow?.recordingState, .recovered)
            XCTAssertEqual(healthyRow?.capturedSampleCount, 4)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory(deleting).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.requestDirectory(deleting).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath:
                fixture.directory(healthy).appendingPathComponent("capture-manifest.json").path))
            let lease = try usage.beginRecording(meetingID: UUID())
            usage.endRecording(lease)
        }
    }

    func testStartupProcessesUnfinishedMeetingsBeyondOnePageAndIsIdempotentAcrossReopen() async throws {
        try await withStartupFixture { fixture in
            var expected: [UUID] = []
            let states: [MeetingRecordingState] = [.recording, .interrupted, .failed, .recovered]
            for number in 1...103 {
                expected.append(try await fixture.seedMeeting(number, state: states[(number - 1) % states.count]))
            }
            let completed = try await fixture.seedMeeting(900, state: .completed)
            let completedManifest = fixture.directory(completed).appendingPathComponent("capture-manifest.json")
            let completedBytes = try Data(contentsOf: completedManifest)
            let startup = LibraryStartupCoordinator(store: fixture.store, recordingsRoot: fixture.recordings,
                usage: MeetingUsageRegistry(requiresStartup: true))
            let first: LibraryStartupReport
            do { first = try await startup.run() }
            catch { XCTFail("All UUID-keyset pages must be accounted: \(type(of: error))"); return }
            XCTAssertEqual(first.recoveredMeetingIDs, expected)
            XCTAssertTrue(first.deletedMeetingIDs.isEmpty)
            XCTAssertTrue(first.issues.isEmpty)
            XCTAssertEqual(startup.state, .ready)
            let reportURL = fixture.directory(expected[0]).appendingPathComponent("recovery-report.json")
            let reportBytes = try Data(contentsOf: reportURL)
            try await fixture.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            do {
                let secondStartup = LibraryStartupCoordinator(store: reopened, recordingsRoot: fixture.recordings,
                    usage: MeetingUsageRegistry(requiresStartup: true))
                let second = try await secondStartup.run()
                XCTAssertEqual(second, first)
                XCTAssertEqual(secondStartup.state, .ready)
                let all = try await reopened.history(limit: 1_000)
                XCTAssertEqual(all.count, 104)
                XCTAssertTrue(all.filter { $0.id != completed }.allSatisfy {
                    $0.recordingState == .recovered && $0.capturedSampleCount == 4
                })
                let finished = try await reopened.meeting(id: completed)
                XCTAssertEqual(finished?.recordingState, .completed)
                XCTAssertEqual(try Data(contentsOf: completedManifest), completedBytes)
                XCTAssertFalse(FileManager.default.fileExists(atPath:
                    fixture.directory(completed).appendingPathComponent("recovery-report.json").path))
                XCTAssertEqual(try Data(contentsOf: reportURL), reportBytes)
                let source = try await reopened.transcript(meetingID: expected[0])
                XCTAssertTrue(source.isEmpty, "Startup reconciliation must not fabricate ASR output")
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }

    func testStartupRecordsAnIsolatedCorruptMeetingButProcessesHealthyOthersBeforeReady() async throws {
        try await withStartupFixture { fixture in
            let bad = try await fixture.seedMeeting(1)
            let good = try await fixture.seedMeeting(2)
            let badManifest = fixture.directory(bad).appendingPathComponent("capture-manifest.json")
            let badBytes = Data("Synthetic invalid recovery manifest".utf8)
            try badBytes.write(to: badManifest, options: .atomic)
            let usage = MeetingUsageRegistry(requiresStartup: true)
            let startup = LibraryStartupCoordinator(store: fixture.store, recordingsRoot: fixture.recordings, usage: usage)
            let report: LibraryStartupReport
            do { report = try await startup.run() }
            catch { XCTFail("One corrupt meeting must be accounted without abandoning healthy meetings"); return }
            XCTAssertEqual(report.recoveredMeetingIDs, [good])
            XCTAssertEqual(report.issues, [LibraryStartupIssue(meetingID: bad, failure: .invalidManifest)])
            XCTAssertEqual(startup.report, report)
            XCTAssertEqual(startup.state, .ready, "Ready follows complete accounting, including explicit isolated issues")
            let healthyRow = try await fixture.store.meeting(id: good)
            let badRow = try await fixture.store.meeting(id: bad)
            XCTAssertEqual(healthyRow?.recordingState, .recovered)
            XCTAssertEqual(badRow?.recordingState, .recording,
                           "A failed inspection cannot pretend the corrupt meeting was recovered or completed")
            XCTAssertEqual(try Data(contentsOf: badManifest), badBytes)
            let lease = try usage.beginRecording(meetingID: UUID())
            usage.endRecording(lease)
        }
    }

    func testDatabaseAndDeletionReplayFailuresKeepStartupFailedAndCaptureAdmissionClosed() async throws {
        try await withStartupFixture { fixture in
            let id = try await fixture.seedMeeting(1)
            let manifest = fixture.directory(id).appendingPathComponent("capture-manifest.json")
            let bytes = try Data(contentsOf: manifest)
            try await fixture.store.close()
            let usage = MeetingUsageRegistry(requiresStartup: true)
            let startup = LibraryStartupCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: usage)
            do {
                _ = try await startup.run()
                XCTFail("A real closed database cannot establish startup readiness")
            } catch { XCTAssertEqual(error as? LibraryStartupError, .metadataFailure) }
            XCTAssertEqual(startup.state, .failed)
            XCTAssertNil(startup.report)
            XCTAssertThrowsError(try usage.beginRecording(meetingID: UUID()))
            XCTAssertEqual(try Data(contentsOf: manifest), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                fixture.directory(id).appendingPathComponent("recovery-report.json").path))
        }
        try await withStartupFixture { fixture in
            let pending = try await fixture.seedMeeting(1)
            let healthy = try await fixture.seedMeeting(2)
            try fixture.quarantineForConfirmedDeletion(pending)
            let request = fixture.requestDirectory(pending)
            let marker = request.appendingPathComponent("request.json")
            let malformed = try JSONSerialization.data(withJSONObject:
                ["schemaVersion": 999, "meetingID": pending.uuidString], options: [.sortedKeys])
            try malformed.write(to: marker, options: .atomic)
            let audio = request.appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent("segment-000000.caf")
            let audioBytes = try Data(contentsOf: audio)
            let usage = MeetingUsageRegistry(requiresStartup: true)
            let startup = LibraryStartupCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: usage)
            do {
                _ = try await startup.run()
                XCTFail("An invalid durable deletion request is a global startup failure")
            } catch { XCTAssertEqual(error as? LibraryStartupError, .deletionReplayFailure) }
            XCTAssertEqual(startup.state, .failed)
            XCTAssertNil(startup.report)
            XCTAssertThrowsError(try usage.beginRecording(meetingID: UUID()))
            XCTAssertEqual(try Data(contentsOf: marker), malformed)
            XCTAssertEqual(try Data(contentsOf: audio), audioBytes)
            let pendingRow = try await fixture.store.meeting(id: pending)
            let healthyRow = try await fixture.store.meeting(id: healthy)
            XCTAssertEqual(pendingRow?.recordingState, .recording)
            XCTAssertEqual(healthyRow?.recordingState, .recording,
                           "A global deletion failure must stop before ordinary recovery")
        }
    }
}

@MainActor
private final class StartupFixture {
    let root: URL
    let recordings: URL
    let database: URL
    let store: SQLiteMeetingStore

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-startup-tests-\(UUID().uuidString)", isDirectory: true)
        recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        database = root.appendingPathComponent("meetings.sqlite")
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        store = try SQLiteMeetingStore(databaseURL: database)
    }

    func directory(_ id: UUID) -> URL { recordings.appendingPathComponent(id.uuidString, isDirectory: true) }
    func requestDirectory(_ id: UUID) -> URL {
        recordings.appendingPathComponent(".pending-deletions", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func seedMeeting(_ number: Int, state: MeetingRecordingState = .recording) async throws -> UUID {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        try await store.createMeeting(MeetingRecord(id: id, title: "Synthetic startup meeting",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: state,
            capturedSampleCount: state == .completed ? 4 : 0))
        let writer = try SegmentCAFWriter(directory: directory(id), sessionID: id, maximumSegmentFrames: 4)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        for frame in 0..<4 { buffer.floatChannelData![0][frame] = Float(frame) / 16 }
        try writer.append(buffer)
        _ = try writer.finish()
        return id
    }

    func quarantineForConfirmedDeletion(_ id: UUID) throws {
        let request = requestDirectory(id)
        try FileManager.default.createDirectory(at: request, withIntermediateDirectories: true)
        let marker = request.appendingPathComponent("request.json")
        let bytes = try JSONSerialization.data(withJSONObject:
            ["schemaVersion": 1, "meetingID": id.uuidString], options: [.sortedKeys])
        try bytes.write(to: marker, options: .atomic)
        let handle = try FileHandle(forUpdating: marker)
        try handle.synchronize()
        try handle.close()
        try FileManager.default.moveItem(at: directory(id), to: request.appendingPathComponent("audio", isDirectory: true))
    }

    func cleanup() throws {
        guard root.lastPathComponent.hasPrefix("localminutes-startup-tests-"),
              root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
            XCTFail("Unsafe startup fixture cleanup"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func withStartupFixture(_ body: @MainActor (StartupFixture) async throws -> Void) async throws {
    let fixture = try StartupFixture()
    do { try await body(fixture) }
    catch { try? await fixture.store.close(); try? fixture.cleanup(); throw error }
    try? await fixture.store.close()
    try fixture.cleanup()
}
