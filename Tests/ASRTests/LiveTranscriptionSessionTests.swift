import AVFoundation
import Dispatch
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
@testable import LocalMinutesTranscription

@MainActor
final class LiveTranscriptionSessionTests: XCTestCase {
    func testLargeConvertedBufferIsSplitIntoBoundedNativeChunksWithoutLosingSpeech() async throws {
        let h = try await LiveSessionFixture.create()
        do {
            let id = UUID()
            guard case .ready(let directory) = await h.session.prepare(sessionID: id) else {
                XCTFail("Actual model preparation failed"); await h.cleanup(); return
            }
            // A native callback can exceed its requested frame-size hint. The
            // actual 16k converter can therefore return more than200ms at once.
            let manifest = try feed(h.speech.samples, session: h.session, directory: directory, id: id, chunkSize: 6_400)
            let failure = await h.session.finish(sessionID: id, manifest: manifest)
            XCTAssertNil(failure)
            XCTAssertEqual(h.session.transcript.receivedSampleCount, Int64(h.speech.samples.count))
            let rows = try await h.store.transcript(meetingID: id)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.text.lowercased().split(separator: " ").last, "tents")
        } catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    func testActualSpeechStreamsBeforeStopAndFinalTextSurvivesSQLiteReopen() async throws {
        let h = try await LiveSessionFixture.create()
        do {
            let id = UUID()
            let prepared = await h.session.prepare(sessionID: id)
            guard case .ready(let directory) = prepared else {
                XCTFail("A verified actual CPU model must establish live readiness")
                await h.cleanup(); return
            }
            let leaseHeld: Bool
            do { try await h.models.remove(modelID: StreamingEnglishModel.manifest.modelID); leaseHeld = false }
            catch { leaseHeld = (error as? ModelInstallationError) == .modelInUse }
            XCTAssertTrue(leaseHeld, "The running native model must retain its installation")
            let audio = h.speech.samples + NativeASRFixture.trailingSilence
            let manifest = try feed(audio, session: h.session, directory: directory, id: id)
            let live = await waitForText(h.session)
            XCTAssertTrue(live, "Actual inference must publish text before recording finishes")
            let failure = await h.session.finish(sessionID: id, manifest: manifest)
            XCTAssertNil(failure)
            let snapshot = h.session.transcript
            XCTAssertEqual(snapshot.receivedSampleCount, Int64(audio.count))
            XCTAssertEqual(snapshot.partial, "")
            XCTAssertEqual(snapshot.finalized.count, 1, "An endpoint plus final flush must not duplicate text")
            let stored = try await h.store.transcript(meetingID: id)
            XCTAssertEqual(stored, snapshot.finalized)
            XCTAssertEqual(stored.first?.text.lowercased().split(separator: " ").last, "tents")
            XCTAssertEqual(stored.first?.startSample, 0)
            XCTAssertEqual(stored.first?.modelRevision, NativeASRFixture.revision)
            let metadata = try await h.store.meeting(id: id)
            XCTAssertEqual(metadata?.recordingState, .completed)
            XCTAssertEqual(metadata?.capturedSampleCount, Int64(audio.count))
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            let persisted = try await reopened.transcript(meetingID: id)
            XCTAssertEqual(persisted, stored)
            try await reopened.close()
            try await h.models.remove(modelID: StreamingEnglishModel.manifest.modelID)
            let removed = try await h.models.current(modelID: StreamingEnglishModel.manifest.modelID)
            XCTAssertNil(removed, "Native teardown must release the lease after the flush")
        } catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    func testTwoActualUtterancesHaveOrderedGlobalRangesWithoutResetDuplication() async throws {
        let h = try await LiveSessionFixture.create()
        do {
            let id = UUID()
            guard case .ready(let directory) = await h.session.prepare(sessionID: id) else {
                XCTFail("Actual model preparation failed"); await h.cleanup(); return
            }
            let audio = h.speech.samples + NativeASRFixture.trailingSilence + h.speech.samples
            let manifest = try feed(audio, session: h.session, directory: directory, id: id)
            let failure = await h.session.finish(sessionID: id, manifest: manifest)
            XCTAssertNil(failure)
            let rows = try await h.store.transcript(meetingID: id)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows.map(\.sequence), [0, 1])
            if rows.count == 2 {
                XCTAssertEqual(rows[0].text, rows[1].text)
                XCTAssertGreaterThan(rows[1].startSample, rows[0].startSample)
                XCTAssertGreaterThanOrEqual(rows[1].startSample, rows[0].endSample)
                XCTAssertEqual(rows[1].endSample, Int64(audio.count))
            }
            XCTAssertEqual(h.session.transcript.receivedSampleCount, Int64(audio.count))
        } catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    func testMissingVerifiedModelCreatesNoMeetingAndNoRecordingDirectory() async throws {
        let h = try await LiveSessionFixture.create(installModel: false)
        let result = await h.session.prepare(sessionID: UUID())
        XCTAssertEqual(result, .rejected(.modelUnavailable))
        let history = try await h.store.history()
        XCTAssertTrue(history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.meetings.path))
        XCTAssertNil(h.session.transcript.sessionID)
        await h.cleanup()
    }

