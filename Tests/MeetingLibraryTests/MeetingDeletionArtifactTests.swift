import AVFoundation
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary

/// Synthetic content through real SQLite, FTS, CAF and checkpoint adapters.
/// Storage deletion evidence is independent of actual inference validation.
@MainActor
final class MeetingDeletionArtifactTests: XCTestCase {
    func testDeletionRemovesOriginalsGeneratedEditsAnswersFTSPinCAFAndSummaryCacheOnlyForSelectedMeeting() async throws {
        try await withArtifactFixture { f in
            let otherCache = try Data(contentsOf: f.cache(f.other))
            let otherAudio = try f.bytes(in: f.audio(f.other))
            let otherDocuments = try await f.store.generatedDocuments(meetingID: f.other)
            let coordinator = f.coordinator()
            try await coordinator.delete(meetingID: f.id)
            try await f.assertAbsent(id: f.id)
            let other = try await f.store.meeting(id: f.other)
            let retainedDocuments = try await f.store.generatedDocuments(meetingID: f.other)
            let retainedPin = try await f.store.speechModelPin(meetingID: f.other)
            let retainedEvidence = try await f.store.retrieveEvidence(meetingID: f.other, query: "Artifact evidence")
            XCTAssertNotNil(other); XCTAssertNotNil(retainedPin)
            XCTAssertEqual(retainedDocuments, otherDocuments)
            XCTAssertFalse(retainedEvidence.isEmpty)
            XCTAssertEqual(try Data(contentsOf: f.cache(f.other)), otherCache)
            XCTAssertEqual(try f.bytes(in: f.audio(f.other)), otherAudio)
            try f.assertSharedBytes()
        }
    }

    func testActualRecordingClaimAndAliasedCacheRefuseWithoutRemovingAnyMeetingArtifacts() async throws {
        try await withArtifactFixture { f in
            let original = try Data(contentsOf: f.cache(f.id))
            let audio = try f.bytes(in: f.audio(f.id))
            let lease = try f.usage.beginRecording(meetingID: f.id)
            let coordinator = f.coordinator()
            do { try await coordinator.delete(meetingID: f.id); XCTFail("An actual admitted recording excludes deletion") }
            catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            let retained = try await f.store.generatedDocuments(meetingID: f.id)
            XCTAssertEqual(retained.count, 2)
            XCTAssertEqual(try Data(contentsOf: f.cache(f.id)), original)
            XCTAssertEqual(try f.bytes(in: f.audio(f.id)), audio)
            f.usage.endRecording(lease)

            try FileManager.default.removeItem(at: f.cache(f.id))
            try FileManager.default.createSymbolicLink(at: f.cache(f.id), withDestinationURL: f.cache(f.other))
            do { try await coordinator.delete(meetingID: f.id); XCTFail("A UUID-shaped cache alias never grants ownership") }
            catch { XCTAssertEqual(error as? MeetingDeletionError, .unsafePath) }
            let row = try await f.store.meeting(id: f.id)
            let documents = try await f.store.generatedDocuments(meetingID: f.id)
            XCTAssertNotNil(row); XCTAssertEqual(documents.count, 2)
            XCTAssertEqual(try? f.bytes(in: f.audio(f.id)), audio)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.cache(f.other).path))
            try FileManager.default.removeItem(at: f.cache(f.id))
            try original.write(to: f.cache(f.id))
            try await coordinator.delete(meetingID: f.id)
            try await f.assertAbsent(id: f.id)
            try f.assertSharedBytes()
        }
    }

    func testFailedCancelledDeletionReopensDurableIntentAndPurgesCorruptOwnedCacheBeforeReportingCompletion() async throws {
        try await withArtifactFixture { f in
            let pause = ArtifactDeletionPause()
            let coordinator = MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.recordings,
                usage: f.usage, summaryCheckpointRoot: f.checkpoints,
                beforeMetadataDeletion: { await pause.hold() })
            let deletion = Task { try await coordinator.delete(meetingID: f.id) }
            let entered = await pause.waitUntilEntered()
            XCTAssertTrue(entered)
            guard entered else { await pause.release(); _ = try? await deletion.value; return }
            try await f.store.close()
            deletion.cancel()
            await pause.release()
            do { try await deletion.value; XCTFail("Closed SQLite must leave a durable deletion request") }
            catch { XCTAssertEqual(error as? MeetingDeletionError, .metadataFailure) }
            let request = f.recordings.appendingPathComponent(".pending-deletions/\(f.id.uuidString)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: request.appendingPathComponent("request.json").path))
            // Once UUID ownership is known, malformed untrusted cache JSON must
            // not make the user's private quotes undeletable forever.
            let corrupt = Data("broken JSON retaining a private synthetic raw quote".utf8)
            try corrupt.write(to: f.cache(f.id))
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            f.additionalStores.append(reopened)
            let recoverer = MeetingDeletionCoordinator(store: reopened, recordingsRoot: f.recordings,
                usage: MeetingUsageRegistry(), summaryCheckpointRoot: f.checkpoints)
            let recovered = try await recoverer.recoverPendingDeletions()
            XCTAssertEqual(recovered, [f.id])
            try await f.assertAbsent(id: f.id, store: reopened)
            XCTAssertFalse(FileManager.default.fileExists(atPath: request.path), "Completion removes its retry marker only after every owned artifact")
            let again = try await recoverer.recoverPendingDeletions()
            XCTAssertTrue(again.isEmpty)
            let other = try await reopened.meeting(id: f.other)
            XCTAssertNotNil(other)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.cache(f.other).path))
            try f.assertSharedBytes()
        }
    }

    private func withArtifactFixture(_ body: @MainActor (DeletionArtifactFixture) async throws -> Void) async throws {
        let fixture = try await DeletionArtifactFixture.create()
        do { try await body(fixture) } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
    }
}

