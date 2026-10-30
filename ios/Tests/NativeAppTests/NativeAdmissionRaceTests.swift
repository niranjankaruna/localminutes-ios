#if os(iOS)
import AVFoundation
import Foundation
import SQLite3
import XCTest
@testable import LocalMinutes

/// Real app services, SQLite locking, metrics and CAF mapping. OS microphone,
/// playback and heavy-resource boundaries are observed without any inference
/// substitution or claim of physical-device/Lock Screen evidence.
@MainActor
final class NativeAdmissionRaceTests: XCTestCase {
    func testSecondMeetingEnduranceSamplingCannotRetainThePriorEpochOriginOrCountersDuringPreparation() async throws {
        try await fixture { f in
            let metrics = try XCTUnwrap(f.services.metrics)
            let endurance = try XCTUnwrap(f.services.endurance)
            try metrics.audioQueued(startSample: 0, frameCount: 1_600, queueDepth: 1)
            try metrics.processed(startSample: 0, frameCount: 1_600,
                workStartedAtNanoseconds: metrics.nowNanoseconds())
            let previousOrigin = try XCTUnwrap(metrics.firstAudioQueuedAtNanoseconds)
            // The owner starts this sampler before its awaited model preparation
            // resets ASR counters. Force the first sample into that interval.
            f.services.beginEnduranceEpoch()
            let firstSample = await admissionEventually { endurance.snapshot().totalSampleCount > 0 }
            XCTAssertTrue(firstSample, "The actual retained sampler must run before the model-preparation reset")
            guard firstSample else { return }
            metrics.beginEpoch()
            try metrics.audioQueued(startSample: 0, frameCount: 320, queueDepth: 1)
            try metrics.processed(startSample: 0, frameCount: 320,
                workStartedAtNanoseconds: metrics.nowNanoseconds())
            do { try f.services.sampleEndurance(visibility: .foreground) }
            catch { XCTFail("New-epoch facts must not be rejected because preparation reset old counters: \(error)") }
            let result = endurance.snapshot()
            XCTAssertEqual(result.epochOriginNanoseconds, metrics.firstAudioQueuedAtNanoseconds)
            XCTAssertNotEqual(result.epochOriginNanoseconds, previousOrigin)
            XCTAssertEqual(result.samples.last?.capturedSampleCount, 320)
            XCTAssertEqual(result.samples.last?.processedSampleCount, 320)
            XCTAssertTrue(result.samples.allSatisfy { $0.capturedSampleCount <= 320 && $0.processedSampleCount <= 320 },
                "Prior meeting samples must not contaminate the new meeting's statistics")
        }
    }