    private func feed(_ samples: [Float], session: LiveTranscriptionSession,
                      directory: URL, id: UUID, chunkSize: Int = 1_600) throws -> AudioCaptureManifest {
        let sink = try XCTUnwrap(session.normalizedSink)
        let writer = try SegmentCAFWriter(directory: directory, sessionID: id)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        for start in stride(from: 0, to: samples.count, by: chunkSize) {
            let count = min(chunkSize, samples.count - start)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            let plane = try XCTUnwrap(buffer.floatChannelData?.pointee)
            for index in 0..<count { plane[index] = samples[start + index] }
            try writer.append(buffer)
            XCTAssertTrue(sink.offer(buffer, sourceStartSample: Int64(start)))
        }
        return try writer.finish()
    }

    private func waitForText(_ session: LiveTranscriptionSession) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while session.transcript.partial.isEmpty && session.transcript.finalized.isEmpty {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

@MainActor
private final class LiveSessionFixture {
    let root: URL
    let database: URL
    let meetings: URL
    let models: ModelInstallationManager
    let store: SQLiteMeetingStore
    let session: LiveTranscriptionSession
    let speech: NativeASRFixture

    private init(root: URL, models: ModelInstallationManager,
                 store: SQLiteMeetingStore, speech: NativeASRFixture) {
        self.root = root; self.models = models; self.store = store; self.speech = speech
        database = root.appendingPathComponent("meetings.sqlite")
        meetings = root.appendingPathComponent("meetings", isDirectory: true)
        session = LiveTranscriptionSession(models: models, store: store, meetingsDirectory: meetings)
    }

    static func create(installModel: Bool = true) async throws -> LiveSessionFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-live-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("models"), availableBytes: { _ in .max })
        let speech = try NativeASRFixture.load()
        if installModel {
            _ = try await models.importDirectory(speech.files.encoder.deletingLastPathComponent(),
                                                manifest: StreamingEnglishModel.manifest)
        }
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        return LiveSessionFixture(root: root, models: models, store: store, speech: speech)
    }

    func cleanup() async {
        if let id = session.transcript.sessionID { _ = await session.finish(sessionID: id, manifest: nil) }
        try? await store.close()
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.lastPathComponent.hasPrefix("localminutes-live-test-"),
              root.deletingLastPathComponent().standardizedFileURL == parent,
              root.resolvingSymlinksInPath() == root else { XCTFail("Unsafe fixture cleanup"); return }
        try? FileManager.default.removeItem(at: root)
    }
}

// APPEND to Tests/ASRTests/LiveTranscriptionSessionTests.swift after its existing
// private fixture. Add import Dispatch to that file's import section.

