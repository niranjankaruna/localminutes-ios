#if os(iOS)
import AVFoundation
import Foundation
import XCTest
@testable import LocalMinutes

// Actual app composition, SQLite and CAF files. The speech installation is
// genuinely absent: no network, fake model, permission grant or inference double.
// These tests do not establish physical recording, encryption or locked startup.
private enum NativeStartupTestError: Error { case timedOut }

@MainActor
private final class NativeStartupResult<Value: Sendable> { var value: Result<Value, Error>? }

@MainActor
private func nativeStartupEventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(3))
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

@MainActor
private final class NativeStartupFixture {
    let parent: URL
    let root: URL
    let database: URL
    let services: LocalMinutesServices
    let application: RecordingApplication

    init() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-native-startup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        self.parent = parent; self.root = root
        database = root.appendingPathComponent("meetings.sqlite")
        let services = try LocalMinutesServices(rootURL: root)
        self.services = services
        application = RecordingApplication(services: services)
    }

    func directory(_ id: UUID) -> URL {
        services.meetingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func seedInterruptedMeeting(_ id: UUID) async throws -> [String: Data] {
        try await services.store.createMeeting(MeetingRecord(id: id, title: "Original native interrupted fixture",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .interrupted))
        let writer = try SegmentCAFWriter(directory: directory(id), sessionID: id, maximumSegmentFrames: 32)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32))
        buffer.frameLength = 32
        try XCTUnwrap(buffer.floatChannelData?[0]).update(repeating: 0.25, count: 32)
        try writer.append(buffer)
        let manifest = try writer.finish()
        XCTAssertEqual(manifest.totalFrames, 32)
        let files = manifest.segments.map(\.relativePath) + ["capture-manifest.json"]
        return try Dictionary(uniqueKeysWithValues: files.map {
            ($0, try Data(contentsOf: directory(id).appendingPathComponent($0)))
        })
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        let result = NativeStartupResult<Void>()
        let stopping = Task { @MainActor in
            await application.owner?.stop()
            result.value = .success(())
        }
        guard await nativeStartupEventually({ result.value != nil }) else {
            stopping.cancel()
            XCTFail("App owner cleanup did not settle; retain its owned fixture", file: file, line: line); return
        }
        await stopping.value
        if let state = await application.owner?.snapshot(),
           state.cleanupPending || state.readiness.audioSessionActive {
            XCTFail("App resources still own the fixture", file: file, line: line); return
        }
        do { try await services.store.close() }
        catch { XCTFail("Actual fixture database did not close", file: file, line: line); return }
        guard root.lastPathComponent.hasPrefix("localminutes-native-startup-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath() == parent,
              root.resolvingSymlinksInPath() == root else {
            XCTFail("Refuse cleanup outside generated native fixture root", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned native startup fixture cleanup failed", file: file, line: line) }
    }
}

@MainActor
final class NativeStartupIntegrationTests: XCTestCase {
    private func withFixture(_ body: @MainActor (NativeStartupFixture) async throws -> Void) async throws {
        let h = try NativeStartupFixture()
        do { try await body(h) }
        catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    private func performStart(_ h: NativeStartupFixture, id: UUID) async throws -> RecordingIntentOutcome {
        let result = NativeStartupResult<RecordingIntentOutcome>()
        let task = Task { @MainActor in
            do { result.value = .success(try await h.application.perform(.start(id))) }
            catch { result.value = .failure(error) }
        }
        guard await nativeStartupEventually({ result.value != nil }) else {
            task.cancel()
            XCTFail("Actual absent-model startup must settle without an OS microphone prompt")
            throw NativeStartupTestError.timedOut
        }
        await task.value
        // A foreground-required SDK error is not expected in either fixture:
        // model absence is a block; global startup failure precedes owner use.
        return try XCTUnwrap(result.value).get()
    }

    func testAppStartReconcilesInterruptedCAFBeforeRealMissingModelRejection() async throws {
        try await withFixture { h in
            let interrupted = UUID()
            let original = try await h.seedInterruptedMeeting(interrupted)
            XCTAssertTrue(h.application.services === h.services)
            XCTAssertEqual(h.services.startup.state, .notStarted)
            let model = try await h.services.models.current(modelID: StreamingEnglishModel.manifest.modelID)
            XCTAssertNil(model, "The actual default recognizer preflight must see a genuinely absent model")
            let requested = UUID()
            let outcome = try await self.performStart(h, id: requested)
            XCTAssertEqual(outcome, .blocked(.modelUnavailable))
            XCTAssertEqual(h.application.lastOutcome, .blocked(.modelUnavailable))
            XCTAssertEqual(h.services.startup.state, .ready)
            XCTAssertEqual(h.services.startup.report?.recoveredMeetingIDs, [interrupted])
            XCTAssertEqual(h.services.startup.report?.deletedMeetingIDs, [])
            XCTAssertEqual(h.services.startup.report?.issues, [])
            let row = try await h.services.store.meeting(id: interrupted)
            XCTAssertEqual(row?.recordingState, .recovered)
            XCTAssertEqual(row?.capturedSampleCount, 32)
            XCTAssertEqual(row?.title, "Original native interrupted fixture")
            let rejected = try await h.services.store.meeting(id: requested)
            XCTAssertNil(rejected, "A missing real model must not create a new recording row")
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory(requested).path))
            let owner = try XCTUnwrap(h.application.owner)
            let state = await owner.snapshot()
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(state.readiness.audioSessionActive)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(state.readiness.activityActive)
            XCTAssertNil(h.application.owner?.completedManifest)
            for (name, bytes) in original {
                XCTAssertEqual(try Data(contentsOf: h.directory(interrupted).appendingPathComponent(name)), bytes)
            }
            let reportURL = h.directory(interrupted).appendingPathComponent("recovery-report.json")
            let persistedReport = try? Data(contentsOf: reportURL)
            XCTAssertNotNil(persistedReport, "App Start must durably reconcile the old audio before returning")
            if let persistedReport {
                let report = try JSONDecoder().decode(MeetingRecoveryReport.self, from: persistedReport)
                XCTAssertEqual(report.meetingID, interrupted)
                XCTAssertEqual(report.durableFrameCount, 32)
                XCTAssertEqual(report.timelineEndSample, 32)
                XCTAssertTrue(report.gaps.isEmpty)
                XCTAssertTrue(report.quarantinedFiles.isEmpty)
            }
            try await h.services.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            do {
                let durable = try await reopened.meeting(id: interrupted)
                XCTAssertEqual(durable?.recordingState, .recovered)
                XCTAssertEqual(durable?.capturedSampleCount, 32)
                let transcript = try await reopened.transcript(meetingID: interrupted)
                XCTAssertTrue(transcript.isEmpty, "Startup reconciliation cannot fabricate model output")
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }

    func testClosedDatabaseStartupFailureLeavesOwnerIdleAndRefusesModelPreflight() async throws {
        try await withFixture { h in
            let interrupted = UUID()
            let original = try await h.seedInterruptedMeeting(interrupted)
            let model = try await h.services.models.current(modelID: StreamingEnglishModel.manifest.modelID)
            XCTAssertNil(model)
            try await h.services.store.close()
            let outcome = try await self.performStart(h, id: UUID())
            XCTAssertEqual(outcome, .cleanupPending,
                "Global recovery failure must deny Start before it reaches the real model preflight")
            XCTAssertEqual(h.application.lastOutcome, .cleanupPending)
            XCTAssertEqual(h.services.startup.state, .failed)
            XCTAssertNil(h.services.startup.report)
            let owner = try XCTUnwrap(h.application.owner)
            let state = await owner.snapshot()
            XCTAssertEqual(state.phase, .idle)
            XCTAssertNil(state.sessionID)
            XCTAssertNil(state.failure, "A startup failure must not be rewritten as a missing-model failure")
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(state.readiness.audioSessionActive)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(state.readiness.activityActive)
            XCTAssertNil(h.services.live.transcript.sessionID)
            XCTAssertNil(h.application.owner?.completedManifest)
            XCTAssertFalse(FileManager.default.fileExists(atPath:
                h.directory(interrupted).appendingPathComponent("recovery-report.json").path))
            for (name, bytes) in original {
                XCTAssertEqual(try Data(contentsOf: h.directory(interrupted).appendingPathComponent(name)), bytes)
            }
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            do {
                let durable = try await reopened.meeting(id: interrupted)
                XCTAssertEqual(durable?.recordingState, .interrupted)
                XCTAssertEqual(durable?.capturedSampleCount, 0)
                let rows = try await reopened.history(limit: 10)
                XCTAssertEqual(rows.map(\.id), [interrupted])
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }
}
#endif
