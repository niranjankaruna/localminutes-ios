import AVFoundation
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
@testable import LocalMinutesTranscription

@MainActor
final class LiveTranscriptionSessionTests: XCTestCase {
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
                      directory: URL, id: UUID) throws -> AudioCaptureManifest {
        let sink = try XCTUnwrap(session.normalizedSink)
        let writer = try SegmentCAFWriter(directory: directory, sessionID: id)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        for start in stride(from: 0, to: samples.count, by: 1_600) {
            let count = min(1_600, samples.count - start)
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
