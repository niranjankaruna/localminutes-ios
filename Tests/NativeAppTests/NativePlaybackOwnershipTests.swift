#if os(iOS)
import AVFoundation
import Foundation
import XCTest
@testable import LocalMinutes

// Lifecycle/ownership evidence only: preparation, permission and native OS
// resources are doubled. The coordinator, queue, conversion, CAF writer and CAF
// mapper are real. These tests make no inference, speaker, lock or phone claim.
private enum PlaybackTestError: Error { case timeout, deactivation, unsafeFixture }

@MainActor
private func playbackEventually(
    _ condition: @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

@MainActor
private final class PlaybackLatch {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var isWaiting: Bool { !waiters.isEmpty }
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
private final class PlaybackProbe {
    var trace: [String] = []
    var snapshots: [RecordingSnapshot] = []
    var captureSawPlayback: [Bool] = []
}

@MainActor
private final class PlaybackOSBoundary: PlaybackHardware {
    let probe: PlaybackProbe
    private(set) var isActive = false
    private(set) var starts: [MeetingPlaybackLocation] = []
    private(set) var stopCalls = 0
    private(set) var deactivationCalls = 0
    var deactivationFailures = 0
    init(probe: PlaybackProbe) { self.probe = probe }
    func startPlayback(at location: MeetingPlaybackLocation) throws {
        probe.trace.append("playback.activate")
        starts.append(location)
        isActive = true
    }
    func stopPlayback() throws {
        probe.trace.append("playback.stop")
        stopCalls += 1
        probe.trace.append("playback.deactivate")
        deactivationCalls += 1
        if deactivationFailures > 0 {
            deactivationFailures -= 1
            throw PlaybackTestError.deactivation
        }
        isActive = false
    }
    func releaseFixtureResource() {
        deactivationFailures = 0
        isActive = false
    }
}

@MainActor
private final class PlaybackPreparation: RecordingPreparationSource {
    let directory: URL
    let probe: PlaybackProbe
    var latch: PlaybackLatch?
    private(set) var requests: [UUID] = []
    init(directory: URL, probe: PlaybackProbe) { self.directory = directory; self.probe = probe }
    func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        requests.append(sessionID)
        probe.trace.append("recording.prepare")
        await latch?.wait()
        // Explicit model-preflight boundary for this scheduling contract. This
        // value is never counted as real model installation or inference.
        return .ready(directory: directory)
    }
}

@MainActor
private final class PlaybackPermission: CapturePermissionSource {
    private(set) var requests = 0
    func requestRecordPermission() async -> Bool { requests += 1; return true }
}

@MainActor
private final class PlaybackCaptureHardware: CaptureHardware {
    let format: AVAudioFormat
    let probe: PlaybackProbe
    let playback: PlaybackOSBoundary
    private(set) var tap: CaptureTapHandler?
    private(set) var activations = 0
    private(set) var deactivations = 0
    private(set) var active = false
    private(set) var running = false
    var deactivationFailures = 0
    init(probe: PlaybackProbe, playback: PlaybackOSBoundary) throws {
        format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        self.probe = probe; self.playback = playback
    }
    func activateSession() throws {
        probe.trace.append("capture.activate")
        probe.captureSawPlayback.append(playback.isActive)
        activations += 1
        active = true
    }
    func inputFormat() throws -> AVAudioFormat { format }
    func installTap(_ handler: @escaping CaptureTapHandler) throws { tap = handler }
    func startEngine() throws { running = true; probe.trace.append("capture.start") }
    func stopEngine() { running = false; probe.trace.append("capture.stop") }
    func removeTap() { tap = nil }
    func deactivateSession() throws {
        deactivations += 1
        probe.trace.append("capture.deactivate")
        if deactivationFailures > 0 {
            deactivationFailures -= 1
            throw PlaybackTestError.deactivation
        }
        active = false
    }
    func emit() throws {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.update(repeating: 0.25, count: 64)
        let callback = try XCTUnwrap(tap)
        callback(buffer, AVAudioTime(sampleTime: 5_000, atRate: 16_000))
    }
}

@MainActor
private final class PlaybackActivity: LiveActivityHandle {
    var state: LiveActivityResourceState = .active
    var endLatch: PlaybackLatch?
    private var observer: LiveActivityStateObserver?
    func setStateObserver(_ observer: LiveActivityStateObserver?) { self.observer = observer }
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome { .applied }
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        await endLatch?.wait()
        state = .ended
        observer?(.ended)
        return .applied
    }
}

