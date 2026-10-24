import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
@testable import LocalMinutesRecording
@testable import LocalMinutesMeetingLibrary
@testable import LocalMinutesTranscription

/// Mandatory actual licensed speech/model + actual native CAF/SQLite. Missing
/// fixtures fail setup; none of these tests skips or supplies recognizer text.
@MainActor
final class RecoveredTranscriptionReplayTests: XCTestCase {
    func testActualASRReplaysOnlyUntranscribedDurableCAFPreservesGlobalRangesAndIsIdempotentAfterReopen() async throws {
        let f = try await ReplayFixture.create()
        do {
            let recovery = try await MeetingRecoveryCoordinator(store: f.store, recordingsRoot: f.recordings)
                .recover(meetingID: f.id)
            XCTAssertEqual(recovery.resumeFromSample, f.prefixFrames)
            let originalRecovery = try Data(contentsOf: f.directory.appendingPathComponent("recovery-report.json"))
            let originalManifest = try Data(contentsOf: f.manifestURL)
            let originalNote = try await f.store.manualNote(meetingID: f.id)
            let replay = f.coordinator()
            let report = try await replay.replay(meetingID: f.id)
            let rows = try await f.store.transcript(meetingID: f.id)
            XCTAssertEqual(rows.first, f.original)
            XCTAssertEqual(rows.count, 2)
            if rows.count == 2 {
                assertReplaySpeech(rows[1].text)
                XCTAssertEqual(rows[1].sequence, 1)
                XCTAssertEqual(rows[1].startSample, f.prefixFrames,
                    "Native stream starts at zero; stored timestamps must retain the manifest's global offset")
                XCTAssertGreaterThan(rows[1].endSample, f.prefixFrames)
                XCTAssertLessThanOrEqual(rows[1].endSample, f.timelineEnd)
                XCTAssertEqual(rows[1].modelRevision, NativeASRFixture.revision)
                XCTAssertEqual(report.insertedSegmentIDs, [rows[1].id])
            }
            XCTAssertEqual(report.durableFrameCount, f.manifest.totalFrames)
            XCTAssertEqual(report.replayedFrameCount, f.manifest.totalFrames - f.prefixFrames)
            XCTAssertEqual(report.timelineEndSample, f.timelineEnd)
            XCTAssertTrue(report.gaps.isEmpty)
            let checkpoint = try await replay.checkpoint(meetingID: f.id)
            XCTAssertEqual(checkpoint?.meetingID, f.id)
            XCTAssertEqual(checkpoint?.manifestSHA256, replayDigest(originalManifest))
            XCTAssertEqual(checkpoint?.modelRevision, NativeASRFixture.revision)
            XCTAssertEqual(checkpoint?.nextGlobalSample, f.timelineEnd)
            XCTAssertEqual(checkpoint?.committedSequence, 1)
            let metadata = try await f.store.meeting(id: f.id)
            let note = try await f.store.manualNote(meetingID: f.id)
            XCTAssertEqual(metadata?.recordingState, .recovered, "A crashed recording never becomes normally completed")
            XCTAssertEqual(metadata?.title, "Original replay meeting")
            XCTAssertEqual(note, originalNote)
            XCTAssertEqual(try Data(contentsOf: f.manifestURL), originalManifest)
            XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent("recovery-report.json")), originalRecovery)
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                let resumed = MeetingTranscriptionReplayCoordinator(store: reopened, models: f.models,
                    recordingsRoot: f.recordings, usage: f.usage, admission: f.admission)
                let second = try await resumed.replay(meetingID: f.id)
                let after = try await reopened.transcript(meetingID: f.id)
                let persistedCheckpoint = try await resumed.checkpoint(meetingID: f.id)
                XCTAssertEqual(after, rows, "Reopening must retain exact committed UUIDs/text/ranges without duplicates")
                XCTAssertTrue(second.insertedSegmentIDs.isEmpty)
                XCTAssertEqual(second.replayedFrameCount, 0)
                XCTAssertEqual(persistedCheckpoint, checkpoint)
                let retained = try await reopened.meeting(id: f.id)
                XCTAssertEqual(retained, metadata)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
            try await f.models.remove(modelID: StreamingEnglishModel.manifest.modelID)
        } catch { await f.cleanup(); throw error }
        await f.cleanup()
    }

    func testActualReplayKeepsManifestGapAndCorruptTailExplicitWithoutCompressingOrInventingAudio() async throws {
        let f = try await ReplayFixture.create(gapAndCorrupt: true)
        do {
            let sourceManifest = try Data(contentsOf: f.manifestURL)
            let report = try await f.coordinator().replay(meetingID: f.id)
            let corrupt = try XCTUnwrap(f.manifest.segments.last)
            XCTAssertEqual(report.gaps.map(\.startSample), [f.prefixFrames, corrupt.startFrame])
            XCTAssertEqual(report.gaps.map(\.endSample), [f.prefixFrames + f.gapFrames, f.timelineEnd])
            XCTAssertEqual(report.gaps.map(\.reason), [.manifestGap, .corruptAudio])
            XCTAssertEqual(report.durableFrameCount, f.manifest.totalFrames - corrupt.frameCount)
            XCTAssertEqual(report.replayedFrameCount, f.manifest.totalFrames - f.prefixFrames - corrupt.frameCount)
            XCTAssertEqual(report.timelineEndSample, f.timelineEnd)
            let rows = try await f.store.transcript(meetingID: f.id)
            XCTAssertEqual(rows.first, f.original)
            XCTAssertEqual(rows.count, 2)
            if rows.count == 2 {
                assertReplaySpeech(rows[1].text)
                XCTAssertEqual(rows[1].startSample, f.prefixFrames + f.gapFrames)
                XCTAssertLessThanOrEqual(rows[1].endSample, corrupt.startFrame)
                for gap in report.gaps {
                    XCTAssertFalse(rows[1].startSample < gap.endSample && rows[1].endSample > gap.startSample)
                }
            }
            let metadata = try await f.store.meeting(id: f.id)
            XCTAssertEqual(metadata?.recordingState, .recovered)
            XCTAssertEqual(metadata?.capturedSampleCount, report.durableFrameCount)
            XCTAssertEqual(try Data(contentsOf: f.manifestURL), sourceManifest)
            let quarantined = f.directory.appendingPathComponent("RecoveryQuarantine")
                .appendingPathComponent(corrupt.relativePath)
            XCTAssertEqual(try? Data(contentsOf: quarantined), f.corruptBytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent(corrupt.relativePath).path))
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
        } catch { await f.cleanup(); throw error }
        await f.cleanup()
    }

    func testActualRegistryExcludesReplayFromRecordingAndDurableDeletionInBothDirections() async throws {
        let f = try await ReplayFixture.create()
        let claimPause = ReplayPause()
        let deletionPause = ReplayPause()
        do {
            let lease = try f.usage.beginRecording(meetingID: f.id)
            do {
                _ = try await f.coordinator().replay(meetingID: f.id)
                XCTFail("An actual recording claim must reject replay before touching files or a model")
            } catch { XCTAssertEqual(error as? TranscriptionReplayError, .meetingInUse) }
            f.usage.endRecording(lease)
            let replay = f.coordinator(afterClaim: { await claimPause.wait() })
            let work = Task { try await replay.replay(meetingID: f.id) }
            let claimed = await replayWait { await claimPause.entered }
            XCTAssertTrue(claimed)
            guard claimed else {
                work.cancel(); await claimPause.release(); _ = try? await work.value
                await f.cleanup(); return
            }
            do { _ = try f.usage.beginRecording(meetingID: f.id); XCTFail("Replay must hold actual shared meeting admission") }
            catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            let deletion = MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.recordings, usage: f.usage)
            do { try await deletion.delete(meetingID: f.id); XCTFail("Replay-owned CAF cannot be deleted concurrently") }
            catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.manifestURL.path))
            work.cancel(); await claimPause.release()
            do { _ = try await work.value; XCTFail("Cancellation must finish the replay claim before deletion") }
            catch is CancellationError { }
            catch { XCTFail("Unexpected cancellation result: \(error)") }
            let heldDeletion = MeetingDeletionCoordinator(store: f.store, recordingsRoot: f.recordings, usage: f.usage,
                beforeMetadataDeletion: { await deletionPause.wait() })
            let removing = Task { try await heldDeletion.delete(meetingID: f.id) }
            let deleting = await replayWait { await deletionPause.entered }
            XCTAssertTrue(deleting, "Actual deletion must hold its durable intent/quarantine claim")
            guard deleting else {
                await deletionPause.release(); _ = try? await removing.value
                await f.cleanup(); return
            }
            do {
                _ = try await f.coordinator().replay(meetingID: f.id)
                XCTFail("Replay must reject a real pending deletion before following the absent original path")
            } catch { XCTAssertEqual(error as? TranscriptionReplayError, .meetingInUse) }
            await deletionPause.release(); try await removing.value
            let removed = try await f.store.meeting(id: f.id)
            XCTAssertNil(removed)
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
        } catch {
            await claimPause.release(); await deletionPause.release()
            await f.cleanup(); throw error
        }
        await f.cleanup()
    }
}

