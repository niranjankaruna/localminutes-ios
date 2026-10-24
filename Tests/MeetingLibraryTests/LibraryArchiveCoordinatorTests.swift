import AVFoundation
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesPersistence
import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary

/// Actual native SQLite snapshots/CAF and Core archive bytes. Runtime/OS model
/// work is not exercised or replaced; admission doubles are boundary observers.
@MainActor
final class LibraryArchiveCoordinatorTests: XCTestCase {
    func testExportRestoreRoundTripKeepsActualOriginalsGeneratedDataCAFAndSharedSiblings() async throws {
        let f = try await LibraryArchiveFixture.create()
        do {
            let files = try f.sharedBytes()
            let sourceAudio = try Data(contentsOf: f.audio)
            let coordinator = f.coordinator()
            let manifest: MeetingArchiveManifest
            do { manifest = try await coordinator.export(to: f.archive) }
            catch { XCTFail("Library export must use a real consistent SQLite snapshot plus CAF: \(type(of: error))"); await f.remove(); return }
            XCTAssertTrue(manifest.files.contains { $0.relativePath == "meetings.sqlite" })
            XCTAssertTrue(manifest.files.contains { $0.relativePath.hasSuffix(".caf") })
            XCTAssertFalse(manifest.files.contains { $0.relativePath.hasPrefix("Models/") || $0.relativePath.hasPrefix("Diagnostics/") })
            XCTAssertEqual(try MeetingArchive.inspect(f.archive), manifest)
            let destination: URL
            do { destination = try await coordinator.restore(from: f.archive) }
            catch { XCTFail("Restore must validate/migrate a fresh generation before activation"); await f.remove(); return }
            try await assertRestored(f, at: destination)
            XCTAssertEqual(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root), destination)
            XCTAssertEqual(try f.sharedBytes(), files)
            XCTAssertEqual(try Data(contentsOf: f.audio), sourceAudio)
            do { _ = try await f.store.history(); XCTFail("Successful activation must close the old SQLite connection") }
            catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
            let pointer = f.root.appendingPathComponent("activeLibrary.json")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: pointer.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual(try pointer.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testMaintenanceLeaseBlocksRealRecordingDeletionAndStaleReleaseCannotUnlockItsReplacement() async throws {
        let f = try await LibraryArchiveFixture.create()
        do {
            let first = try f.usage.beginMaintenance()
            do {
                let admitted = try f.usage.beginRecording(meetingID: f.id)
                f.usage.endRecording(admitted)
                XCTFail("A global maintenance lease must reject actual recording admission")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            do {
                try await MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.library.appendingPathComponent("Meetings"), usage: f.usage)
                    .delete(meetingID: f.id)
                XCTFail("Actual durable deletion must reject global library maintenance")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.audio.path))
            f.usage.endMaintenance(first)
            let second = try f.usage.beginMaintenance()
            XCTAssertNotEqual(first, second)
            f.usage.endMaintenance(first)
            do {
                let admitted = try f.usage.beginRecording(meetingID: UUID())
                f.usage.endRecording(admitted)
                XCTFail("A stale release must not unlock a replacement maintenance lease")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            f.usage.endMaintenance(second)
            let restoredAdmission = try f.usage.beginRecording(meetingID: UUID())
            f.usage.endRecording(restoredAdmission)
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testExportAndRestoreRejectRecordingDeletionHeavyUseAndPlaybackBeforeClosingCurrentStore() async throws {
        for boundary in ["recording", "deletion", "heavy", "playback"] {
            let f = try await LibraryArchiveFixture.create()
            let pause = LibraryArchivePause()
            var removing: Task<Void, Error>?
            var recording: MeetingRecordingLease?
            var heavy: HeavyModelUseLease?
            do {
                try await f.makeIndependentArchive()
                if boundary == "recording" { recording = try f.usage.beginRecording(meetingID: f.id) }
                if boundary == "heavy" { heavy = try f.admission.acquire(purpose: .summary, requestID: UUID(), resource: LibraryArchiveHeavyBoundary()) }
                if boundary == "deletion" {
                    let deletion = MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.library.appendingPathComponent("Meetings"),
                        usage: f.usage, beforeMetadataDeletion: { await pause.wait() })
                    removing = Task { try await deletion.delete(meetingID: f.id) }
                    let entered = await waitForArchivePause(pause)
                    XCTAssertTrue(entered)
                }
                let coordinator = f.coordinator(canMaintain: { boundary != "playback" })
                let blockedOutput = f.root.appendingPathComponent("blocked-export")
                do { _ = try await coordinator.export(to: blockedOutput); XCTFail("Export must reject active \(boundary)") }
                catch { XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .busy) }
                do { _ = try await coordinator.restore(from: f.archive); XCTFail("Restore must reject active \(boundary)") }
                catch { XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .busy) }
                XCTAssertFalse(FileManager.default.fileExists(atPath: blockedOutput.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("activeLibrary.json").path))
                let rows = try await f.store.history()
                XCTAssertEqual(rows.map(\.id), [f.id], "Busy rejection must preserve the open current SQLite store")
                if let recording { f.usage.endRecording(recording) }
                if let heavy { try await f.admission.cancelAndDrain(heavy) }
                await pause.release(); if let removing { try await removing.value }
            } catch {
                if let recording { f.usage.endRecording(recording) }
                if let heavy { try? await f.admission.cancelAndDrain(heavy) }
                await pause.release(); _ = try? await removing?.value
                await f.remove(); throw error
            }
            await f.remove()
        }
    }

    func testCorruptOrCancelledRestorePreservesActivePointerOldStoreAndPrivateSharedFiles() async throws {
        for fault in ["corrupt", "cancelled"] {
            let f = try await LibraryArchiveFixture.create(generation: true)
            do {
                try await f.makeIndependentArchive()
                let pointer = f.root.appendingPathComponent("activeLibrary.json")
                let originalPointer = try Data(contentsOf: pointer)
                let shared = try f.sharedBytes()
                let before = try Set(FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("LibraryGenerations").path))
                if fault == "corrupt" {
                    let payload = f.archive.appendingPathComponent("payload/Meetings/\(f.id.uuidString)/segment-000001.caf")
                    var bytes = try Data(contentsOf: payload); bytes[bytes.startIndex] ^= 0xff
                    try bytes.write(to: payload)
                    do { _ = try await f.coordinator().restore(from: f.archive); XCTFail("Corrupt payload must not activate any generation") }
                    catch { XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .invalidBackup) }
                } else {
                    let pause = LibraryArchivePause()
                    let task = Task { await pause.wait(); return try await f.coordinator().restore(from: f.archive) }
                    task.cancel(); await pause.release()
                    do { _ = try await task.value; XCTFail("Cancelled restore must not activate a new library") }
                    catch is CancellationError { }
                    catch { XCTFail("Expected explicit cancellation, not a completed/alternate restore") }
                }
                XCTAssertEqual(try Data(contentsOf: pointer), originalPointer)
                XCTAssertEqual(try f.sharedBytes(), shared)
                XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("LibraryGenerations").path)), before)
                let rows = try await f.store.history()
                XCTAssertEqual(rows.map(\.id), [f.id])
            } catch { await f.remove(); throw error }
            await f.remove()
        }
    }

    func testActivePointerUsesOwnedUUIDGenerationAndRejectsTraversalCorruptionOrSymlink() async throws {
        let f = try await LibraryArchiveFixture.create()
        do {
            XCTAssertEqual(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root), f.root)
            let generation = UUID()
            let directory = f.root.appendingPathComponent("LibraryGenerations/\(generation.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await f.store.createSnapshot(at: directory.appendingPathComponent("meetings.sqlite"))
            try FileManager.default.copyItem(at: f.library.appendingPathComponent("Meetings"), to: directory.appendingPathComponent("Meetings"))
            let pointer = f.root.appendingPathComponent("activeLibrary.json")
            try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(ActiveLibrarySelection(generationID: generation)), to: pointer, within: f.root)
            XCTAssertEqual(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root), directory)
            for bytes in [Data("{invalid pointer".utf8), Data("{\"schemaVersion\":1,\"generationID\":\"../Models\"}".utf8)] {
                try PersistentFilePolicy.writeAtomically(bytes, to: pointer, within: f.root)
                XCTAssertThrowsError(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root)) { error in
                    XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .invalidActivePointer)
                }
            }
            let escaped = UUID()
            try FileManager.default.createSymbolicLink(at: f.root.appendingPathComponent("LibraryGenerations/\(escaped.uuidString)"),
                withDestinationURL: f.root.appendingPathComponent("Models"))
            try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(ActiveLibrarySelection(generationID: escaped)), to: pointer, within: f.root)
            XCTAssertThrowsError(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root)) { error in
                XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .invalidActivePointer)
            }
            XCTAssertEqual(try f.sharedBytes()["Models/sentinel.bin"], Data("Synthetic shared model marker".utf8))
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testRestoreCreatesFreshGenerationPreservesPreviousActiveGenerationAndNeverOverwritesPointerTarget() async throws {
        let f = try await LibraryArchiveFixture.create(generation: true)
        do {
            try await f.makeIndependentArchive()
            let originalLibrary = f.library
            let originalDB = try Data(contentsOf: originalLibrary.appendingPathComponent("meetings.sqlite"))
            let shared = try f.sharedBytes()
            let restored: URL
            do { restored = try await f.coordinator().restore(from: f.archive) }
            catch { XCTFail("Restoring over an existing active selection must publish another fresh generation"); await f.remove(); return }
            XCTAssertNotEqual(restored, originalLibrary)
            try await assertRestored(f, at: restored)
            XCTAssertEqual(try Data(contentsOf: originalLibrary.appendingPathComponent("meetings.sqlite")), originalDB)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.audio.path))
            XCTAssertEqual(try f.sharedBytes(), shared)
            XCTAssertEqual(try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root), restored)
            let pointer = try JSONDecoder().decode(ActiveLibrarySelection.self, from: Data(contentsOf: f.root.appendingPathComponent("activeLibrary.json")))
            XCTAssertEqual(pointer.schemaVersion, 1)
            XCTAssertEqual(restored.lastPathComponent, pointer.generationID.uuidString)
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testMaintenanceRemainsHeldUntilCancelledSnapshotWorkDrainsWithoutPublishingOutput() async throws {
        let f = try await LibraryArchiveFixture.create()
        let pause = LibraryArchivePause()
        let coordinator = f.coordinator(afterMaintenance: { await pause.wait() })
        let work = Task { try await coordinator.export(to: f.archive) }
        do {
            let entered = await waitForArchivePause(pause)
            XCTAssertTrue(entered, "Only actual global maintenance acquisition may trigger the scheduling boundary")
            guard entered else { work.cancel(); await pause.release(); _ = try? await work.value; await f.remove(); return }
            do {
                let recording = try f.usage.beginRecording(meetingID: UUID())
                f.usage.endRecording(recording); XCTFail("Export's retained maintenance must block new recording")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            do {
                try await MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.library.appendingPathComponent("Meetings"), usage: f.usage).delete(meetingID: f.id)
                XCTFail("Export's real maintenance must block deletion of its CAF input")
            } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            work.cancel(); await pause.release()
            do { _ = try await work.value; XCTFail("Cancellation cannot publish successful export") }
            catch is CancellationError { }
            catch { XCTFail("Expected cancellation after maintained cleanup") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.archive.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("activeLibrary.json").path))
            let admitted = try f.usage.beginRecording(meetingID: f.id); f.usage.endRecording(admitted)
            let rows = try await f.store.history(); XCTAssertEqual(rows.map(\.id), [f.id])
        } catch {
            work.cancel(); await pause.release(); _ = try? await work.value
            await f.remove(); throw error
        }
        await f.remove()
    }

    private func assertRestored(_ f: LibraryArchiveFixture, at url: URL) async throws {
        XCTAssertEqual(url.deletingLastPathComponent(), f.root.appendingPathComponent("LibraryGenerations"))
        XCTAssertNotNil(UUID(uuidString: url.lastPathComponent))
        let restored = try SQLiteMeetingStore(databaseURL: url.appendingPathComponent("meetings.sqlite"))
        do {
            let rows = try await restored.transcript(meetingID: f.id)
            let note = try await restored.manualNote(meetingID: f.id)
            let generated = try await restored.generatedDocument(id: f.generated.id, meetingID: f.id)
            XCTAssertEqual(rows, [f.segment]); XCTAssertEqual(note, f.note); XCTAssertEqual(generated, f.generated)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("Meetings/\(f.id.uuidString)/segment-000001.caf")), try Data(contentsOf: f.audio))
            try await restored.close()
        } catch { try? await restored.close(); throw error }
    }
}