private actor ArtifactDeletionPause {
    private var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func hold() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        released = true
        let pending = waiter; waiter = nil
        pending?.resume()
    }
    func waitUntilEntered() async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if entered { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
}

@MainActor
private final class DeletionArtifactFixture {
    let root: URL, library: URL, recordings: URL, checkpoints: URL, database: URL
    let id = UUID(), other = UUID(), usage = MeetingUsageRegistry()
    let store: SQLiteMeetingStore
    var additionalStores: [SQLiteMeetingStore] = []
    private init(root: URL, library: URL, store: SQLiteMeetingStore) {
        self.root = root; self.library = library; self.store = store
        recordings = library.appendingPathComponent("Meetings", isDirectory: true)
        checkpoints = library.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
        database = library.appendingPathComponent("meetings.sqlite")
    }
    func audio(_ id: UUID) -> URL { recordings.appendingPathComponent(id.uuidString, isDirectory: true) }
    func cache(_ id: UUID) -> URL { checkpoints.appendingPathComponent(id.uuidString + ".json", isDirectory: false) }
    func coordinator() -> MeetingDeletionCoordinator {
        .init(store: store, recordingsRoot: recordings, usage: usage, summaryCheckpointRoot: checkpoints)
    }
    static func create() async throws -> DeletionArtifactFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-delete-artifacts-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("LibraryGenerations/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = try SQLiteMeetingStore(databaseURL: library.appendingPathComponent("meetings.sqlite"))
        let f = DeletionArtifactFixture(root: root, library: library, store: store)
        do {
            for path in ["Models/retained.bin", "Exports/retained-external-backup.bin"] {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(path.utf8).write(to: url)
            }
            try FileManager.default.createDirectory(at: f.checkpoints, withIntermediateDirectories: true)
            for id in [f.id, f.other] {
                try await store.createMeeting(.init(id: id, title: "Synthetic artifact meeting", createdAt: Date(timeIntervalSince1970: 1_000),
                    recordingState: .completed, capturedSampleCount: 320))
                try await store.appendFinalizedSegments([.init(id: UUID(), meetingID: id, sequence: 0,
                    startSample: 0, endSample: 320, text: "Artifact evidence quote.", modelRevision: "synthetic-asr")], to: id)
                try await store.saveManualNote(.init(meetingID: id, text: "Original synthetic manual note", editRevision: 1,
                    modifiedAt: Date(timeIntervalSince1970: 1_000)))
                try await store.saveSpeechModelPin(.init(meetingID: id, selection: .init(manifest: StreamingEnglishModel.manifest,
                    profile: .streamingZipformerONNX, installationID: UUID())))
                for kind in [GeneratedDocumentKind.summary, .questionAnswer] {
                    let documentID = UUID()
                    try await store.createGeneratedDocument(.init(id: documentID, meetingID: id, kind: kind,
                        originalJSON: Data("{\"synthetic\":\"immutable generated original\"}".utf8),
                        question: kind == .questionAnswer ? "What was recorded?" : nil, editedText: "Generated original",
                        modelRevision: "synthetic-llm", promptVersion: "synthetic-storage-only",
                        createdAt: Date(timeIntervalSince1970: 1_000), modifiedAt: Date(timeIntervalSince1970: 1_000)))
                    _ = try await store.saveGeneratedDocumentEdit(id: documentID, meetingID: id, text: "Edited generated text",
                        expectedRevision: 0, modifiedAt: Date(timeIntervalSince1970: 2_000))
                }
                let writer = try SegmentCAFWriter(directory: f.audio(id), sessionID: id, maximumSegmentFrames: 160)
                let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)); buffer.frameLength = 320
                let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
                for index in 0..<320 { samples[index] = 0.125 }
                try writer.append(buffer); _ = try writer.finish()
                let checkpoints = try SummaryCheckpointStore(directoryURL: f.checkpoints)
                let identity = SummaryCheckpointIdentity(jobID: id, meetingID: id, sourceSHA256: String(repeating: "a", count: 64),
                    planSHA256: String(repeating: "b", count: 64), modelID: "synthetic-model", modelRevision: String(repeating: "c", count: 40),
                    modelSHA256: String(repeating: "d", count: 64), runtimeVersion: "llama.cpp-b5046", promptVersion: "synthetic-map",
                    contextTokenLimit: 512, reservedOutputTokens: 64, totalChunks: 1)
                let map = try JSONSerialization.data(withJSONObject: ["meeting_id": id.uuidString,
                    "summary_points": [["quote": "Artifact evidence quote."]], "decisions": [], "actions": []])
                try await checkpoints.save(.init(index: 0, chunkSHA256: String(repeating: "e", count: 64), mapJSON: map), matching: identity)
            }
            return f
        } catch { await f.cleanup(); throw error }
    }
    func assertAbsent(id: UUID, store: SQLiteMeetingStore? = nil) async throws {
        let db = store ?? self.store
        let row = try await db.meeting(id: id), note = try await db.manualNote(meetingID: id)
        let transcript = try await db.transcript(meetingID: id), documents = try await db.generatedDocuments(meetingID: id)
        let evidence = try await db.retrieveEvidence(meetingID: id, query: "Artifact evidence")
        let pin = try await db.speechModelPin(meetingID: id)
        XCTAssertNil(row); XCTAssertNil(note); XCTAssertNil(pin)
        XCTAssertTrue(transcript.isEmpty); XCTAssertTrue(documents.isEmpty); XCTAssertTrue(evidence.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio(id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache(id).path), "Summary map checkpoints retain source quotes until explicitly erased")
    }
    func bytes(in directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    func assertSharedBytes() throws {
        for path in ["Models/retained.bin", "Exports/retained-external-backup.bin"] {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(path.utf8))
        }
    }
    func cleanup() async {
        for database in [store] + additionalStores { try? await database.close() }
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-delete-artifacts-"), root.resolvingSymlinksInPath() == root else {
            XCTFail("Refuse fixture cleanup outside its owned UUID root"); return
        }
        do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Owned artifact fixture cleanup failed") }
    }
}