private actor ReplayPause {
    private(set) var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor
private func replayWait(_ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    while !(await condition()) {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
private final class ReplayFixture {
    let root: URL, recordings: URL, directory: URL, database: URL, manifestURL: URL
    let id: UUID, store: SQLiteMeetingStore, models: ModelInstallationManager
    let usage = MeetingUsageRegistry(), admission = HeavyModelAdmission()
    let prefixFrames: Int64 = 16_000
    let gapFrames: Int64
    let manifest: AudioCaptureManifest
    let original: StoredTranscriptSegment
    let corruptBytes = Data("Original synthetic corrupt CAF bytes".utf8)
    var timelineEnd: Int64 { manifest.segments.last.map { $0.startFrame + $0.frameCount } ?? 0 }

    private init(root: URL, id: UUID, store: SQLiteMeetingStore, models: ModelInstallationManager,
                 manifest: AudioCaptureManifest, gapFrames: Int64) {
        self.root = root; self.id = id; self.store = store; self.models = models
        self.manifest = manifest; self.gapFrames = gapFrames
        recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        directory = recordings.appendingPathComponent(id.uuidString, isDirectory: true)
        manifestURL = directory.appendingPathComponent("capture-manifest.json")
        database = root.appendingPathComponent("meetings.sqlite")
        original = .init(id: UUID(), meetingID: id, sequence: 0, startSample: 0, endSample: 16_000,
            text: "Original finalized prefix — preserve.", modelRevision: "synthetic-original-revision")
    }

    static func create(utterances: Int = 1, gapAndCorrupt: Bool = false) async throws -> ReplayFixture {
        let speech = try NativeASRFixture.load()
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-replay-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let id = UUID()
        let recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        let directory = recordings.appendingPathComponent(id.uuidString, isDirectory: true)
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
        var store: SQLiteMeetingStore?
        do {
            _ = try await models.importDirectory(speech.files.encoder.deletingLastPathComponent(), manifest: StreamingEnglishModel.manifest)
            var samples = [Float](repeating: 0, count: 16_000)
            for _ in 0..<utterances { samples += speech.samples + NativeASRFixture.trailingSilence }
            let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 16_000)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            for offset in stride(from: 0, to: samples.count, by: 3_200) {
                let count = min(3_200, samples.count - offset)
                let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
                buffer.frameLength = AVAudioFrameCount(count)
                let target = try XCTUnwrap(buffer.floatChannelData?.pointee)
                for index in 0..<count { target[index] = samples[offset + index] }
                try writer.append(buffer)
            }
            let captured = try writer.finish()
            let gap: Int64 = gapAndCorrupt ? 16_000 : 0
            let manifest = AudioCaptureManifest(schemaVersion: 1, sessionID: id, totalFrames: captured.totalFrames,
                segments: captured.segments.enumerated().map { index, file in
                    .init(relativePath: file.relativePath, startFrame: file.startFrame + (index == 0 ? 0 : gap),
                          frameCount: file.frameCount)
                })
            let database = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
            store = database
            let fixture = ReplayFixture(root: root, id: id, store: database, models: models, manifest: manifest, gapFrames: gap)
            try JSONEncoder().encode(manifest).write(to: fixture.manifestURL, options: .atomic)
            if gapAndCorrupt, let last = manifest.segments.last {
                try fixture.corruptBytes.write(to: directory.appendingPathComponent(last.relativePath))
            }
            try await database.createMeeting(.init(id: id, title: "Original replay meeting",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recovered,
                capturedSampleCount: manifest.totalFrames))
            try await database.appendFinalizedSegments([fixture.original], to: id)
            try await database.saveManualNote(.init(meetingID: id, text: "Original manual replay note.",
                editRevision: 9, modifiedAt: Date(timeIntervalSince1970: 2_000)))
            return fixture
        } catch {
            try? await store?.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func coordinator(afterClaim: (@Sendable () async -> Void)? = nil,
                     afterCheckpoint: (@Sendable (TranscriptionReplayCheckpoint) async -> Void)? = nil) -> MeetingTranscriptionReplayCoordinator {
        if afterClaim != nil || afterCheckpoint != nil {
            return .init(store: store, models: models, recordingsRoot: recordings, usage: usage, admission: admission,
                afterClaim: afterClaim ?? {}, afterCheckpoint: afterCheckpoint)
        }
        return .init(store: store, models: models, recordingsRoot: recordings, usage: usage, admission: admission)
    }

    func cleanup() async {
        try? await store.close()
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.deletingLastPathComponent().standardizedFileURL == parent,
              root.lastPathComponent.hasPrefix("localminutes-replay-test-"), root.resolvingSymlinksInPath() == root,
              UUID(uuidString: String(root.lastPathComponent.dropFirst("localminutes-replay-test-".count))) != nil else {
            XCTFail("Unsafe replay fixture cleanup"); return
        }
        try? FileManager.default.removeItem(at: root)
    }
}

private func replayDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

@MainActor
private func assertReplaySpeech(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
    let expected = NativeASRFixture.reference.lowercased().split { !$0.isLetter }.map(String.init)
    let actual = text.lowercased().split { !$0.isLetter }.map(String.init)
    XCTAssertFalse(actual.isEmpty, file: file, line: line)
    XCTAssertTrue(Set(["concord", "returned", "place", "tents"]).isSubset(of: Set(actual)), file: file, line: line)
    var previous = Array(0...actual.count)
    for (i, word) in expected.enumerated() {
        var next = [i + 1]
        for (j, found) in actual.enumerated() {
            next.append(min(next[j] + 1, previous[j + 1] + 1, previous[j] + (word == found ? 0 : 1)))
        }
        previous = next
    }
    XCTAssertLessThanOrEqual(Double(previous[actual.count]) / Double(expected.count), 0.15, file: file, line: line)
}

/// Separate mandatory MVP2 negatives. The original three-case primitive filter
/// deliberately does not establish checkpoint-integrity completion.
@MainActor
final class TranscriptionReplayCheckpointIntegrityTests: XCTestCase {
    func testCursorOnlyJumpToTimelineEndCannotSkipRemainingActualSpeechAfterReopen() async throws {
        let f = try await ReplayFixture.create(utterances: 2)
        do {
            let legitimate = try await interruptedAfterRealCheckpoint(f)
            let committed = try await f.store.transcript(meetingID: f.id)
            XCTAssertEqual(committed.count, 2)
            let original = try captureSources(f)
            let metadata = try await f.store.meeting(id: f.id)
            let note = try await f.store.manualNote(meetingID: f.id)
            let url = f.directory.appendingPathComponent("transcription-replay.json")
            var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: legitimate) as? [String: Any])
            let originalPoint = try XCTUnwrap(object["checkpoint"] as? [String: Any])
            var changedPoint = originalPoint
            XCTAssertLessThan((originalPoint["nextGlobalSample"] as? NSNumber)?.int64Value ?? Int64.max, f.timelineEnd)
            changedPoint["nextGlobalSample"] = f.timelineEnd
            object["checkpoint"] = changedPoint
            // Every existing model/row/manifest/recovery binding remains intact.
            let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try PersistentFilePolicy.writeAtomically(tampered, to: url, within: f.directory)
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                let replay = MeetingTranscriptionReplayCoordinator(store: reopened, models: f.models,
                    recordingsRoot: f.recordings, usage: f.usage, admission: f.admission)
                do {
                    _ = try await replay.replay(meetingID: f.id)
                    XCTFail("Changing only the replay cursor must not authorize skipping untranscribed durable speech")
                } catch { XCTAssertEqual(error as? TranscriptionReplayError, .invalidCheckpoint) }
                let after = try await reopened.transcript(meetingID: f.id)
                let afterMeeting = try await reopened.meeting(id: f.id)
                let afterNote = try await reopened.manualNote(meetingID: f.id)
                XCTAssertEqual(after, committed); XCTAssertEqual(afterMeeting, metadata); XCTAssertEqual(afterNote, note)
                XCTAssertEqual(try captureSources(f), original)
                XCTAssertEqual(f.admission.snapshot().phase, .idle)
                try PersistentFilePolicy.writeAtomically(legitimate, to: url, within: f.directory)
                _ = try await replay.replay(meetingID: f.id)
                let resumed = try await reopened.transcript(meetingID: f.id)
                XCTAssertEqual(resumed.count, 3, "A valid checkpoint must still replay the second real utterance")
                XCTAssertEqual(Array(resumed.prefix(committed.count)), committed)
                for row in resumed.dropFirst() { assertReplaySpeech(row.text) }
                XCTAssertEqual(try captureSources(f), original)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { await f.cleanup(); throw error }
        await f.cleanup()
    }

    func testOmittedCheckpointModelRevisionIsRejectedWithoutSourceOrOriginalRowMutation() async throws {
        let f = try await ReplayFixture.create(utterances: 2)
        do {
            let legitimate = try await interruptedAfterRealCheckpoint(f)
            let committed = try await f.store.transcript(meetingID: f.id)
            let original = try captureSources(f)
            let url = f.directory.appendingPathComponent("transcription-replay.json")
            var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: legitimate) as? [String: Any])
            var point = try XCTUnwrap(object["checkpoint"] as? [String: Any])
            point.removeValue(forKey: "modelRevision")
            object["checkpoint"] = point
            try PersistentFilePolicy.writeAtomically(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                to: url, within: f.directory)
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                let replay = MeetingTranscriptionReplayCoordinator(store: reopened, models: f.models,
                    recordingsRoot: f.recordings, usage: f.usage, admission: f.admission)
                do { _ = try await replay.replay(meetingID: f.id); XCTFail("A checkpoint without its model pin is not replay authority") }
                catch { XCTAssertEqual(error as? TranscriptionReplayError, .invalidCheckpoint) }
                let rows = try await reopened.transcript(meetingID: f.id)
                XCTAssertEqual(rows, committed); XCTAssertEqual(rows.first, f.original)
                XCTAssertEqual(try captureSources(f), original)
                XCTAssertEqual(f.admission.snapshot().phase, .idle)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { await f.cleanup(); throw error }
        await f.cleanup()
    }

    private func interruptedAfterRealCheckpoint(_ f: ReplayFixture) async throws -> Data {
        let pause = ReplayPause()
        let prefix = f.prefixFrames, end = f.timelineEnd
        let replay = f.coordinator(afterCheckpoint: { point in
            if point.nextGlobalSample > prefix && point.nextGlobalSample < end { await pause.wait() }
        })
        let work = Task { try await replay.replay(meetingID: f.id) }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !(await pause.entered), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let entered = await pause.entered
            XCTAssertTrue(entered, "The integrity fixture needs a real row+checkpoint after the first actual ASR utterance")
            guard entered else { throw TranscriptionReplayError.invalidCheckpoint }
            let rows = try await f.store.transcript(meetingID: f.id)
            XCTAssertEqual(rows.count, 2); XCTAssertEqual(rows.first, f.original)
            if rows.count == 2 { assertReplaySpeech(rows[1].text) }
            let bytes = try Data(contentsOf: f.directory.appendingPathComponent("transcription-replay.json"))
            work.cancel(); await pause.release()
            do { _ = try await work.value; XCTFail("Cancelled replay unexpectedly completed") }
            catch is CancellationError { }
            catch { XCTFail("Expected cancellation after real checkpoint cleanup") }
            XCTAssertEqual(f.admission.snapshot().phase, .idle)
            return bytes
        } catch {
            work.cancel(); await pause.release(); _ = try? await work.value
            throw error
        }
    }

    private func captureSources(_ f: ReplayFixture) throws -> [String: String] {
        var sources: [String: String] = [:]
        for file in f.manifest.segments.map(\.relativePath) + ["capture-manifest.json", "recovery-report.json"] {
            sources[file] = replayDigest(try Data(contentsOf: f.directory.appendingPathComponent(file)))
        }
        return sources
    }
}
