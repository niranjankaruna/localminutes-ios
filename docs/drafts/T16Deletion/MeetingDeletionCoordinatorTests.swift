import AVFoundation
import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary

@MainActor
final class MeetingDeletionCoordinatorTests: XCTestCase {
    func testConfirmedDeletionRemovesOwnedCAFMetadataNotesAndTranscriptOnly() async throws {
        try await withDeletionFixture { fixture in
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: MeetingUsageRegistry())
            try await coordinator.delete(meetingID: fixture.firstID)
            let deleted = try await fixture.store.meeting(id: fixture.firstID)
            let transcript = try await fixture.store.transcript(meetingID: fixture.firstID)
            let note = try await fixture.store.manualNote(meetingID: fixture.firstID)
            XCTAssertNil(deleted)
            XCTAssertTrue(transcript.isEmpty)
            XCTAssertNil(note)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            let retained = try await fixture.store.meeting(id: fixture.secondID)
            let secondNote = try await fixture.store.manualNote(meetingID: fixture.secondID)
            let secondTranscript = try await fixture.store.transcript(meetingID: fixture.secondID)
            XCTAssertNotNil(retained)
            XCTAssertEqual(secondNote?.text, "Synthetic second note")
            XCTAssertEqual(secondTranscript.map(\.text), ["Synthetic transcript"])
            XCTAssertTrue(secondTranscript.allSatisfy { $0.meetingID == fixture.secondID })
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondAudio.path))
            XCTAssertEqual(try Data(contentsOf: fixture.modelSentinel), Data("Synthetic model sentinel".utf8))
        }
    }

    func testAnActiveRecordingLeasePreventsDeletionUntilItsCleanupReleasesTheLease() async throws {
        try await withDeletionFixture { fixture in
            let usage = MeetingUsageRegistry()
            let lease = try usage.beginRecording(meetingID: fixture.firstID)
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: usage)
            do {
                try await coordinator.delete(meetingID: fixture.firstID)
                XCTFail("An active/preparing/stopping meeting cannot be deleted")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            let stillOwned = try await fixture.store.meeting(id: fixture.firstID)
            XCTAssertNotNil(stillOwned)
            usage.endRecording(lease)
            try await coordinator.delete(meetingID: fixture.firstID)
            let removed = try await fixture.store.meeting(id: fixture.firstID)
            XCTAssertNil(removed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
        }
    }

    func testDeletionRejectsAnAliasedMeetingDirectoryWithoutFollowingItsSymlink() async throws {
        try await withDeletionFixture { fixture in
            try FileManager.default.removeItem(at: fixture.firstAudio)
            try FileManager.default.createSymbolicLink(at: fixture.firstAudio,
                                                      withDestinationURL: fixture.models)
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: MeetingUsageRegistry())
            do {
                try await coordinator.delete(meetingID: fixture.firstID)
                XCTFail("A UUID-shaped symlink must not authorize deleting another directory")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .unsafePath) }
            let retained = try await fixture.store.meeting(id: fixture.firstID)
            XCTAssertNotNil(retained)
            XCTAssertEqual(try Data(contentsOf: fixture.modelSentinel), Data("Synthetic model sentinel".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondAudio.path))
        }
    }

    func testDeletionRejectsNestedEscapingLinksAndMismatchedManifestOwnership() async throws {
        try await withDeletionFixture { fixture in
            let escape = fixture.firstAudio.appendingPathComponent("unexpected-link")
            try FileManager.default.createSymbolicLink(at: escape,
                                                      withDestinationURL: fixture.modelSentinel)
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: MeetingUsageRegistry())
            do {
                try await coordinator.delete(meetingID: fixture.firstID)
                XCTFail("A nested external link must fail before any meeting data is removed")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .unsafePath) }
            try FileManager.default.removeItem(at: escape)
            let manifestURL = fixture.firstAudio.appendingPathComponent("capture-manifest.json")
            let otherManifestURL = fixture.secondAudio.appendingPathComponent("capture-manifest.json")
            try Data(contentsOf: otherManifestURL).write(to: manifestURL, options: .atomic)
            do {
                try await coordinator.delete(meetingID: fixture.firstID)
                XCTFail("Directory UUID and capture manifest session must identify the same meeting")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .invalidOwnership) }
            let retained = try await fixture.store.meeting(id: fixture.firstID)
            XCTAssertNotNil(retained)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            XCTAssertEqual(try Data(contentsOf: fixture.modelSentinel), Data("Synthetic model sentinel".utf8))
        }
    }

    func testUnavailableActualSQLiteLeavesOriginalAudioUntouchedBeforeDeletionStarts() async throws {
        try await withDeletionFixture { fixture in
            try await fixture.store.close()
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: MeetingUsageRegistry())
            do {
                try await coordinator.delete(meetingID: fixture.firstID)
                XCTFail("Unavailable metadata must not permit destructive filesystem work")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .metadataFailure) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            let retained = try await reopened.meeting(id: fixture.firstID)
            XCTAssertNotNil(retained)
            try await reopened.close()
        }
    }

    func testMetadataFailureAfterQuarantineCanBeRecoveredIdempotentlyFromRealDisk() async throws {
        try await withDeletionFixture { fixture in
            let gate = DeletionTestPause()
            let originalCAFs = try FileManager.default.contentsOfDirectory(at: fixture.firstAudio,
                includingPropertiesForKeys: nil).filter { $0.pathExtension == "caf" }
            let originalBytes = try Dictionary(uniqueKeysWithValues:
                originalCAFs.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
            let usage = MeetingUsageRegistry()
            let coordinator = MeetingDeletionCoordinator(store: fixture.store,
                recordingsRoot: fixture.recordings, usage: usage,
                beforeMetadataDeletion: { await gate.pause() })
            let deletion = Task { try await coordinator.delete(meetingID: fixture.firstID) }
            let entered = await waitForDeletionPause(gate)
            XCTAssertTrue(entered, "The barrier must follow durable intent and same-volume audio quarantine")
            guard entered else {
                await gate.release()
                _ = try? await deletion.value
                return
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            let requestDirectory = fixture.recordings.appendingPathComponent(".pending-deletions")
                .appendingPathComponent(fixture.firstID.uuidString, isDirectory: true)
            let markerURL = requestDirectory.appendingPathComponent("request.json")
            let quarantinedAudio = requestDirectory.appendingPathComponent("audio", isDirectory: true)
            if let markerData = try? Data(contentsOf: markerURL),
               let marker = (try? JSONSerialization.jsonObject(with: markerData)) as? [String: Any] {
                XCTAssertEqual(marker["schemaVersion"] as? Int, 1)
                XCTAssertEqual(marker["meetingID"] as? String, fixture.firstID.uuidString)
            } else { XCTFail("A recoverable deletion requires an actual durable, scoped intent marker") }
            for (filename, bytes) in originalBytes {
                XCTAssertEqual(try? Data(contentsOf: quarantinedAudio.appendingPathComponent(filename)), bytes,
                               "Quarantine must preserve each actual CAF byte before metadata commits")
            }
            let rowBeforeCommit = try await fixture.store.meeting(id: fixture.firstID)
            XCTAssertNotNil(rowBeforeCommit)
            do {
                _ = try usage.beginRecording(meetingID: fixture.firstID)
                XCTFail("Pending deletion must block a new recording reservation for that UUID")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            try await fixture.store.close()
            await gate.release()
            do {
                try await deletion.value
                XCTFail("A real closed database cannot report completed deletion")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .metadataFailure) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
            for (filename, bytes) in originalBytes {
                XCTAssertEqual(try? Data(contentsOf: quarantinedAudio.appendingPathComponent(filename)), bytes)
            }
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            let recoverer = MeetingDeletionCoordinator(store: reopened,
                recordingsRoot: fixture.recordings, usage: MeetingUsageRegistry())
            let recovered = try await recoverer.recoverPendingDeletions()
            XCTAssertEqual(recovered, [fixture.firstID])
            let removed = try await reopened.meeting(id: fixture.firstID)
            let removedNote = try await reopened.manualNote(meetingID: fixture.firstID)
            let retained = try await reopened.meeting(id: fixture.secondID)
            XCTAssertNil(removed)
            XCTAssertNil(removedNote)
            XCTAssertNotNil(retained)
            let repeated = try await recoverer.recoverPendingDeletions()
            XCTAssertTrue(repeated.isEmpty)
            try await recoverer.delete(meetingID: fixture.firstID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.firstAudio.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondAudio.path))
            XCTAssertEqual(try Data(contentsOf: fixture.modelSentinel), Data("Synthetic model sentinel".utf8))
            let descendants = try FileManager.default.subpathsOfDirectory(atPath: fixture.recordings.path)
            XCTAssertFalse(descendants.contains { $0.contains(fixture.firstID.uuidString) },
                           "No quarantined audio, pending marker or original meeting directory may remain")
            try await reopened.close()
        }
    }
}

private actor DeletionTestPause {
    private(set) var entered = false
    private var released = false
    func pause() async {
        entered = true
        let deadline = Date().addingTimeInterval(2)
        while !released && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    func release() { released = true }
}

private func waitForDeletionPause(_ gate: DeletionTestPause) async -> Bool {
    let deadline = Date().addingTimeInterval(1)
    while Date() < deadline {
        if await gate.entered { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

private struct DeletionFixture {
    let store: SQLiteMeetingStore
    let database: URL
    let recordings: URL
    let models: URL
    let modelSentinel: URL
    let firstID: UUID
    let secondID: UUID
    var firstAudio: URL { recordings.appendingPathComponent(firstID.uuidString, isDirectory: true) }
    var secondAudio: URL { recordings.appendingPathComponent(secondID.uuidString, isDirectory: true) }
}

@MainActor
private func withDeletionFixture(_ body: @MainActor (DeletionFixture) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("localminutes-deletion-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let recordings = root.appendingPathComponent("recordings", isDirectory: true)
    let models = root.appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: false)
    let sentinel = models.appendingPathComponent("synthetic-sentinel.txt")
    try Data("Synthetic model sentinel".utf8).write(to: sentinel)
    let database = root.appendingPathComponent("meetings.sqlite")
    let store = try SQLiteMeetingStore(databaseURL: database)
    let firstID = UUID(), secondID = UUID()
    for (id, title) in [(firstID, "Synthetic first"), (secondID, "Synthetic second")] {
        try await store.createMeeting(MeetingRecord(id: id, title: title,
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed,
            capturedSampleCount: 8))
        try await store.saveManualNote(StoredManualNote(meetingID: id,
            text: id == firstID ? "Synthetic first note" : "Synthetic second note",
            editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 1_000)))
        try await store.appendFinalizedSegments([StoredTranscriptSegment(id: UUID(), meetingID: id,
            sequence: 0, startSample: 0, endSample: 8, text: "Synthetic transcript",
            modelRevision: "synthetic-fixture-revision")], to: id)
        let writer = try SegmentCAFWriter(directory: recordings.appendingPathComponent(id.uuidString),
            sessionID: id, maximumSegmentFrames: 4)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8)!
        buffer.frameLength = 8
        for frame in 0..<8 { buffer.floatChannelData![0][frame] = Float(frame) / 10 }
        try writer.append(buffer)
        _ = try writer.finish()
    }
    do {
        try await body(DeletionFixture(store: store, database: database, recordings: recordings,
            models: models, modelSentinel: sentinel, firstID: firstID, secondID: secondID))
    } catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
    try? await store.close()
    guard root.lastPathComponent.hasPrefix("localminutes-deletion-tests-"),
          root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else {
        XCTFail("Unsafe fixture cleanup"); return
    }
    try FileManager.default.removeItem(at: root)
}