private struct LiveMetricsTestClock: MetricsMonotonicClock {
    func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

@MainActor
extension LiveTranscriptionSessionTests {
    func testActualCPUConsumerPublishesPrivateMonotonicProgressBeforeFinalFlush() async throws {
        let h = try await LiveSessionFixture.create()
        guard let source = ProcessInfo.processInfo.environment["GITHUB_SHA"], source.count == 40,
              source.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            XCTFail("Mandatory actual source SHA is missing; setup failure is not metrics RED")
            await h.cleanup()
            throw MetricsASRDraftError.missingSourceIdentity
        }
        let identity = MetricsBuildIdentity(
            sourceCommit: source,
            modelRevision: NativeASRFixture.revision, runtimeVersion: "1.13.8", buildNumber: 1)
        let metrics = try TranscriptionMetricsRecorder(identity: identity, capacity: 128, clock: LiveMetricsTestClock())
        let session = LiveTranscriptionSession(models: h.models, store: h.store,
                                               meetingsDirectory: h.meetings, metrics: metrics)
        var activeID: UUID?
        do {
            let id = UUID()
            guard case .ready(let directory) = await session.prepare(sessionID: id) else {
                XCTFail("Actual pinned recognizer preparation must work before metrics assertions")
                throw MetricsASRDraftError.preparationFailed
            }
            activeID = id
            // A test marker exercises capture of visibility facts. It does not
            // put macOS into an iPhone Lock Screen or prove locked operation.
            try metrics.visibilityChanged(.background)
            let audio = h.speech.samples + NativeASRFixture.trailingSilence
            let manifest = try feed(audio, session: session, directory: directory, id: id)
            let hasText = await waitForText(session)
            XCTAssertTrue(hasText, "The actual CPU consumer must publish speech before finalization")
            try metrics.checkpoint()
            let before = metrics.snapshot()
            XCTAssertGreaterThan(before.processedSampleCount, 0,
                "An injected recorder must observe actual consumer progress, not only an exported test snapshot")
            XCTAssertGreaterThan(before.capturedSampleCount, 0)
            XCTAssertGreaterThan(before.processingWallNanoseconds, 0)
            XCTAssertGreaterThan(before.peakQueueDepth, 0)
            XCTAssertTrue(before.realTimeFactor.map { $0.isFinite && $0 > 0 } ?? false)
            let failure = await session.finish(sessionID: id, manifest: manifest)
            activeID = nil
            XCTAssertNil(failure)
            try metrics.checkpoint()
            let after = metrics.snapshot()
            XCTAssertEqual(after.capturedSampleCount, Int64(audio.count))
            XCTAssertEqual(after.processedSampleCount, Int64(audio.count))
            XCTAssertGreaterThan(after.processingWallNanoseconds, 0)
            XCTAssertGreaterThan(after.partialLatency.sampleCount, 0)
            XCTAssertGreaterThan(after.finalLatency.sampleCount, 0)
            XCTAssertTrue(after.errors.isEmpty)
            XCTAssertEqual(after.identity, identity)
            XCTAssertTrue(after.checkpoints.contains {
                $0.visibility == .background && $0.processedSampleCount > 0
            })
            let times = after.checkpoints.map(\.monotonicNanoseconds)
            XCTAssertEqual(times, times.sorted())
            let rows = try await h.store.transcript(meetingID: id)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.text.lowercased().split(separator: " ").last, "tents")
            let data: Data
            do { data = try MetricsExportCodec.encode(after) }
            catch {
                XCTFail("Actual consumer facts need a privacy-safe checkpoint: \(type(of: error))")
                await h.cleanup(); return
            }
            let checkpoint = h.root.appendingPathComponent("metrics-checkpoint.json")
            try data.write(to: checkpoint, options: .atomic)
            let reopened = try MetricsExportCodec.decodeValidated(Data(contentsOf: checkpoint))
            XCTAssertEqual(reopened, after)
            XCTAssertLessThanOrEqual(data.count, 65_536)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertFalse(json.contains(h.root.path))
            XCTAssertFalse(json.lowercased().contains(NativeASRFixture.reference.lowercased()))
            for row in rows where !row.text.isEmpty {
                XCTAssertFalse(json.contains(row.text), "Actual recognized content must never enter metrics JSON")
            }
        } catch {
            if let activeID { _ = await session.finish(sessionID: activeID, manifest: nil) }
            await h.cleanup()
            throw error
        }
        await h.cleanup()
    }
}

private enum MetricsASRDraftError: Error { case preparationFailed, missingSourceIdentity }


// APPEND this entire fragment to Tests/ASRTests/LiveTranscriptionSessionTests.swift
// after its existing LiveSessionFixture declaration. Add the import and package
// dependency documented in README. Private existing helpers remain unchanged.