@MainActor
private final class PlaybackActivityBackend: LiveActivityBackend {
    let activity = PlaybackActivity()
    var areActivitiesEnabled: Bool { true }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle { activity }
}

@MainActor
private final class PlaybackForegroundBoundary: RecordingForegroundContinuation {
    func requestContinuation(for failure: RecordingFailure) async throws {}
}

@MainActor
private final class PlaybackOperation<Value: Sendable> {
    var result: Result<Value, Error>?
}

@MainActor
private final class PlaybackHarness {
    let id = UUID()
    let root: URL
    let parent: URL
    let captureDirectory: URL
    let location: MeetingPlaybackLocation
    let probe: PlaybackProbe
    let playback: PlaybackOSBoundary
    let preparation: PlaybackPreparation
    let permission: PlaybackPermission
    let capture: PlaybackCaptureHardware
    let activities: PlaybackActivityBackend
    let owner: RecordingSessionOwner
    let ownership: PlaybackOwnershipController
    let application: RecordingApplication
    let snapshotLatch: PlaybackLatch?
    let reservationLatch: PlaybackLatch?

    init(holdSnapshot: Bool = false, holdReservation: Bool = false,
         holdPreparation: Bool = false) throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-playback-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let captureDirectory = root.appendingPathComponent("capture", isDirectory: true)
        let playbackDirectory = root.appendingPathComponent("playback", isDirectory: true)
        let fixtureID = UUID()
        let writer = try SegmentCAFWriter(directory: playbackDirectory, sessionID: fixtureID)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        try XCTUnwrap(buffer.floatChannelData?[0]).update(repeating: 0.5, count: 64)
        try writer.append(buffer)
        let manifest = try writer.finish()
        let location = try XCTUnwrap(MeetingPlaybackMapper.locate(globalSample: 16, meetingID: fixtureID,
            manifest: manifest, meetingDirectory: playbackDirectory))
        let probe = PlaybackProbe()
        let playback = PlaybackOSBoundary(probe: probe)
        let preparation = PlaybackPreparation(directory: captureDirectory, probe: probe)
        if holdPreparation { preparation.latch = PlaybackLatch() }
        let permission = PlaybackPermission()
        let capture = try PlaybackCaptureHardware(probe: probe, playback: playback)
        let activities = PlaybackActivityBackend()
        let snapshotLatch = holdSnapshot ? PlaybackLatch() : nil
        let reservationLatch = holdReservation ? PlaybackLatch() : nil
        let owner = RecordingSessionOwner(permission: permission, hardware: capture,
            activityBackend: activities, preparation: preparation, beforeReservation: {
                await reservationLatch?.wait()
            })
        let ownership = PlaybackOwnershipController(owner: owner, hardware: playback, afterSnapshot: { snapshot in
            probe.snapshots.append(snapshot)
            await snapshotLatch?.wait()
        })
        self.parent = parent; self.root = root; self.captureDirectory = captureDirectory
        self.location = location; self.probe = probe; self.playback = playback
        self.preparation = preparation; self.permission = permission; self.capture = capture
        self.activities = activities; self.owner = owner; self.ownership = ownership
        self.snapshotLatch = snapshotLatch; self.reservationLatch = reservationLatch
        application = RecordingApplication(owner: owner, foreground: PlaybackForegroundBoundary(),
                                           playbackOwnership: ownership)
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        snapshotLatch?.release()
        reservationLatch?.release()
        preparation.latch?.release()
        activities.activity.endLatch?.release()
        capture.deactivationFailures = 0
        let completion = PlaybackOperation<Void>()
        let stopping = Task { @MainActor in
            await owner.stop()
            completion.result = .success(())
        }
        guard await playbackEventually({ completion.result != nil }) else {
            stopping.cancel()
            XCTFail("Capture cleanup did not settle; retain the owned fixture", file: file, line: line)
            return
        }
        await stopping.value
        let state = await owner.snapshot()
        guard !state.cleanupPending, !capture.active, !capture.running, capture.tap == nil else {
            XCTFail("Capture resources still own the fixture", file: file, line: line); return
        }
        // Test fixture teardown only; production deactivation behavior remains
        // asserted before this unconditional release of the doubled OS resource.
        playback.releaseFixtureResource()
        guard root.lastPathComponent.hasPrefix("localminutes-playback-test-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath() == parent,
              root.resolvingSymlinksInPath() == root else {
            XCTFail("Refuse cleanup outside generated fixture root", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned fixture cleanup failed: \(error)", file: file, line: line) }
    }
}

@MainActor
final class NativePlaybackOwnershipTests: XCTestCase {
    private func withHarness(holdSnapshot: Bool = false, holdReservation: Bool = false,
        holdPreparation: Bool = false, _ body: @MainActor (PlaybackHarness) async throws -> Void) async throws {
        let h = try PlaybackHarness(holdSnapshot: holdSnapshot, holdReservation: holdReservation,
                                    holdPreparation: holdPreparation)
        do { try await body(h) }
        catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    private func complete<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let completion = PlaybackOperation<Value>()
        let task = Task { @MainActor in
            do { completion.result = .success(try await operation()) }
            catch { completion.result = .failure(error) }
        }
        guard await playbackEventually({ completion.result != nil }) else {
            task.cancel()
            XCTFail("Operation exceeded the bounded native-test deadline")
            throw PlaybackTestError.timeout
        }
        await task.value
        return try XCTUnwrap(completion.result).get()
    }

    private func assertRecording(_ h: PlaybackHarness) async throws {
        try h.capture.emit()
        let becameRecording = await playbackEventually { await h.owner.snapshot().phase == .recording }
        XCTAssertTrue(becameRecording)
        let state = await h.owner.snapshot()
        XCTAssertTrue(state.readiness.audioSessionActive)
        XCTAssertTrue(state.readiness.firstBufferAccepted)
        XCTAssertTrue(state.readiness.activityActive)
    }

    private func assertSavedCAF(_ h: PlaybackHarness) throws {
        let manifest = try XCTUnwrap(h.owner.completedManifest)
        XCTAssertEqual(manifest.sessionID, h.id)
        XCTAssertEqual(manifest.totalFrames, 64)
        let persisted = try JSONDecoder().decode(AudioCaptureManifest.self,
            from: Data(contentsOf: h.captureDirectory.appendingPathComponent("capture-manifest.json")))
        XCTAssertEqual(persisted, manifest)
        let location = try XCTUnwrap(MeetingPlaybackMapper.locate(globalSample: 0, meetingID: h.id,
            manifest: persisted, meetingDirectory: h.captureDirectory))
        let file = try AVAudioFile(forReading: location.fileURL)
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 64))
        try file.read(into: decoded)
        XCTAssertEqual(decoded.frameLength, 64)
        XCTAssertEqual(try XCTUnwrap(decoded.floatChannelData?[0])[0], 0.25, accuracy: 0.001)
    }