    func testActualSQLiteBlockedDeletionOwnsTheSharedHeavyGateUntilCacheAndMetadataCleanupSettle() async throws {
        try await fixture { f in
            let gate = try XCTUnwrap(f.services.heavyAdmission)
            let writer = try AdmissionSQLiteWriteLock(at: f.services.libraryRoot.appendingPathComponent("meetings.sqlite"))
            defer { try? writer.release() }
            let completion = AdmissionDeletionCompletion()
            let deletion = Task { @MainActor in
                let result = await f.services.deleteMeeting(id: f.id)
                completion.result = result
                return result
            }
            let request = f.services.meetingsDirectory.appendingPathComponent(".pending-deletions/\(f.id.uuidString)/request.json")
            // The real store has a1s busy timeout. The observed durable marker
            // must precede release of our independent BEGIN IMMEDIATE writer.
            let pending = await admissionEventually(milliseconds: 750) {
                FileManager.default.fileExists(atPath: request.path) && completion.result == nil
            }
            XCTAssertTrue(pending, "Actual deletion must reach durable intent while SQLite commit is blocked")
            guard pending else {
                try writer.release(); _ = await deletion.value
                return
            }
            var unexpected: HeavyModelUseLease?
            do {
                unexpected = try gate.acquire(purpose: .summary, requestID: UUID(), resource: AdmissionHeavyBoundary())
                XCTFail("A new generation can recreate raw-quote caches unless deletion owns shared admission")
            } catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .busy) }
            if let unexpected { try await gate.cancelAndDrain(unexpected) }
            try writer.release()
            let deleted = await deletion.value
            XCTAssertTrue(deleted)
            let row = try await f.services.store.meeting(id: f.id)
            let transcript = try await f.services.store.transcript(meetingID: f.id)
            XCTAssertNil(row); XCTAssertTrue(transcript.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.cache.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: request.path))
            XCTAssertEqual(gate.snapshot().phase, .idle)
            let replacement = try gate.acquire(purpose: .questionAnswering, requestID: UUID(), resource: AdmissionHeavyBoundary())
            try await gate.cancelAndDrain(replacement)
        }
    }

    func testPlaybackHeldAfterIdleSnapshotCannotActivateAfterLibraryRestoreAdmission() async throws {
        try await fixture { f in
            let permission = AdmissionPermissionBoundary()
            let capture = AdmissionCaptureBoundary(format: f.format)
            let owner = RecordingSessionOwner(permission: permission, hardware: capture,
                activityBackend: AdmissionActivityBoundary(), preparation: AdmissionPreparationBoundary())
            let playback = AdmissionPlaybackBoundary()
            let latch = AdmissionNativeLatch()
            let ownership = PlaybackOwnershipController(owner: owner, hardware: playback,
                afterSnapshot: { _ in await latch.wait() })
            let application = RecordingApplication(owner: owner, playbackOwnership: ownership,
                signalCenter: NotificationCenter())
            let playing = Task { await application.playAudio(at: f.location, requestID: UUID()) }
            defer {
                playing.cancel(); latch.release()
                try? application.setLibraryRestoreActive(false)
                _ = application.stopPlayback()
            }
            let held = await admissionEventually { latch.isWaiting }
            XCTAssertTrue(held)
            guard held else { latch.release(); _ = await playing.value; return }
            try application.setLibraryRestoreActive(true)
            XCTAssertTrue(application.isRestoringLibrary)
            latch.release()
            let outcome = await playing.value
            XCTAssertEqual(outcome, .blockedByRecording)
            XCTAssertEqual(playback.starts, 0, "Maintenance must invalidate already pending playback, before native activation")
            XCTAssertFalse(playback.active)
            XCTAssertFalse(ownership.hasPlaybackOwnership)
            XCTAssertEqual(playback.stops, 0, "No unowned OS audio-session deactivation is allowed")
            XCTAssertEqual(permission.requests, 0)
            XCTAssertEqual(capture.activations, 0)
            let state = await owner.snapshot()
            XCTAssertFalse(state.cleanupPending); XCTAssertFalse(state.readiness.audioSessionActive)
            await owner.stop()
        }
    }

    private func fixture(_ body: @MainActor (AdmissionNativeFixture) async throws -> Void) async throws {
        let f = try await AdmissionNativeFixture.create()
        do { try await body(f) } catch { await f.cleanup(); throw error }
        await f.cleanup()
    }
}

@MainActor
private func admissionEventually(milliseconds: Int = 2_000, _ predicate: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(milliseconds))
    while !(await predicate()) {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

@MainActor private final class AdmissionDeletionCompletion { var result: Bool? }
@MainActor private final class AdmissionNativeLatch {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }
    func wait() async { if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class AdmissionHeavyBoundary: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}

@MainActor private final class AdmissionPermissionBoundary: CapturePermissionSource {
    var requests = 0
    func requestRecordPermission() async -> Bool { requests += 1; return false }
}
private enum AdmissionFixtureError: Error { case unexpectedHardware, sqlite }
@MainActor private final class AdmissionPreparationBoundary: RecordingPreparationSource {
    func prepare(sessionID: UUID) async -> RecordingPreparationResult { .rejected(.modelUnavailable) }
}
@MainActor private final class AdmissionCaptureBoundary: CaptureHardware {
    let format: AVAudioFormat
    var activations = 0
    init(format: AVAudioFormat) { self.format = format }
    func activateSession() throws { activations += 1; throw AdmissionFixtureError.unexpectedHardware }
    func inputFormat() throws -> AVAudioFormat { format }
    func installTap(_ handler: @escaping CaptureTapHandler) throws { throw AdmissionFixtureError.unexpectedHardware }
    func startEngine() throws { throw AdmissionFixtureError.unexpectedHardware }
    func stopEngine() {}
    func removeTap() {}
    func deactivateSession() throws {}
}
@MainActor private final class AdmissionActivityBoundary: LiveActivityBackend {
    var areActivitiesEnabled: Bool { false }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle {
        throw AdmissionFixtureError.unexpectedHardware
    }
}
@MainActor private final class AdmissionPlaybackBoundary: PlaybackHardware {
    var starts = 0, stops = 0
    var active = false
    func startPlayback(at location: MeetingPlaybackLocation) throws { starts += 1; active = true }
    func stopPlayback() throws { stops += 1; active = false }
}

/// Native pointer remains in this synchronous owner, never service tasks.
private final class AdmissionSQLiteWriteLock {
    private var database: OpaquePointer?
    init(at url: URL) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw AdmissionFixtureError.sqlite
        }
        database = opened
        guard sqlite3_exec(opened, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close_v2(opened); database = nil; throw AdmissionFixtureError.sqlite
        }
    }
    func release() throws {
        guard let database else { return }
        let status = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
        let closed = sqlite3_close_v2(database)
        if closed == SQLITE_OK { self.database = nil }
        guard status == SQLITE_OK, closed == SQLITE_OK else { throw AdmissionFixtureError.sqlite }
    }
    deinit {
        if let database { sqlite3_exec(database, "ROLLBACK", nil, nil, nil); sqlite3_close_v2(database) }
    }
}