@MainActor
private final class T12SpeechPermission: CapturePermissionSource {
    func requestRecordPermission() async -> Bool { true }
}

@MainActor
private final class T12SpeechHardware: CaptureHardware {
    let format: AVAudioFormat
    private(set) var tap: CaptureTapHandler?
    private(set) var active = false
    private(set) var running = false
    init() throws {
        format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    }
    func activateSession() throws { active = true }
    func inputFormat() throws -> AVAudioFormat { format }
    func installTap(_ handler: @escaping CaptureTapHandler) throws { tap = handler }
    func startEngine() throws { running = true }
    func stopEngine() { running = false }
    func removeTap() { tap = nil }
    func deactivateSession() throws { active = false }
    func emit(_ samples: ArraySlice<Float>, start: Int64) throws {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                  frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let target = try XCTUnwrap(buffer.floatChannelData?[0])
        for (index, sample) in samples.enumerated() { target[index] = sample }
        let callback = try XCTUnwrap(tap)
        callback(buffer, AVAudioTime(sampleTime: 10_000 + start, atRate: 16_000))
    }
}

@MainActor
private final class T12SpeechActivity: LiveActivityHandle {
    private(set) var state: LiveActivityResourceState = .active
    private var observer: LiveActivityStateObserver?
    private var release: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { release != nil }
    func setStateObserver(_ observer: LiveActivityStateObserver?) { self.observer = observer }
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome { .applied }
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        if !released { await withCheckedContinuation { release = $0 } }
        state = .ended
        observer?(.ended)
        return .applied
    }
    func releaseEnd() {
        released = true
        let continuation = release
        release = nil
        continuation?.resume()
    }
}

@MainActor
private final class T12SpeechActivityBackend: LiveActivityBackend {
    let handle = T12SpeechActivity()
    var areActivitiesEnabled: Bool { true }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle { handle }
}

@MainActor
private final class T12SpeechCompletion { var finished = false }

@MainActor
private func t12SpeechEventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(12))
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
private func t12CleanupSpeech(_ h: LiveSessionFixture, owner: RecordingSessionOwner,
                             activity: T12SpeechActivityBackend) async {
    activity.handle.releaseEnd()
    let stopped = T12SpeechCompletion()
    let stopping = Task { await owner.stop(); stopped.finished = true }
    guard await t12SpeechEventually({ stopped.finished }) else {
        stopping.cancel()
        XCTFail("Interruption fixture cleanup did not settle; retain its owned native files")
        return
    }
    await stopping.value
    let state = await owner.snapshot()
    guard !state.cleanupPending, !state.readiness.audioSessionActive else {
        XCTFail("Interruption fixture still has live resources; retain the owned files")
        return
    }
    await h.cleanup()
}