    private func assertReservationBlocksDelayedPlayback(_ action: RecordingIntentAction,
        h: PlaybackHarness) async throws {
        let playing = Task { await h.application.playAudio(at: h.location) }
        defer { playing.cancel(); h.snapshotLatch?.release(); h.reservationLatch?.release() }
        let observed = await playbackEventually { h.snapshotLatch?.isWaiting == true }
        XCTAssertTrue(observed, "The real idle observation must precede recording admission")
        XCTAssertEqual(h.probe.snapshots.first?.phase, .idle)
        let starting = Task { try await h.application.perform(action) }
        defer { starting.cancel() }
        let reserved = await playbackEventually { h.reservationLatch?.isWaiting == true }
        XCTAssertTrue(reserved, "The real owner must reserve before its domain actor hop")
        let duringReservation = await h.owner.snapshot()
        XCTAssertEqual(duringReservation.phase, .idle,
            "This test must exercise the interval a second phase snapshot cannot protect")
        h.snapshotLatch?.release()
        let result = try await complete { await playing.value }
        XCTAssertEqual(result, .blockedByRecording)
        XCTAssertEqual(h.playback.starts.count, 0)
        XCTAssertEqual(h.playback.deactivationCalls, 0)
        h.reservationLatch?.release()
        let outcome = try await complete { try await starting.value }
        XCTAssertEqual(outcome, .starting)
        XCTAssertEqual(h.capture.activations, 1)
        XCTAssertEqual(h.probe.captureSawPlayback, [false])
    }