@MainActor
private final class AdmissionNativeFixture {
    let root: URL, parent: URL, id: UUID, cache: URL
    let services: LocalMinutesServices
    let format: AVAudioFormat
    let location: MeetingPlaybackLocation
    private init(root: URL, parent: URL, id: UUID, cache: URL, services: LocalMinutesServices,
                 format: AVAudioFormat, location: MeetingPlaybackLocation) {
        self.root = root; self.parent = parent; self.id = id; self.cache = cache
        self.services = services; self.format = format; self.location = location
    }
    static func create() async throws -> AdmissionNativeFixture {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        let parent = support.appendingPathComponent("LocalMinutesNativeAdmissionTests", isDirectory: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let services = try LocalMinutesServices(rootURL: root)
        do {
            await services.initialize()
            guard services.startup.state == .ready else { throw AdmissionFixtureError.sqlite }
            let id = UUID()
            try await services.store.createMeeting(.init(id: id, title: "Synthetic admission meeting",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed, capturedSampleCount: 320))
            try await services.store.appendFinalizedSegments([.init(id: UUID(), meetingID: id, sequence: 0,
                startSample: 0, endSample: 320, text: "Original synthetic admission transcript.", modelRevision: "synthetic-asr")], to: id)
            let audio = services.meetingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            let writer = try SegmentCAFWriter(directory: audio, sessionID: id)
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)); buffer.frameLength = 320
            try XCTUnwrap(buffer.floatChannelData?.pointee).update(repeating: 0.125, count: 320)
            try writer.append(buffer)
            let manifest = try writer.finish()
            let location = try XCTUnwrap(MeetingPlaybackMapper.locate(globalSample: 16, meetingID: id,
                manifest: manifest, meetingDirectory: audio))
            let identity = SummaryCheckpointIdentity(jobID: id, meetingID: id,
                sourceSHA256: String(repeating: "a", count: 64), planSHA256: String(repeating: "b", count: 64),
                modelID: "synthetic-storage-only", modelRevision: String(repeating: "c", count: 40),
                modelSHA256: String(repeating: "d", count: 64), runtimeVersion: "llama.cpp-b5046",
                promptVersion: "synthetic-checkpoint", contextTokenLimit: 512, reservedOutputTokens: 64, totalChunks: 1)
            let map = try JSONSerialization.data(withJSONObject: ["meeting_id": id.uuidString,
                "summary_points": [["quote": "Original synthetic admission transcript."]], "decisions": [], "actions": []])
            try await services.summaryCheckpoints.save(.init(index: 0, chunkSHA256: String(repeating: "e", count: 64), mapJSON: map), matching: identity)
            return .init(root: root, parent: parent, id: id,
                cache: services.libraryRoot.appendingPathComponent("SummaryCheckpoints/\(id.uuidString).json"),
                services: services, format: format, location: location)
        } catch {
            try? await services.store.close(); try? FileManager.default.removeItem(at: root); throw error
        }
    }
    func cleanup() async {
        services.endEnduranceEpoch()
        try? await services.store.close()
        guard root.deletingLastPathComponent() == parent, parent.lastPathComponent == "LocalMinutesNativeAdmissionTests",
              UUID(uuidString: root.lastPathComponent) != nil, root.resolvingSymlinksInPath().standardizedFileURL == root else {
            return XCTFail("Refuse cleanup outside owned native admission fixture")
        }
        do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Owned native admission fixture cleanup failed") }
    }
}
#endif