@MainActor
extension LiveTranscriptionSessionTests {
    func testOwnerInterruptionDrainsActualSpeechAndPersistsInterruptedWithoutSavedSuccess() async throws {
        let hardware = try T12SpeechHardware()
        let h = try await LiveSessionFixture.create()
        let id = UUID()
        let activity = T12SpeechActivityBackend()
        let usage = MeetingUsageRegistry()
        let owner = RecordingSessionOwner(permission: T12SpeechPermission(), hardware: hardware,
            activityBackend: activity, preparation: h.session, usageAdmission: usage)
        do {
            let started = T12SpeechCompletion()
            let start = Task { await owner.start(sessionID: id); started.finished = true }
            guard await t12SpeechEventually({ started.finished }) else {
                start.cancel(); XCTFail("Actual native speech preparation did not finish");
                throw T12SpeechInterruptionDraftError.timedOut
            }
            await start.value
            for offset in stride(from: 0, to: h.speech.samples.count, by: 1_600) {
                let end = min(offset + 1_600, h.speech.samples.count)
                try hardware.emit(h.speech.samples[offset..<end], start: Int64(offset))
                // Test-source pacing lets the real bounded capture worker drain;
                // it is neither an audio-callback wait nor a performance proof.
                try await Task.sleep(for: .milliseconds(12))
            }
            let recording = await t12SpeechEventually { await owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            let textBeforeStop = await waitForText(h.session)
            XCTAssertTrue(textBeforeStop, "Licensed speech must reach the actual CPU recognizer before interruption")
            do {
                try await h.models.remove(modelID: StreamingEnglishModel.manifest.modelID)
                XCTFail("The native model must remain leased during live inference")
            } catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
            let interrupted = T12SpeechCompletion()
            let interruption = Task { await owner.interrupt(sessionID: id); interrupted.finished = true }
            let reached = await t12SpeechEventually { activity.handle.isWaiting || interrupted.finished }
            XCTAssertTrue(reached)
            XCTAssertTrue(activity.handle.isWaiting,
                "Interruption must join real CAF/ASR/SQLite flush before entering the Activity cleanup barrier")
            let pending = await owner.snapshot()
            XCTAssertEqual(pending.phase, .interrupted)
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertNil(owner.completedManifest)
            XCTAssertFalse(hardware.active)
            XCTAssertFalse(hardware.running)
            XCTAssertThrowsError(try usage.beginRecording(meetingID: id),
                "Deletion/recording usage stays held until Activity cleanup also settles")
            let during = try await h.store.meeting(id: id)
            XCTAssertEqual(during?.recordingState, .interrupted)
            XCTAssertEqual(during?.capturedSampleCount, Int64(h.speech.samples.count))
            activity.handle.releaseEnd()
            let settled = await t12SpeechEventually { interrupted.finished }
            XCTAssertTrue(settled)
            if settled { await interruption.value } else { interruption.cancel() }
            let final = await owner.snapshot()
            XCTAssertEqual(final.phase, .interrupted)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertNil(final.failure)
            XCTAssertNil(owner.completedManifest, "Interrupted audio cannot be presented as Recording saved")
            let rows = try await h.store.transcript(meetingID: id)
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.map(\.sequence), [0])
            let words = rows.flatMap { $0.text.lowercased().split { !$0.isLetter }.map(String.init) }
            XCTAssertEqual(words, NativeASRFixture.reference.lowercased().split(separator: " ").map(String.init),
                "Actual final inference must retain the licensed reference including final TENTS")
            XCTAssertEqual(h.session.transcript.receivedSampleCount, Int64(h.speech.samples.count))
            let directory = h.meetings.appendingPathComponent(id.uuidString)
            let manifestData = try? Data(contentsOf: directory.appendingPathComponent("capture-manifest.json"))
            XCTAssertNotNil(manifestData)
            if let manifestData {
                let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: manifestData)
                XCTAssertEqual(manifest.totalFrames, Int64(h.speech.samples.count))
                var decoded: Int64 = 0
                for segment in manifest.segments {
                    let file = try AVAudioFile(forReading: directory.appendingPathComponent(segment.relativePath))
                    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                        frameCapacity: AVAudioFrameCount(segment.frameCount)))
                    try file.read(into: buffer)
                    decoded += Int64(buffer.frameLength)
                }
                XCTAssertEqual(decoded, manifest.totalFrames)
            }
            do {
                let lease = try usage.beginRecording(meetingID: id)
                usage.endRecording(lease)
            } catch { XCTFail("Combined interruption cleanup must release the exact usage lease") }
            do { try await h.models.remove(modelID: StreamingEnglishModel.manifest.modelID) }
            catch { XCTFail("Completed native teardown must release its model lease") }
            if final.phase == .interrupted, !final.cleanupPending {
                try await h.store.close()
                let reopened = try SQLiteMeetingStore(databaseURL: h.database)
                do {
                    let stored = try await reopened.meeting(id: id)
                    XCTAssertEqual(stored?.recordingState, .interrupted)
                    XCTAssertEqual(stored?.capturedSampleCount, Int64(h.speech.samples.count))
                    let persisted = try await reopened.transcript(meetingID: id)
                    XCTAssertEqual(persisted, rows)
                    try await reopened.close()
                } catch { try? await reopened.close(); throw error }
            }
        } catch {
            await t12CleanupSpeech(h, owner: owner, activity: activity)
            throw error
        }
        await t12CleanupSpeech(h, owner: owner, activity: activity)
    }
}

private enum T12SpeechInterruptionDraftError: Error { case timedOut }