    func testDelayedPlaybackCannotActivateAfterStartReservationBeforeDomainPhaseChanges() async throws {
        try await withHarness(holdSnapshot: true, holdReservation: true) { h in
            try await self.assertReservationBlocksDelayedPlayback(.start(h.id), h: h)
        }
    }

    func testDelayedPlaybackCannotActivateAfterToggleReservationBeforeDomainPhaseChanges() async throws {
        try await withHarness(holdSnapshot: true, holdReservation: true) { h in
            try await self.assertReservationBlocksDelayedPlayback(.toggle(h.id), h: h)
        }
    }

    func testDelayedPlaybackIsBlockedWhileRealOwnerPreparationIsHeld() async throws {
        try await withHarness(holdSnapshot: true, holdPreparation: true) { h in
            let playing = Task { await h.application.playAudio(at: h.location) }
            defer { playing.cancel(); h.snapshotLatch?.release(); h.preparation.latch?.release() }
            let observedIdle = await playbackEventually { h.snapshotLatch?.isWaiting == true }
            XCTAssertTrue(observedIdle)
            let starting = Task { try await h.application.perform(.start(h.id)) }
            defer { starting.cancel() }
            let enteredPreparation = await playbackEventually { h.preparation.latch?.isWaiting == true }
            XCTAssertTrue(enteredPreparation)
            let held = await h.owner.snapshot()
            XCTAssertEqual(held.phase, .preparing)
            XCTAssertEqual(held.sessionID, h.id)
            h.snapshotLatch?.release()
            let result = try await self.complete { await playing.value }
            XCTAssertEqual(result, .blockedByRecording)
            XCTAssertTrue(h.playback.starts.isEmpty)
            XCTAssertEqual(h.playback.deactivationCalls, 0)
            XCTAssertEqual(h.capture.activations, 0)
            h.preparation.latch?.release()
            let outcome = try await self.complete { try await starting.value }
            XCTAssertEqual(outcome, .starting)
        }
    }