private actor LibraryArchivePause {
    private(set) var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor
private func waitForArchivePause(_ pause: LibraryArchivePause) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !(await pause.entered) { if ContinuousClock.now >= deadline { return false }; try? await Task.sleep(for: .milliseconds(5)) }
    return true
}

@MainActor
private final class LibraryArchiveHeavyBoundary: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}

@MainActor
private final class LibraryArchiveFixture {
    let root: URL, library: URL, archive: URL
    let id = UUID()
    let usage = MeetingUsageRegistry(), admission = HeavyModelAdmission()
    let store: SQLiteMeetingStore
    var audio: URL { library.appendingPathComponent("Meetings/\(id.uuidString)/segment-000001.caf") }
    var segment: StoredTranscriptSegment { .init(id: UUID(uuidString: "81818181-0000-0000-0000-000000000001")!, meetingID: id,
        sequence: 0, startSample: 0, endSample: 320, text: "Original archive transcript.", modelRevision: "synthetic-asr") }
    var note: StoredManualNote { .init(meetingID: id, text: "Original archive note — Café.", editRevision: 2, modifiedAt: Date(timeIntervalSince1970: 2_000)) }
    var generated: StoredGeneratedDocument { .init(id: UUID(uuidString: "81818181-0000-0000-0000-000000000002")!, meetingID: id,
        kind: .summary, originalJSON: Data("{\"synthetic\":\"original generated payload\"}".utf8), question: nil,
        editedText: "User-edited generated note.", modelRevision: "synthetic-llm", promptVersion: "fixture-only",
        createdAt: Date(timeIntervalSince1970: 3_000), modifiedAt: Date(timeIntervalSince1970: 3_000)) }