// APPEND to Tests/ASRTests/LiveTranscriptionSessionTests.swift, preserving its
// private real-model fixture, feed, LiveMetricsTestClock and existing assertions.
// Runs in the hosted actual-ASR core suite, never a fake recognizer or device gate.
@MainActor
extension LiveTranscriptionSessionTests {
    func testActualSequentialMeetingsReuseOneSessionWithIndependentMetricsEpochs() async throws {
        let h = try await LiveSessionFixture.create()
        guard let source = ProcessInfo.processInfo.environment["GITHUB_SHA"], source.count == 40,
              source.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            XCTFail("The hosted actual source identity is required; missing setup is not RED")
            await h.cleanup()
            throw MetricsASRDraftError.missingSourceIdentity
        }
        let identity = MetricsBuildIdentity(sourceCommit: source, modelRevision: NativeASRFixture.revision,
            runtimeVersion: "1.13.8", buildNumber: 1)
        let metrics = try TranscriptionMetricsRecorder(identity: identity, capacity: 128, clock: LiveMetricsTestClock())
        let session = LiveTranscriptionSession(models: h.models, store: h.store,
            meetingsDirectory: h.meetings, metrics: metrics)
        var activeID: UUID?
        do {
            let firstID = UUID()
            guard case .ready(let firstDirectory) = await session.prepare(sessionID: firstID) else {
                XCTFail("First actual pinned recognizer must prepare")
                throw MetricsASRDraftError.preparationFailed
            }
            activeID = firstID
            let firstAudio = h.speech.samples + NativeASRFixture.trailingSilence
            let firstManifest = try feed(firstAudio, session: session, directory: firstDirectory, id: firstID)
            let firstFailure = await session.finish(sessionID: firstID, manifest: firstManifest)
            activeID = nil
            XCTAssertNil(firstFailure)
            let first = metrics.snapshot()
            XCTAssertEqual(first.capturedSampleCount, firstManifest.totalFrames)
            XCTAssertEqual(first.processedSampleCount, firstManifest.totalFrames)
            XCTAssertTrue(first.errors.isEmpty)

            let secondID = UUID()
            guard case .ready(let secondDirectory) = await session.prepare(sessionID: secondID) else {
                XCTFail("The same application-owned live session must support another meeting")
                throw MetricsASRDraftError.preparationFailed
            }
            activeID = secondID
            let secondAudio = firstAudio + [Float](repeating: 0, count: 1_600)
            let secondManifest = try feed(secondAudio, session: session, directory: secondDirectory, id: secondID)
            XCTAssertNotEqual(secondManifest.totalFrames, firstManifest.totalFrames,
                "Different lengths make a stale first-epoch snapshot observable")
            let secondFailure = await session.finish(sessionID: secondID, manifest: secondManifest)
            activeID = nil
            XCTAssertNil(secondFailure, "Instrumentation cannot break healthy actual ASR or persistence")
            let second = metrics.snapshot()
            XCTAssertEqual(second.capturedSampleCount, secondManifest.totalFrames)
            XCTAssertEqual(second.processedSampleCount, secondManifest.totalFrames)
            XCTAssertTrue(second.errors.isEmpty, "A new meeting's sample0 is valid for its new metrics epoch")
            XCTAssertGreaterThan(second.processingWallNanoseconds, 0)
            XCTAssertGreaterThan(second.finalLatency.sampleCount, 0)
            XCTAssertEqual(second.identity, identity)
            XCTAssertEqual(session.transcript.sessionID, secondID)
            XCTAssertEqual(session.transcript.receivedSampleCount, secondManifest.totalFrames)
            let firstRows = try await h.store.transcript(meetingID: firstID)
            let secondRows = try await h.store.transcript(meetingID: secondID)
            XCTAssertEqual(firstRows.count, 1); XCTAssertEqual(secondRows.count, 1)
            XCTAssertEqual(firstRows.first?.text.lowercased().split(separator: " ").last, "tents")
            XCTAssertEqual(secondRows.first?.text.lowercased().split(separator: " ").last, "tents")
            XCTAssertEqual(secondRows.first?.meetingID, secondID)
            XCTAssertEqual(secondRows.first?.modelRevision, NativeASRFixture.revision)
        } catch {
            if let activeID { _ = await session.finish(sessionID: activeID, manifest: nil) }
            await h.cleanup()
            throw error
        }
        await h.cleanup()
    }
}