    func testDelayedPlaybackCannotReconfigureOrDeactivateAnActiveRealCapture() async throws {
        try await withHarness(holdSnapshot: true) { h in
            let playing = Task { await h.application.playAudio(at: h.location) }
            defer { playing.cancel(); h.snapshotLatch?.release() }
            let observedIdle = await playbackEventually { h.snapshotLatch?.isWaiting == true }
            XCTAssertTrue(observedIdle)
            let started = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(started, .starting)
            try await self.assertRecording(h)
            h.snapshotLatch?.release()
            let result = try await self.complete { await playing.value }
            XCTAssertEqual(result, .blockedByRecording)
            XCTAssertTrue(h.playback.starts.isEmpty)
            XCTAssertEqual(h.playback.deactivationCalls, 0,
                "A delayed playback cleanup must never deactivate capture's session")
            XCTAssertTrue(h.capture.active)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .recording)
            let stopped = try await self.complete { try await h.application.perform(.stop(expectedSessionID: h.id)) }
            XCTAssertEqual(stopped, .stopped)
            try self.assertSavedCAF(h)
        }
    }

    func testRecordingClosesAdmittedPlaybackBeforeAnyCaptureActivation() async throws {
        try await withHarness { h in
            let played = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(played, .playing)
            XCTAssertEqual(h.playback.starts, [h.location])
            XCTAssertTrue(h.playback.isActive)
            let started = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(started, .starting)
            XCTAssertEqual(h.playback.stopCalls, 1)
            XCTAssertEqual(h.playback.deactivationCalls, 1)
            XCTAssertFalse(h.playback.isActive)
            XCTAssertEqual(h.probe.captureSawPlayback, [false])
            let captureIndex = try XCTUnwrap(h.probe.trace.firstIndex(of: "capture.activate"))
            if let stopped = h.probe.trace.firstIndex(of: "playback.stop"),
               let deactivated = h.probe.trace.firstIndex(of: "playback.deactivate") {
                XCTAssertLessThan(stopped, deactivated)
                XCTAssertLessThan(deactivated, captureIndex)
            } else { XCTFail("Actual player stop and session deactivation must precede capture") }
            try await self.assertRecording(h)
            let stopped = try await self.complete { try await h.application.perform(.stop(expectedSessionID: h.id)) }
            XCTAssertEqual(stopped, .stopped)
            try self.assertSavedCAF(h)
        }
    }

    func testFailedPlaybackDeactivationPreventsCaptureAndRemainsExplicitlyRetryable() async throws {
        try await withHarness { h in
            let played = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(played, .playing)
            h.playback.deactivationFailures = 1
            let refused = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(refused, .cleanupPending)
            XCTAssertTrue(h.ownership.hasPlaybackOwnership,
                "Failed deactivation cannot silently discard the operation's session ownership")
            XCTAssertTrue(h.playback.isActive)
            XCTAssertEqual(h.playback.deactivationCalls, 1)
            XCTAssertEqual(h.preparation.requests.count, 0)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertEqual(h.capture.activations, 0,
                "Returning cleanupPending after activating capture is not a valid admission guard")
            XCTAssertFalse(h.capture.running)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .idle)
            XCTAssertNil(state.sessionID)
            let cleaned = h.application.stopPlayback()
            XCTAssertEqual(cleaned, .stopped)
            XCTAssertFalse(h.ownership.hasPlaybackOwnership)
            XCTAssertFalse(h.playback.isActive)
            XCTAssertEqual(h.playback.deactivationCalls, 2)
            let retried = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(retried, .starting)
            XCTAssertEqual(h.capture.activations, 1)
            XCTAssertEqual(h.probe.captureSawPlayback, [false])
        }
    }

    func testStoppingBlocksPlaybackUntilActualCAFFlushAndActivityEndSettle() async throws {
        try await withHarness { h in
            let started = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(started, .starting)
            try await self.assertRecording(h)
            let endLatch = PlaybackLatch()
            h.activities.activity.endLatch = endLatch
            let stopping = Task { try await h.application.perform(.stop(expectedSessionID: h.id)) }
            defer { stopping.cancel(); endLatch.release() }
            let enteredEnd = await playbackEventually { endLatch.isWaiting }
            XCTAssertTrue(enteredEnd)
            let pending = await h.owner.snapshot()
            XCTAssertEqual(pending.phase, .stopping)
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertFalse(h.capture.active)
            XCTAssertNil(h.owner.completedManifest)
            let blocked = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(blocked, .blockedByRecording)
            XCTAssertTrue(h.playback.starts.isEmpty)
            XCTAssertEqual(h.playback.deactivationCalls, 0)
            endLatch.release()
            let stopped = try await self.complete { try await stopping.value }
            XCTAssertEqual(stopped, .stopped)
            try self.assertSavedCAF(h)
            let admitted = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(admitted, .playing)
            XCTAssertEqual(h.playback.starts, [h.location])
        }
    }

    func testFailedCaptureDeactivationBlocksPlaybackUntilExplicitCaptureCleanupRetry() async throws {
        try await withHarness { h in
            let started = try await self.complete { try await h.application.perform(.start(h.id)) }
            XCTAssertEqual(started, .starting)
            try await self.assertRecording(h)
            h.capture.deactivationFailures = 1
            let failedStop = try await self.complete { try await h.application.perform(.stop(expectedSessionID: h.id)) }
            XCTAssertEqual(failedStop, .cleanupPending)
            let pending = await h.owner.snapshot()
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertTrue(h.capture.active)
            let blocked = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(blocked, .blockedByRecording)
            XCTAssertTrue(h.playback.starts.isEmpty)
            XCTAssertEqual(h.playback.deactivationCalls, 0)
            let retry = try await self.complete { try await h.application.perform(.stop(expectedSessionID: h.id)) }
            XCTAssertEqual(retry, .requiresForeground(.captureUnavailable))
            let settled = await h.owner.snapshot()
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertFalse(h.capture.active)
            XCTAssertNil(h.owner.completedManifest, "A failed recording must never become Saved")
            let admitted = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(admitted, .playing)
        }
    }

    func testGlobalStopRevokesAPlayAwaitingItsSnapshotAndALaterPlayCanStart() async throws {
        try await withHarness(holdSnapshot: true) { h in
            let pending = Task { await h.application.playAudio(at: h.location) }
            defer { pending.cancel(); h.snapshotLatch?.release() }
            let observedIdle = await playbackEventually { h.snapshotLatch?.isWaiting == true }
            XCTAssertTrue(observedIdle)
            XCTAssertEqual(h.probe.snapshots.first?.phase, .idle)
            XCTAssertEqual(h.application.stopPlayback(), .stopped)
            h.snapshotLatch?.release()
            let revoked = try await self.complete { await pending.value }
            XCTAssertEqual(revoked, .unavailable,
                "A view's global Stop must revoke its not-yet-activated play request")
            XCTAssertTrue(h.playback.starts.isEmpty, "Offscreen playback must never activate after Stop")
            XCTAssertEqual(h.playback.deactivationCalls, 0)
            XCTAssertFalse(h.playback.isActive)
            XCTAssertFalse(h.ownership.hasPlaybackOwnership)
            let later = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(later, .playing)
            XCTAssertEqual(h.playback.starts, [h.location])
            XCTAssertTrue(h.playback.isActive)
            XCTAssertTrue(h.ownership.hasPlaybackOwnership)
        }
    }

    func testCancelledPendingPlayCannotActivateAndALaterPlayCanStart() async throws {
        try await withHarness(holdSnapshot: true) { h in
            let pending = Task { await h.application.playAudio(at: h.location) }
            defer { pending.cancel(); h.snapshotLatch?.release() }
            let observedIdle = await playbackEventually { h.snapshotLatch?.isWaiting == true }
            XCTAssertTrue(observedIdle)
            XCTAssertEqual(h.probe.snapshots.first?.phase, .idle)
            pending.cancel()
            h.snapshotLatch?.release()
            let cancelled = try await self.complete { await pending.value }
            XCTAssertEqual(cancelled, .unavailable,
                "Cancellation must be checked before native audio-session activation")
            XCTAssertTrue(h.playback.starts.isEmpty)
            XCTAssertEqual(h.playback.deactivationCalls, 0)
            XCTAssertFalse(h.playback.isActive)
            XCTAssertFalse(h.ownership.hasPlaybackOwnership)
            let later = try await self.complete { await h.application.playAudio(at: h.location) }
            XCTAssertEqual(later, .playing)
            XCTAssertEqual(h.playback.starts, [h.location])
            XCTAssertTrue(h.playback.isActive)
        }
    }

    func testScopedOldRequestCleanupCannotStopAReplacementPlayer() async throws {
        try await withHarness { h in
            let firstID = UUID()
            let replacementID = UUID()
            let playbackDirectory = h.location.fileURL.deletingLastPathComponent()
            let manifest = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: playbackDirectory.appendingPathComponent("capture-manifest.json")))
            let replacement = try XCTUnwrap(MeetingPlaybackMapper.locate(globalSample: 32,
                meetingID: manifest.sessionID, manifest: manifest, meetingDirectory: playbackDirectory))
            let first = try await self.complete {
                await h.application.playAudio(at: h.location, requestID: firstID)
            }
            XCTAssertEqual(first, .playing)
            let second = try await self.complete {
                await h.application.playAudio(at: replacement, requestID: replacementID)
            }
            XCTAssertEqual(second, .playing)
            XCTAssertEqual(h.playback.starts, [h.location, replacement])
            XCTAssertEqual(h.playback.stopCalls, 1)
            XCTAssertEqual(h.playback.deactivationCalls, 1)
            XCTAssertTrue(h.playback.isActive)
            let staleCleanup = h.application.stopPlayback(expectedRequestID: firstID)
            XCTAssertEqual(staleCleanup, .stopped)
            XCTAssertEqual(h.playback.stopCalls, 1,
                "Old view cleanup must not stop the replacement request's player")
            XCTAssertEqual(h.playback.deactivationCalls, 1)
            XCTAssertTrue(h.playback.isActive)
            XCTAssertTrue(h.ownership.hasPlaybackOwnership)
            let matchingCleanup = h.application.stopPlayback(expectedRequestID: replacementID)
            XCTAssertEqual(matchingCleanup, .stopped)
            XCTAssertEqual(h.playback.stopCalls, 2)
            XCTAssertEqual(h.playback.deactivationCalls, 2)
            XCTAssertFalse(h.playback.isActive)
            XCTAssertFalse(h.ownership.hasPlaybackOwnership)
            XCTAssertEqual(h.capture.activations, 0)
        }
    }
}
#endif