    private init(root: URL, library: URL, store: SQLiteMeetingStore) {
        self.root = root; self.library = library; self.store = store
        archive = root.appendingPathComponent("Exports/meeting.localminutesbackup", isDirectory: true)
    }
    static func create(generation: Bool = false) async throws -> LibraryArchiveFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-library-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var opened: SQLiteMeetingStore?
        do {
            for name in ["Models", "ModelSelections", "Diagnostics", "Exports"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: false)
            }
            for (path, text) in [("Models/sentinel.bin", "Synthetic shared model marker"),
                                 ("ModelSelections/equipped.json", "Synthetic shared choice marker"),
                                 ("Diagnostics/retained.json", "Synthetic diagnostic marker")] {
                try Data(text.utf8).write(to: root.appendingPathComponent(path))
            }
            let library: URL
            if generation {
                let id = UUID()
                library = root.appendingPathComponent("LibraryGenerations/\(id.uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
                try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(ActiveLibrarySelection(generationID: id)),
                    to: root.appendingPathComponent("activeLibrary.json"), within: root)
            } else { library = root }
            let store = try SQLiteMeetingStore(databaseURL: library.appendingPathComponent("meetings.sqlite")); opened = store
            let f = LibraryArchiveFixture(root: root, library: library, store: store)
            try await store.createMeeting(.init(id: f.id, title: "Original library meeting", createdAt: Date(timeIntervalSince1970: 1_000),
                recordingState: .completed, capturedSampleCount: 320))
            try await store.appendFinalizedSegments([f.segment], to: f.id)
            try await store.saveManualNote(f.note); try await store.createGeneratedDocument(f.generated)
            let writer = try SegmentCAFWriter(directory: library.appendingPathComponent("Meetings/\(f.id.uuidString)"), sessionID: f.id)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)); buffer.frameLength = 320
            let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
            for index in 0..<320 { samples[index] = index.isMultiple(of: 2) ? 0.25 : -0.125 }
            try writer.append(buffer); _ = try writer.finish()
            return f
        } catch { try? await opened?.close(); try? FileManager.default.removeItem(at: root); throw error }
    }
    func coordinator(canMaintain: @escaping @MainActor () -> Bool = { true },
                     afterMaintenance: (@Sendable () async -> Void)? = nil) -> LibraryArchiveCoordinator {
        if let afterMaintenance {
            return .init(applicationRoot: root, currentLibraryRoot: library, store: store, usage: usage,
                admission: admission, canMaintain: canMaintain, afterMaintenance: afterMaintenance)
        }
        return .init(applicationRoot: root, currentLibraryRoot: library, store: store, usage: usage,
            admission: admission, canMaintain: canMaintain)
    }
    func makeIndependentArchive() async throws {
        let snapshot = library.appendingPathComponent(".archive-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try await store.createSnapshot(at: snapshot.appendingPathComponent("meetings.sqlite"))
        try FileManager.default.copyItem(at: library.appendingPathComponent("Meetings"), to: snapshot.appendingPathComponent("Meetings"))
        _ = try MeetingArchive.export(snapshotRoot: snapshot, to: archive)
    }
    func sharedBytes() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: ["Models/sentinel.bin", "ModelSelections/equipped.json", "Diagnostics/retained.json"].map {
            ($0, try Data(contentsOf: root.appendingPathComponent($0)))
        })
    }
    func remove() async {
        try? await store.close()
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-library-archive-"), root.resolvingSymlinksInPath() == root else {
            return XCTFail("Unsafe library archive fixture cleanup")
        }
        try? FileManager.default.removeItem(at: root)
    }
}
