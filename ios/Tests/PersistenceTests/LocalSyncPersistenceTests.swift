import XCTest
import Foundation
@testable import LocalMinutesCore
@testable import LocalMinutesPersistence

final class LocalSyncPersistenceTests: XCTestCase {
    func testSenderUpdatesNotesButKeepsReceiverOnlyMeetingAndReceiptIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let leftRoot = root.appendingPathComponent("left"), rightRoot = root.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: leftRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightRoot, withIntermediateDirectories: true)
        let left = try SQLiteMeetingStore(databaseURL: leftRoot.appendingPathComponent("meetings.sqlite"))
        let right = try SQLiteMeetingStore(databaseURL: rightRoot.appendingPathComponent("meetings.sqlite"))
        let shared = MeetingRecord(id: UUID(), title: "Synthetic shared meeting", createdAt: Date(timeIntervalSince1970: 1_700_000_000), recordingState: .completed)
        let local = MeetingRecord(id: UUID(), title: "Receiver only", createdAt: Date(timeIntervalSince1970: 1_700_000_001), recordingState: .completed)
        try await left.createMeeting(shared); try await right.createMeeting(shared); try await right.createMeeting(local)
        try await left.saveManualNote(.init(meetingID: shared.id, text: "Sender value", editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 100)))
        try await right.saveManualNote(.init(meetingID: shared.id, text: "Newer receiver value", editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 200)))
        let stage = root.appendingPathComponent("stage"); try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try await left.exportSyncRecords(to: stage.appendingPathComponent("records.jsonl"))
        let manifest = try LocalSyncArchive.seal(stage, sourceID: UUID())
        let digest = try LocalSyncArchive.digest(stage.appendingPathComponent("manifest.json"))
        try await right.applySyncRecords(from: stage.appendingPathComponent("records.jsonl"), manifest: manifest, digest: digest)
        let imported = try await right.manualNote(meetingID: shared.id)
        XCTAssertEqual(imported?.text, "Sender value")
        let retained = try await right.meeting(id: local.id); XCTAssertNotNil(retained)
        try await right.applySyncRecords(from: stage.appendingPathComponent("records.jsonl"), manifest: manifest, digest: digest)
        let repeated = try await right.manualNote(meetingID: shared.id); XCTAssertEqual(repeated?.editRevision, imported?.editRevision)
        try await left.close(); try await right.close()
    }

    func testPathValidationRejectsTraversalAndModelPayload() {
        XCTAssertFalse(LocalSyncArchive.allowed("../Models/private.gguf"))
        XCTAssertFalse(LocalSyncArchive.allowed("Meetings/\(UUID().uuidString)/../../Models/private.gguf"))
        XCTAssertTrue(LocalSyncArchive.allowed("Meetings/\(UUID().uuidString)/segment-000000.caf"))
    }
}
