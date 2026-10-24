import AVFoundation
import AudioToolbox
import Foundation
import XCTest
#if SWIFT_PACKAGE
import LocalMinutesCore
@testable import LocalMinutesRecording
#else
@testable import LocalMinutes
#endif

// Test-first composition contract. Only permission, hardware, ActivityKit and
// model-preparation boundaries are doubled. Synthetic PCM must flow through the
// actual capture queue, native conversion and CAF writer after implementation.
// A doubled preparation result is never real ASR/inference or device evidence.
private enum OwnerTestError: Error {
    case hardwareFailure, noActivityHandle, timedOut, unsafeFixture, unexpectedAudio
}

@MainActor
private final class OwnerTestProbe {
    var trace: [String] = []
    var started = false
    var finished = false
}

@MainActor
private func ownerEventually(
    timeout: Duration = .seconds(1),
    _ condition: @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

@MainActor
private final class OwnerTestPreparation: RecordingPreparationSource {
    var result: RecordingPreparationResult
    var hold = false
    private(set) var requests: [UUID] = []
    private var waiters: [CheckedContinuation<RecordingPreparationResult, Never>] = []
    var isWaiting: Bool { !waiters.isEmpty }
    var holdFinish = false
    var finishFailure: RecordingFailure?
    private var finishWaiter: CheckedContinuation<RecordingFailure?, Never>?
    var finishIsWaiting: Bool { finishWaiter != nil }
    private(set) var finishes: [UUID] = []

    init(directory: URL) { result = .ready(directory: directory) }

    func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure? {
        finishes.append(sessionID)
        if holdFinish { return await withCheckedContinuation { finishWaiter = $0 } }
        return finishFailure
    }

    func resolveFinish() {
        holdFinish = false
        let pending = finishWaiter
        finishWaiter = nil
        pending?.resume(returning: finishFailure)
    }

    func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        requests.append(sessionID)
        if hold {
            // Intentionally does not complete merely because its task is
            // cancelled. Stop must keep cleanup pending until preparation exits.
            return await withCheckedContinuation { waiters.append($0) }
        }
        return result
    }

    func resolve(_ result: RecordingPreparationResult) {
        hold = false
        self.result = result
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume(returning: result) }
    }
}

@MainActor
private final class OwnerTestPermission: CapturePermissionSource {
    var granted = true
    var hold = false
    private(set) var requests = 0
    private var continuation: CheckedContinuation<Bool, Never>?
    var isWaiting: Bool { continuation != nil }
    func requestRecordPermission() async -> Bool {
        requests += 1
        if hold { return await withCheckedContinuation { continuation = $0 } }
        return granted
    }
    func resolve() {
        hold = false
        let pending = continuation
        continuation = nil
        pending?.resume(returning: granted)
    }
}

@MainActor
private final class OwnerTestReservationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

@MainActor
private final class OwnerTestHardware: CaptureHardware {
    let probe: OwnerTestProbe
    let format: AVAudioFormat
    private(set) var tap: CaptureTapHandler?
    private(set) var sessionActive = false
    private(set) var engineRunning = false
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var deactivateCalls = 0
    var activationFailures = 0
    var deactivationFailures = 0

    init(probe: OwnerTestProbe, rate: Double, channels: AVAudioChannelCount) throws {
        self.probe = probe
        format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: rate, channels: channels
        ))
    }

    func activateSession() throws {
        probe.trace.append("audio.activate")
        if activationFailures > 0 {
            activationFailures -= 1
            throw OwnerTestError.hardwareFailure
        }
        sessionActive = true
    }
    func inputFormat() throws -> AVAudioFormat {
        probe.trace.append("audio.format")
        XCTAssertTrue(sessionActive)
        return format
    }
    func installTap(_ handler: @escaping CaptureTapHandler) throws {
        probe.trace.append("audio.install")
        tap = handler
    }
    func startEngine() throws {
        probe.trace.append("audio.start")
        startCalls += 1
        engineRunning = true
    }
    func stopEngine() {
        probe.trace.append("audio.stop")
        stopCalls += 1
        engineRunning = false
    }
    func removeTap() {
        probe.trace.append("audio.remove")
        tap = nil
    }
    func deactivateSession() throws {
        probe.trace.append("audio.deactivate")
        deactivateCalls += 1
        if deactivationFailures > 0 {
            deactivationFailures -= 1
            throw OwnerTestError.hardwareFailure
        }
        sessionActive = false
    }
    func emit(_ buffer: AVAudioPCMBuffer, sampleTime: AVAudioFramePosition) throws {
        let callback = try XCTUnwrap(tap, "Owner must use the real capture runtime")
        callback(buffer, AVAudioTime(sampleTime: sampleTime, atRate: format.sampleRate))
    }
}

@MainActor
private final class OwnerTestActivity: LiveActivityHandle {
    let probe: OwnerTestProbe
    private(set) var state: LiveActivityResourceState = .active
    private(set) var observer: LiveActivityStateObserver?
    private(set) var updates: [LiveActivityStatus] = []
    private(set) var endCalls = 0
    var holdEnd = false
    var endOutcome: LiveActivityOperationOutcome = .applied
    private var endWaiters: [CheckedContinuation<Void, Never>] = []
    var endIsWaiting: Bool { !endWaiters.isEmpty }

    init(probe: OwnerTestProbe) { self.probe = probe }

    func setStateObserver(_ observer: LiveActivityStateObserver?) {
        self.observer = observer
    }
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        updates.append(status)
        return .applied
    }
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        probe.trace.append("activity.end.begin")
        endCalls += 1
        let outcome = endOutcome
        if holdEnd {
            await withCheckedContinuation { endWaiters.append($0) }
        }
        if outcome == .applied { emit(.ended) }
        probe.trace.append("activity.end.settled")
        return outcome
    }
    func emit(_ state: LiveActivityResourceState) {
        self.state = state
        observer?(state)
    }
    func releaseEnd() {
        holdEnd = false
        let pending = endWaiters
        endWaiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class OwnerTestActivityBackend: LiveActivityBackend {
    let probe: OwnerTestProbe
    let handles: [OwnerTestActivity]
    var areActivitiesEnabled = true
    private(set) var requests: [UUID] = []

    init(probe: OwnerTestProbe) {
        self.probe = probe
        handles = (0..<3).map { _ in OwnerTestActivity(probe: probe) }
    }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle {
        probe.trace.append("activity.request")
        guard requests.count < handles.count else { throw OwnerTestError.noActivityHandle }
        let handle = handles[requests.count]
        requests.append(sessionID)
        return handle
    }
}

@MainActor
private final class OwnerTestHarness {
    let id = UUID()
    let root: URL
    let directory: URL
    let probe: OwnerTestProbe
    let preparation: OwnerTestPreparation
    let permission: OwnerTestPermission
    let hardware: OwnerTestHardware
    let activity: OwnerTestActivityBackend
    let owner: RecordingSessionOwner
    private let parent: URL

    init(rate: Double = 16_000, channels: AVAudioChannelCount = 1,
         beforeReservation: (@MainActor @Sendable () async -> Void)? = nil) throws {
        let fixtureParent = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath().standardizedFileURL
        let fixtureRoot = fixtureParent.appendingPathComponent("localminutes-owner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        let meetingDirectory = fixtureRoot.appendingPathComponent("meeting")
        let eventProbe = OwnerTestProbe()
        let modelBoundary = OwnerTestPreparation(directory: meetingDirectory)
        let permissionBoundary = OwnerTestPermission()
        let hardwareBoundary = try OwnerTestHardware(probe: eventProbe, rate: rate, channels: channels)
        let activityBoundary = OwnerTestActivityBackend(probe: eventProbe)
        parent = fixtureParent
        root = fixtureRoot
        directory = meetingDirectory
        probe = eventProbe
        preparation = modelBoundary
        permission = permissionBoundary
        hardware = hardwareBoundary
        activity = activityBoundary
        if let beforeReservation {
            owner = RecordingSessionOwner(
                permission: permissionBoundary, hardware: hardwareBoundary,
                activityBackend: activityBoundary, preparation: modelBoundary,
                beforeReservation: beforeReservation
            )
        } else {
            owner = RecordingSessionOwner(
                permission: permissionBoundary, hardware: hardwareBoundary,
                activityBackend: activityBoundary, preparation: modelBoundary
            )
        }
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        preparation.resolveFinish()
        preparation.resolve(.rejected(.modelUnavailable))
        permission.resolve()
        hardware.deactivationFailures = 0
        for handle in activity.handles {
            handle.endOutcome = .applied
            handle.releaseEnd()
        }
        let completion = OwnerTestProbe()
        let task = Task {
            await owner.stop()
            completion.finished = true
        }
        let returned = await ownerEventually { completion.finished }
        guard returned else {
            task.cancel()
            XCTFail("Cleanup did not settle; retain the owned synthetic fixture", file: file, line: line)
            return
        }
        await task.value
        let snapshot = await owner.snapshot()
        let returnedHandles = activity.handles.prefix(activity.requests.count)
        guard !snapshot.cleanupPending, !hardware.engineRunning, !hardware.sessionActive,
              hardware.tap == nil,
              returnedHandles.allSatisfy({ $0.state == .ended || $0.state == .dismissed }) else {
            XCTFail("Resources remain owned; retain the synthetic fixture", file: file, line: line)
            return
        }
        guard root.isFileURL, root.lastPathComponent.hasPrefix("localminutes-owner-test-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath().path == parent.path,
              root.resolvingSymlinksInPath().path == root.path else {
            XCTFail("Refuse fixture cleanup outside the generated root", file: file, line: line)
            return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned fixture cleanup failed: \(error)", file: file, line: line) }
    }
}

@MainActor
final class RecordingSessionOwnerTests: XCTestCase {
    func testOwnerWaitsForTranscriptFinalizationBeforeAcknowledgingSavedAudio() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.preparation.holdFinish = true
            let returned = OwnerTestProbe()
            let stopping = Task { await h.owner.stop(); returned.finished = true }
            let entered = await ownerEventually { h.preparation.finishIsWaiting || returned.finished }
            XCTAssertTrue(entered)
            XCTAssertTrue(h.preparation.finishIsWaiting, "Stop must enter the actual transcript persistence barrier")
            XCTAssertFalse(returned.finished, "Saved cannot precede finalized transcript persistence")
            let pending = await h.owner.snapshot()
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
            h.preparation.resolveFinish()
            await stopping.value
            XCTAssertEqual(h.preparation.finishes, [h.id])
            XCTAssertNotNil(h.owner.completedManifest)
        }
    }

    func testTranscriptFinalizationFailureCannotPublishRecordingSaved() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.preparation.finishFailure = .writeFailed
            try await complete { await h.owner.stop() }
            let final = await h.owner.snapshot()
            XCTAssertEqual(h.preparation.finishes, [h.id])
            XCTAssertEqual(final.failure, .writeFailed)
            XCTAssertNotEqual(final.phase, .completed)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    private func withHarness(
        rate: Double = 16_000, channels: AVAudioChannelCount = 1,
        beforeReservation: (@MainActor @Sendable () async -> Void)? = nil,
        _ body: @MainActor (OwnerTestHarness) async throws -> Void
    ) async throws {
        let harness = try OwnerTestHarness(rate: rate, channels: channels,
                                          beforeReservation: beforeReservation)
        do { try await body(harness) }
        catch {
            await harness.cleanup()
            throw error
        }
        await harness.cleanup()
    }

    private func complete(
        file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        let completion = OwnerTestProbe()
        let task = Task {
            await operation()
            completion.finished = true
        }
        guard await ownerEventually({ completion.finished }) else {
            task.cancel()
            XCTFail("Owner operation exceeded the bounded deadline", file: file, line: line)
            throw OwnerTestError.timedOut
        }
        await task.value
    }

    private func begin(_ h: OwnerTestHarness) async throws {
        try await complete { await h.owner.start(sessionID: h.id) }
    }

    private func signal(
        _ h: OwnerTestHarness, frames: AVAudioFrameCount = 64,
        value: (Int) -> Float = { _ in 0.25 }
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: h.hardware.format, frameCapacity: frames
        ))
        buffer.frameLength = frames
        let planes = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(buffer.format.channelCount) {
            planes[channel].update(repeating: value(channel), count: Int(frames))
        }
        return buffer
    }

    private func recordOneBuffer(_ h: OwnerTestHarness) async throws {
        try await begin(h)
        try h.hardware.emit(signal(h), sampleTime: 40_000)
        let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
        XCTAssertTrue(recording)
    }

    private func durableManifest(_ directory: URL) throws -> AudioCaptureManifest {
        try JSONDecoder().decode(
            AudioCaptureManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json"))
        )
    }

    private func decode(
        _ manifest: AudioCaptureManifest, directory: URL
    ) throws -> [Float] {
        var samples: [Float] = []
        XCTAssertFalse(manifest.segments.isEmpty)
        for segment in manifest.segments {
            guard segment.relativePath == URL(fileURLWithPath: segment.relativePath).lastPathComponent,
                  segment.relativePath.hasSuffix(".caf") else { throw OwnerTestError.unsafeFixture }
            let file = try AVAudioFile(forReading: directory.appendingPathComponent(segment.relativePath))
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual((file.fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue, 16)
            XCTAssertEqual(file.length, segment.frameCount)
            guard file.length > 0, file.length <= 16_000 else { throw OwnerTestError.unexpectedAudio }
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
            ))
            try file.read(into: buffer)
            let plane = try XCTUnwrap(buffer.floatChannelData?[0])
            samples += Array(UnsafeBufferPointer(start: plane, count: Int(buffer.frameLength)))
        }
        XCTAssertEqual(Int64(samples.count), manifest.totalFrames)
        XCTAssertEqual(try durableManifest(directory), manifest)
        return samples
    }

    func testUnavailableRealModelPreventsEveryOSResourceStart() async throws {
        try await withHarness { h in
            h.preparation.result = .rejected(.modelUnavailable)
            try await begin(h)
            let snapshot = await h.owner.snapshot()
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(snapshot.phase, .failed)
            XCTAssertEqual(snapshot.failure, .modelUnavailable)
            XCTAssertFalse(snapshot.cleanupPending)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertTrue(h.probe.trace.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.path))
        }
    }

    func testStopDuringHeldPreparationWaitsForExitAndRejectsLateReady() async throws {
        try await withHarness { h in
            h.preparation.hold = true
            let startCompletion = OwnerTestProbe()
            let stopCompletion = OwnerTestProbe()
            let starting = Task {
                await h.owner.start(sessionID: h.id)
                startCompletion.finished = true
            }
            defer { starting.cancel() }
            let waiting = await ownerEventually { h.preparation.isWaiting }
            XCTAssertTrue(waiting)
            let stopping = Task {
                await h.owner.stop()
                stopCompletion.finished = true
            }
            defer { stopping.cancel() }
            let cancelling = await ownerEventually {
                let state = await h.owner.snapshot()
                return state.phase == .stopping && state.cleanupPending
            }
            XCTAssertTrue(cancelling, "Stop must reach the domain before blocked preparation returns")
            XCTAssertFalse(stopCompletion.finished, "Preparation still owns outstanding work")
            try await complete { await h.owner.start(sessionID: UUID()) }
            XCTAssertEqual(h.preparation.requests, [h.id])
            h.preparation.resolve(.ready(directory: h.directory))
            let returned = await ownerEventually { startCompletion.finished && stopCompletion.finished }
            XCTAssertTrue(returned)
            if returned { await starting.value; await stopping.value }
            let snapshot = await h.owner.snapshot()
            XCTAssertEqual(snapshot.phase, .idle)
            XCTAssertNil(snapshot.sessionID)
            XCTAssertFalse(snapshot.cleanupPending)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertTrue(h.probe.trace.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testDuplicateStartAndCoalescedStopOwnExactlyOneSetOfResources() async throws {
        try await withHarness { h in
            try await begin(h)
            try await complete { await h.owner.start(sessionID: h.id) }
            try await complete { await h.owner.start(sessionID: UUID()) }
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(h.activity.requests, [h.id])
            XCTAssertEqual(h.permission.requests, 1)
            XCTAssertEqual(h.hardware.startCalls, 1)
            h.activity.handles[0].holdEnd = true
            let firstCompletion = OwnerTestProbe()
            let secondCompletion = OwnerTestProbe()
            let first = Task {
                await h.owner.stop()
                firstCompletion.finished = true
            }
            let waiting = await ownerEventually { h.activity.handles[0].endIsWaiting }
            XCTAssertTrue(waiting)
            let second = Task {
                secondCompletion.started = true
                await h.owner.stop()
                secondCompletion.finished = true
            }
            defer { first.cancel(); second.cancel() }
            let duplicateEntered = await ownerEventually { secondCompletion.started }
            XCTAssertTrue(duplicateEntered)
            XCTAssertFalse(firstCompletion.finished)
            XCTAssertFalse(secondCompletion.finished)
            h.activity.handles[0].releaseEnd()
            let returned = await ownerEventually { firstCompletion.finished && secondCompletion.finished }
            XCTAssertTrue(returned)
            if returned { await first.value; await second.value }
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.hardware.deactivateCalls, 1)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            let snapshot = await h.owner.snapshot()
            XCTAssertEqual(snapshot.phase, .idle, "No accepted audio means no completed recording")
            XCTAssertFalse(snapshot.cleanupPending)
        }
    }

    func testActualOwnedAudioReachesRecordingOnlyWithAllThreeFactsAndProducesRealCAF() async throws {
        try await withHarness(rate: 48_000, channels: 2) { h in
            try await begin(h)
            let before = await h.owner.snapshot()
            XCTAssertEqual(before.phase, .preparing)
            XCTAssertTrue(before.readiness.activityActive)
            XCTAssertTrue(before.readiness.audioSessionActive)
            XCTAssertFalse(before.readiness.firstBufferAccepted)
            XCTAssertFalse(h.activity.handles[0].updates.contains(.recording))
            let requested = try XCTUnwrap(h.probe.trace.firstIndex(of: "activity.request"))
            let activated = try XCTUnwrap(h.probe.trace.firstIndex(of: "audio.activate"))
            XCTAssertLessThan(requested, activated, "The Activity must exist before capture starts")
            for index in 0..<4 {
                let buffer = try signal(h, frames: 480) { $0 == 0 ? 0.25 : 0.5 }
                try h.hardware.emit(buffer, sampleTime: Int64(30_000 + index * 480))
                for channel in 0..<2 {
                    buffer.floatChannelData?[channel].update(repeating: -0.75, count: 480)
                }
            }
            let recording = await ownerEventually {
                let state = await h.owner.snapshot()
                return state.phase == .recording && h.activity.handles[0].updates.contains(.recording)
            }
            XCTAssertTrue(recording)
            let active = await h.owner.snapshot()
            XCTAssertTrue(active.readiness.activityActive)
            XCTAssertTrue(active.readiness.audioSessionActive)
            XCTAssertTrue(active.readiness.firstBufferAccepted)
            try await complete { await h.owner.stop() }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .completed)
            XCTAssertFalse(final.cleanupPending)
            let manifest = try XCTUnwrap(h.owner.completedManifest)
            XCTAssertEqual(manifest.sessionID, h.id)
            XCTAssertLessThanOrEqual(abs(manifest.totalFrames - 640), 2)
            let samples = try decode(manifest, directory: h.directory)
            guard samples.count > 128 else { XCTFail("Actual converted samples are required"); return }
            for sample in samples.dropFirst(64).dropLast(64) {
                XCTAssertEqual(sample, 0.375, accuracy: 0.001)
            }
        }
    }

    func testDisabledOrInactiveActivityCannotStartTheMicrophone() async throws {
        for disabled in [true, false] {
            try await withHarness { h in
                if disabled { h.activity.areActivitiesEnabled = false }
                else { h.activity.handles[0].emit(.ended) }
                try await begin(h)
                let snapshot = await h.owner.snapshot()
                XCTAssertEqual(snapshot.phase, .failed)
                XCTAssertEqual(snapshot.failure, .activityUnavailable)
                XCTAssertFalse(snapshot.cleanupPending)
                XCTAssertEqual(h.permission.requests, 0)
                XCTAssertFalse(h.probe.trace.contains("audio.activate"))
                XCTAssertFalse(h.probe.trace.contains("audio.start"))
                XCTAssertEqual(h.activity.requests.count, disabled ? 0 : 1)
                if !disabled { XCTAssertEqual(h.activity.handles[0].endCalls, 1) }
                XCTAssertNil(h.owner.completedManifest)
            }
        }
    }

    func testDeniedMicrophoneEndsTheOwnedActivityWithoutRecordingSuccess() async throws {
        try await withHarness { h in
            h.permission.granted = false
            try await begin(h)
            let snapshot = await h.owner.snapshot()
            XCTAssertEqual(snapshot.phase, .failed)
            XCTAssertEqual(snapshot.failure, .microphoneDenied)
            XCTAssertFalse(snapshot.cleanupPending)
            XCTAssertEqual(h.activity.requests, [h.id])
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertEqual(h.permission.requests, 1)
            XCTAssertFalse(h.probe.trace.contains("audio.activate"))
            XCTAssertFalse(h.probe.trace.contains("audio.start"))
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testHeldActivityEndKeepsCleanupPendingAfterRealAudioFlushAndDeactivation() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.activity.handles[0].holdEnd = true
            let completion = OwnerTestProbe()
            let stopping = Task {
                await h.owner.stop()
                completion.finished = true
            }
            defer { stopping.cancel() }
            let waiting = await ownerEventually { h.activity.handles[0].endIsWaiting }
            XCTAssertTrue(waiting)
            let held = await h.owner.snapshot()
            XCTAssertEqual(held.phase, .stopping)
            XCTAssertTrue(held.cleanupPending)
            XCTAssertFalse(completion.finished)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
            let checkpoint = try durableManifest(h.directory)
            XCTAssertEqual(checkpoint.totalFrames, 64)
            XCTAssertEqual(try decode(checkpoint, directory: h.directory).count, 64)
            let deactivated = try XCTUnwrap(h.probe.trace.firstIndex(of: "audio.deactivate"))
            let endBegan = try XCTUnwrap(h.probe.trace.firstIndex(of: "activity.end.begin"))
            XCTAssertLessThan(deactivated, endBegan)
            h.activity.handles[0].releaseEnd()
            let returned = await ownerEventually { completion.finished }
            XCTAssertTrue(returned)
            if returned { await stopping.value }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .completed)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertEqual(h.owner.completedManifest, checkpoint)
        }
    }

    func testToggleStartsStopsAndRetriesPendingActivityCleanupWithoutNewCapture() async throws {
        try await withHarness { h in
            try await complete { await h.owner.toggle(sessionID: h.id) }
            let preparing = await h.owner.snapshot()
            XCTAssertEqual(preparing.phase, .preparing)
            let unusedID = UUID()
            try await complete { await h.owner.toggle(sessionID: unusedID) }
            let cancelled = await h.owner.snapshot()
            XCTAssertEqual(cancelled.phase, .idle)
            XCTAssertFalse(cancelled.cleanupPending)
            XCTAssertEqual(h.preparation.requests, [h.id])

            let nextID = UUID()
            let nextDirectory = h.root.appendingPathComponent("next")
            h.preparation.result = .ready(directory: nextDirectory)
            try await complete { await h.owner.toggle(sessionID: nextID) }
            try h.hardware.emit(signal(h), sampleTime: 1_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            h.activity.handles[1].endOutcome = .notFound
            try await complete { await h.owner.toggle(sessionID: unusedID) }
            let failed = await h.owner.snapshot()
            XCTAssertEqual(failed.phase, .recoverableFailure)
            XCTAssertEqual(failed.failure, .activityUnavailable)
            XCTAssertTrue(failed.cleanupPending)
            XCTAssertEqual(failed.sessionID, nextID)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertEqual(h.hardware.startCalls, 2)
            XCTAssertEqual(h.hardware.stopCalls, 2)
            XCTAssertEqual(h.activity.handles[1].endCalls, 1)
            h.activity.handles[1].endOutcome = .applied
            try await complete { await h.owner.toggle(sessionID: UUID()) }
            let settled = await h.owner.snapshot()
            XCTAssertEqual(settled.phase, .recoverableFailure)
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertEqual(h.preparation.requests, [h.id, nextID])
            XCTAssertEqual(h.hardware.startCalls, 2)
            XCTAssertEqual(h.hardware.stopCalls, 2)
            XCTAssertEqual(h.activity.handles[1].endCalls, 2)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testFailedDeactivationKeepsActivityAndExplicitStopRetryDoesNotRestartCapture() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.hardware.deactivationFailures = 1
            try await complete { await h.owner.stop() }
            let failed = await h.owner.snapshot()
            XCTAssertEqual(failed.phase, .recoverableFailure)
            XCTAssertEqual(failed.failure, .captureUnavailable)
            XCTAssertTrue(failed.cleanupPending)
            XCTAssertTrue(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertEqual(h.activity.handles[0].endCalls, 0,
                           "Keep the Activity until capture deactivation is acknowledged")
            XCTAssertNil(h.owner.completedManifest)
            try await complete { await h.owner.start(sessionID: UUID()) }
            XCTAssertEqual(h.preparation.requests, [h.id])
            try await complete { await h.owner.stop() }
            let settled = await h.owner.snapshot()
            XCTAssertEqual(settled.phase, .recoverableFailure)
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.hardware.deactivateCalls, 2)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testUnexpectedActivityLossCannotCompleteAndOldCallbacksCannotStopReplacement() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let oldObserver = try XCTUnwrap(h.activity.handles[0].observer)
            h.activity.handles[0].emit(.dismissed)
            let cleaned = await ownerEventually {
                let state = await h.owner.snapshot()
                return state.phase == .recoverableFailure && !state.cleanupPending
            }
            XCTAssertTrue(cleaned)
            let lost = await h.owner.snapshot()
            XCTAssertEqual(lost.failure, .activityUnavailable)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertNil(h.owner.completedManifest)
            let nextID = UUID()
            let nextDirectory = h.root.appendingPathComponent("replacement")
            h.preparation.result = .ready(directory: nextDirectory)
            try await complete { await h.owner.start(sessionID: nextID) }
            oldObserver(.ended)
            oldObserver(.dismissed)
            let replacement = await h.owner.snapshot()
            XCTAssertEqual(replacement.sessionID, nextID)
            XCTAssertEqual(replacement.phase, .preparing)
            XCTAssertFalse(replacement.cleanupPending)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            try h.hardware.emit(signal(h), sampleTime: 2_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            try await complete { await h.owner.stop() }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .completed)
            XCTAssertFalse(final.cleanupPending)
            let manifest = try XCTUnwrap(h.owner.completedManifest)
            XCTAssertEqual(manifest.sessionID, nextID)
            XCTAssertEqual(manifest.totalFrames, 64)
            XCTAssertEqual(try decode(manifest, directory: nextDirectory).count, 64)
        }
    }

    func testToggleDuringDomainReservationCancelsTheAdmittedStart() async throws {
        let gate = OwnerTestReservationGate()
        defer { gate.release() }
        try await withHarness(beforeReservation: { await gate.wait() }) { h in
            h.preparation.hold = true
            let one = OwnerTestProbe()
            let two = OwnerTestProbe()
            let starting = Task {
                await h.owner.start(sessionID: h.id)
                one.finished = true
            }
            defer { starting.cancel() }
            let reserved = await ownerEventually { gate.isWaiting }
            XCTAssertTrue(reserved)
            let toggling = Task {
                two.started = true
                await h.owner.toggle(sessionID: UUID())
                two.finished = true
            }
            defer { toggling.cancel() }
            let entered = await ownerEventually { two.started }
            XCTAssertTrue(entered)
            // Let the toggle consume the real actor's idle snapshot while the
            // already-admitted reservation is deliberately suspended.
            let vanished = await ownerEventually(timeout: .milliseconds(100)) { two.finished }
            XCTAssertFalse(vanished, "The admitted toggle cannot vanish into an ignored second start")
            gate.release()
            let cancelledOrClosing = await ownerEventually {
                let state = await h.owner.snapshot()
                // With no prepared resource, cancellation may settle directly
                // to idle before this observer runs. A held preflight is tested
                // separately; do not require an observable transient phase.
                return (state.phase == .stopping && state.cleanupPending)
                    || (state.phase == .idle && state.sessionID == nil && !state.cleanupPending)
            }
            XCTAssertTrue(cancelledOrClosing)
            h.preparation.resolve(.ready(directory: h.directory))
            let returned = await ownerEventually { one.finished && two.finished }
            XCTAssertTrue(returned)
            if returned { await starting.value; await toggling.value }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .idle)
            XCTAssertNil(final.sessionID)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertNil(final.failure)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testCancellingStartDuringPermissionReleasesTheActivityAndOwner() async throws {
        try await withHarness { h in
            h.permission.hold = true
            let completion = OwnerTestProbe()
            let starting = Task {
                await h.owner.start(sessionID: h.id)
                completion.finished = true
            }
            defer { starting.cancel(); h.permission.resolve() }
            let waiting = await ownerEventually { h.permission.isWaiting }
            XCTAssertTrue(waiting)
            XCTAssertEqual(h.activity.requests, [h.id])
            starting.cancel()
            h.permission.resolve()
            let returned = await ownerEventually { completion.finished }
            XCTAssertTrue(returned)
            if returned { await starting.value }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .idle)
            XCTAssertNil(final.sessionID)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertEqual(h.activity.handles[0].state, .ended)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
        }
    }
}

// TEST-FIRST DRAFT ONLY. Append this entire file to the existing
// Tests/RecordingTests/RecordingSessionOwnerTests.swift before eventual RED.
// Its private real-owner/PCM/CAF helpers are deliberately reused in that same
// file. Do not activate this as a separate Swift source file.
// Requires the documented no-op owner.stop(sessionID:) interface first.
// These eleven tests are uncompiled and have no RED/GREEN evidence.
// Also requires the documented activationFailures test-hardware boundary field.

@MainActor
private final class IntentTestOutcome {
    var value: RecordingIntentOutcome?
}

@MainActor
extension RecordingSessionOwnerTests {
    private func intentResult(
        _ router: RecordingIntentRouter,
        _ action: RecordingIntentAction
    ) async throws -> RecordingIntentOutcome {
        let result = IntentTestOutcome()
        try await complete { result.value = await router.perform(action) }
        return try XCTUnwrap(result.value)
    }

    func testIntentMissingModelReportsBlockedWithoutAnyOSResources() async throws {
        try await withHarness { h in
            h.preparation.result = .rejected(.modelUnavailable)
            let router = RecordingIntentRouter(owner: h.owner)
            let result = try await intentResult(router, .start(h.id))
            XCTAssertEqual(result, .blocked(.modelUnavailable))
            XCTAssertEqual(h.preparation.requests, [h.id])
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failure, .modelUnavailable)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertTrue(h.probe.trace.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentReportsStartingUntilActualFirstBufferThenRecording() async throws {
        try await withHarness { h in
            // Setup uses the real owner pipeline, not a fabricated snapshot.
            try await begin(h)
            let router = RecordingIntentRouter(owner: h.owner)
            let starting = try await intentResult(router, .start(h.id))
            XCTAssertEqual(starting, .starting)
            let before = await h.owner.snapshot()
            XCTAssertEqual(before.phase, .preparing)
            XCTAssertTrue(before.readiness.audioSessionActive)
            XCTAssertTrue(before.readiness.activityActive)
            XCTAssertFalse(before.readiness.firstBufferAccepted)
            try h.hardware.emit(signal(h), sampleTime: 50_000)
            let accepted = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(accepted)
            let recording = try await intentResult(router, .start(h.id))
            XCTAssertEqual(recording, .recording)
            let after = await h.owner.snapshot()
            XCTAssertEqual(after.readiness, RecordingReadiness(
                audioSessionActive: true, firstBufferAccepted: true, activityActive: true
            ))
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(h.hardware.startCalls, 1)
        }
    }

    func testIntentDuplicateStartPreservesTheExistingEpochAndResourceSet() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let router = RecordingIntentRouter(owner: h.owner)
            let same = try await intentResult(router, .start(h.id))
            let competing = try await intentResult(router, .start(UUID()))
            XCTAssertEqual(same, .recording)
            XCTAssertEqual(competing, .recording,
                           "Report the existing recording without claiming the proposed ID was admitted")
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.sessionID, h.id)
            XCTAssertEqual(state.phase, .recording)
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(h.activity.requests, [h.id])
            XCTAssertEqual(h.permission.requests, 1)
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.hardware.stopCalls, 0)
        }
    }

    func testIntentDeniedMicrophoneRequiresForegroundAfterActivityCleanup() async throws {
        try await withHarness { h in
            h.permission.granted = false
            let router = RecordingIntentRouter(owner: h.owner)
            let result = try await intentResult(router, .start(h.id))
            XCTAssertEqual(result, .requiresForeground(.microphoneDenied))
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failure, .microphoneDenied)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertEqual(h.activity.requests, [h.id])
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertEqual(h.activity.handles[0].state, .ended)
            XCTAssertEqual(h.hardware.startCalls, 0)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentUnavailableAudioSessionRequiresForegroundAfterActivityCleanup() async throws {
        try await withHarness { h in
            h.hardware.activationFailures = 1
            let router = RecordingIntentRouter(owner: h.owner)
            let result = try await intentResult(router, .start(h.id))
            XCTAssertEqual(result, .requiresForeground(.captureUnavailable))
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failure, .captureUnavailable)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertEqual(h.permission.requests, 1)
            XCTAssertEqual(h.activity.requests, [h.id])
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertEqual(h.hardware.startCalls, 0)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentDisabledOrInitiallyPendingActivityRequiresForegroundWithoutMicrophone() async throws {
        for disabled in [true, false] {
            try await withHarness { h in
                h.activity.areActivitiesEnabled = !disabled
                if !disabled { h.activity.handles[0].emit(.pending) }
                let router = RecordingIntentRouter(owner: h.owner)
                let result = try await intentResult(router, .start(h.id))
                XCTAssertEqual(result, .requiresForeground(.activityUnavailable))
                let state = await h.owner.snapshot()
                XCTAssertEqual(state.phase, .failed)
                XCTAssertEqual(state.failure, .activityUnavailable)
                XCTAssertFalse(state.cleanupPending)
                XCTAssertEqual(h.permission.requests, 0)
                XCTAssertEqual(h.hardware.startCalls, 0)
                XCTAssertFalse(h.hardware.sessionActive)
                if disabled {
                    XCTAssertTrue(h.activity.requests.isEmpty)
                } else {
                    XCTAssertEqual(h.activity.requests, [h.id])
                    XCTAssertEqual(h.activity.handles[0].endCalls, 1)
                    XCTAssertEqual(h.activity.handles[0].state, .ended)
                }
                XCTAssertNil(h.owner.completedManifest)
            }
        }
    }

    func testIntentStopAcknowledgesActualSavedCAFOnlyAfterCleanup() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let router = RecordingIntentRouter(owner: h.owner)
            let result = try await intentResult(router, .stop(expectedSessionID: h.id))
            XCTAssertEqual(result, .stopped)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .completed)
            XCTAssertEqual(state.sessionID, h.id)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.hardware.tap)
            XCTAssertEqual(h.activity.handles[0].state, .ended)
            let manifest = try XCTUnwrap(h.owner.completedManifest)
            XCTAssertEqual(manifest.sessionID, h.id)
            XCTAssertEqual(manifest.totalFrames, 64)
            let samples = try decode(manifest, directory: h.directory)
            XCTAssertEqual(samples.count, 64)
            XCTAssertTrue(samples.allSatisfy { abs($0 - 0.25) < 0.001 })
        }
    }

    func testIntentIdleStopReturnsIdleWithoutCreatingResources() async throws {
        try await withHarness { h in
            let router = RecordingIntentRouter(owner: h.owner)
            let result = try await intentResult(router, .stop(expectedSessionID: nil))
            XCTAssertEqual(result, .idle)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .idle)
            XCTAssertNil(state.sessionID)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertTrue(h.preparation.requests.isEmpty)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertTrue(h.probe.trace.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentStaleLockScreenStopCannotStopAReplacementAndMatchingOwnerStopWorks() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            try await complete { await h.owner.stop() }
            let nextID = UUID()
            let nextDirectory = h.root.appendingPathComponent("intent-replacement")
            h.preparation.result = .ready(directory: nextDirectory)
            try await complete { await h.owner.start(sessionID: nextID) }
            try h.hardware.emit(signal(h), sampleTime: 60_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            let router = RecordingIntentRouter(owner: h.owner)
            let stale = try await intentResult(router, .stop(expectedSessionID: h.id))
            XCTAssertEqual(stale, .staleSession)
            // The guard must also live in the owner: a router snapshot alone
            // cannot authorize a later unscoped stop across actor suspension.
            try await complete { await h.owner.stop(sessionID: h.id) }
            let retained = await h.owner.snapshot()
            XCTAssertEqual(retained.sessionID, nextID)
            XCTAssertEqual(retained.phase, .recording)
            XCTAssertFalse(retained.cleanupPending)
            XCTAssertEqual(h.hardware.startCalls, 2)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[1].endCalls, 0)
            XCTAssertNil(h.owner.completedManifest)
            try await complete { await h.owner.stop(sessionID: nextID) }
            let stopped = await h.owner.snapshot()
            XCTAssertEqual(stopped.phase, .completed)
            XCTAssertFalse(stopped.cleanupPending)
            XCTAssertEqual(h.hardware.stopCalls, 2)
            XCTAssertEqual(h.activity.handles[1].endCalls, 1)
            XCTAssertEqual(h.owner.completedManifest?.sessionID, nextID)
        }
    }

    func testIntentMissingActivityEndReportsCleanupPendingAndRetryNeverClaimsSavedSuccess() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.activity.handles[0].endOutcome = .notFound
            let router = RecordingIntentRouter(owner: h.owner)
            let pending = try await intentResult(router, .stop(expectedSessionID: h.id))
            XCTAssertEqual(pending, .cleanupPending)
            let failed = await h.owner.snapshot()
            XCTAssertEqual(failed.phase, .recoverableFailure)
            XCTAssertEqual(failed.failure, .activityUnavailable)
            XCTAssertTrue(failed.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertNil(h.owner.completedManifest)
            h.activity.handles[0].endOutcome = .applied
            let retry = try await intentResult(router, .stop(expectedSessionID: h.id))
            XCTAssertEqual(retry, .requiresForeground(.activityUnavailable))
            let settled = await h.owner.snapshot()
            XCTAssertEqual(settled.phase, .recoverableFailure)
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[0].endCalls, 2)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentToggleUsesOwnerPhaseAndLaterToggleCanStartANewEpoch() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let router = RecordingIntentRouter(owner: h.owner)
            let stopped = try await intentResult(router, .toggle(UUID()))
            XCTAssertEqual(stopped, .stopped)
            let completed = await h.owner.snapshot()
            XCTAssertEqual(completed.phase, .completed)
            XCTAssertFalse(completed.cleanupPending)
            XCTAssertEqual(h.preparation.requests, [h.id])
            let nextID = UUID()
            h.preparation.result = .ready(directory: h.root.appendingPathComponent("intent-toggle"))
            let starting = try await intentResult(router, .toggle(nextID))
            XCTAssertEqual(starting, .starting)
            let next = await h.owner.snapshot()
            XCTAssertEqual(next.phase, .preparing)
            XCTAssertEqual(next.sessionID, nextID)
            XCTAssertFalse(next.readiness.firstBufferAccepted)
            XCTAssertEqual(h.preparation.requests, [h.id, nextID])
            XCTAssertEqual(h.hardware.startCalls, 2)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testIntentCannotAttributeAReplacementManifestToAnEarlierStopOrToggle() async throws {
        for useToggle in [false, true] {
            try await withHarness { h in
                try await recordOneBuffer(h)
                let gate = OwnerTestReservationGate()
                defer { gate.release() }
                let router = RecordingIntentRouter(owner: h.owner, afterOperation: {
                    await gate.wait()
                })
                let result = IntentTestOutcome()
                let action: RecordingIntentAction = useToggle ? .toggle(UUID()) :
                    .stop(expectedSessionID: h.id)
                let earlier = Task { result.value = await router.perform(action) }
                let paused = await ownerEventually { gate.isWaiting }
                XCTAssertTrue(paused)
                guard paused else { earlier.cancel(); return }
                XCTAssertEqual(h.owner.completedManifest?.sessionID, h.id)

                let replacementID = UUID()
                h.preparation.result = .ready(directory:
                    h.root.appendingPathComponent("replacement-before-intent-response"))
                try await complete { await h.owner.start(sessionID: replacementID) }
                try h.hardware.emit(signal(h), sampleTime: 70_000)
                let recording = await ownerEventually {
                    await h.owner.snapshot().phase == .recording
                }
                XCTAssertTrue(recording)
                try await complete { await h.owner.stop(sessionID: replacementID) }
                let replacement = try XCTUnwrap(h.owner.completedManifest)
                XCTAssertEqual(replacement.sessionID, replacementID)
                XCTAssertEqual(try decode(replacement, directory:
                    h.root.appendingPathComponent("replacement-before-intent-response")).count, 64)

                gate.release()
                try await complete { await earlier.value }
                XCTAssertEqual(result.value, .staleSession,
                               "A delayed response cannot claim the replacement's saved media")
                XCTAssertEqual(h.owner.completedManifest, replacement)
                let final = await h.owner.snapshot()
                XCTAssertEqual(final.sessionID, replacementID)
                XCTAssertEqual(final.phase, .completed)
                XCTAssertFalse(final.cleanupPending)
                XCTAssertEqual(h.hardware.startCalls, 2)
                XCTAssertEqual(h.hardware.stopCalls, 2)
            }
        }
    }
}

#if os(iOS) && !SWIFT_PACKAGE
import AppIntents

// Append to the SAME RecordingSessionOwnerTests.swift file so private helpers
// are reused. Only native app-host tests compile this conditional extension.
// Original ten native cases proved37-case RED at81960fd, then38-case GREEN
// including the extra SDK probe at7c1ae7c. The preparing-toggle regression below
// is newly test-first and has no executed RED yet.

@MainActor
private final class NativeIntentCall {
    var error: (any Error)?
    var reply: RecordingNativeResult?
}

@MainActor
private final class NativeIntentForeground: RecordingForegroundContinuation {
    private(set) var requests: [RecordingFailure] = []
    var shouldReject = true

    func requestContinuation(for failure: RecordingFailure) async throws {
        requests.append(failure)
        if shouldReject { throw RecordingNativeIntentError.foregroundUnavailable }
    }
}

@MainActor
extension RecordingSessionOwnerTests {
    private func nativeCall(
        _ body: @escaping @MainActor @Sendable () async throws -> RecordingNativeResult
    ) async throws -> NativeIntentCall {
        let result = NativeIntentCall()
        try await complete {
            do { result.reply = try await body() }
            catch { result.error = error }
        }
        return result
    }

    func testNativeDefaultRootAndIntentsShareApplicationAndMissingModelIsBlocked() async throws {
        let shared = RecordingApplication.shared
        let root = LocalMinutesApp()
        XCTAssertTrue(root.application === shared)
        XCTAssertTrue(StartMeetingIntent().application === shared)
        XCTAssertTrue(StopMeetingIntent().application === shared)
        XCTAssertTrue(ToggleMeetingIntent().application === shared)
        XCTAssertNotNil(shared.owner, "The production default must own the real resource composition")
        let call = try await nativeCall { try await StartMeetingIntent().perform() }
        XCTAssertNil(call.error, "Model unavailability is a truthful blocked result, not recording success")
        XCTAssertEqual(call.reply?.value, "A verified speech model is required before recording.")
        XCTAssertNotNil(call.reply?.dialog)
        XCTAssertEqual(shared.lastOutcome, .blocked(.modelUnavailable))
        if let owner = shared.owner {
            let state = await owner.snapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failure, .modelUnavailable)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(state.readiness.audioSessionActive)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(state.readiness.activityActive)
            XCTAssertNil(owner.completedManifest)
        }
    }

    func testNativeStartUsesInjectedRealOwnerAndWaitsForActualBufferReadiness() async throws {
        try await withHarness { h in
            let app = RecordingApplication(owner: h.owner)
            let intent = StartMeetingIntent(application: app)
            XCTAssertTrue(intent.application === app)
            XCTAssertTrue(app.owner === h.owner)
            let call = try await nativeCall { try await intent.perform() }
            XCTAssertNil(call.error)
            XCTAssertEqual(call.reply?.value, "Preparing recording.")
            XCTAssertNotNil(call.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .starting)
            let before = await h.owner.snapshot()
            XCTAssertEqual(before.phase, .preparing)
            XCTAssertFalse(before.readiness.firstBufferAccepted)
            guard let sessionID = before.sessionID else {
                XCTFail("The actual native intent must admit a real owner epoch")
                return
            }
            XCTAssertEqual(h.preparation.requests, [sessionID])
            XCTAssertEqual(h.activity.requests, [sessionID])
            try h.hardware.emit(signal(h), sampleTime: 80_000)
            let recorded = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recorded)
            let duplicate = try await nativeCall {
                try await StartMeetingIntent(application: app).perform()
            }
            XCTAssertNil(duplicate.error)
            XCTAssertEqual(duplicate.reply?.value, "Recording is active.")
            XCTAssertNotNil(duplicate.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .recording)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.sessionID, sessionID)
            XCTAssertEqual(state.readiness, RecordingReadiness(
                audioSessionActive: true, firstBufferAccepted: true, activityActive: true
            ))
            XCTAssertEqual(h.preparation.requests, [sessionID])
            XCTAssertEqual(h.hardware.startCalls, 1)
        }
    }

    func testNativeGenericStopWaitsForActualSavedCAFAndAllResourceCleanup() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let app = RecordingApplication(owner: h.owner)
            let call = try await nativeCall {
                try await StopMeetingIntent(application: app).perform()
            }
            XCTAssertNil(call.error)
            XCTAssertEqual(call.reply?.value, "Recording saved.")
            XCTAssertNotNil(call.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .stopped)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .completed)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertNil(h.hardware.tap)
            XCTAssertEqual(h.activity.handles[0].state, .ended)
            guard let manifest = h.owner.completedManifest else {
                XCTFail("A saved result requires the actual matching media manifest")
                return
            }
            XCTAssertEqual(manifest.sessionID, h.id)
            let samples = try decode(manifest, directory: h.directory)
            XCTAssertEqual(samples.count, 64)
            XCTAssertTrue(samples.allSatisfy { abs($0 - 0.25) < 0.001 })
        }
    }

    func testNativeToggleStopsExistingOwnerAndLaterInvocationStartsNewEpoch() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let app = RecordingApplication(owner: h.owner)
            let stopped = try await nativeCall {
                try await ToggleMeetingIntent(application: app).perform()
            }
            XCTAssertNil(stopped.error)
            XCTAssertEqual(stopped.reply?.value, "Recording saved.")
            XCTAssertNotNil(stopped.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .stopped)
            let completed = await h.owner.snapshot()
            XCTAssertEqual(completed.phase, .completed)
            XCTAssertFalse(completed.cleanupPending)
            h.preparation.result = .ready(directory: h.root.appendingPathComponent("native-toggle"))
            let starting = try await nativeCall {
                try await ToggleMeetingIntent(application: app).perform()
            }
            XCTAssertNil(starting.error)
            XCTAssertEqual(starting.reply?.value, "Preparing recording.")
            XCTAssertNotNil(starting.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .starting)
            let next = await h.owner.snapshot()
            XCTAssertEqual(next.phase, .preparing)
            XCTAssertNotNil(next.sessionID)
            XCTAssertNotEqual(next.sessionID, h.id)
            XCTAssertFalse(next.readiness.firstBufferAccepted)
            XCTAssertEqual(h.hardware.startCalls, 2)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.preparation.requests.count, 2)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testNativeActivityStopParameterRejectsMalformedAndStaleIDsBeforeMatchingStop() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            try await complete { await h.owner.stop() }
            let nextID = UUID()
            h.preparation.result = .ready(directory: h.root.appendingPathComponent("native-replacement"))
            try await complete { await h.owner.start(sessionID: nextID) }
            try h.hardware.emit(signal(h), sampleTime: 90_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            let app = RecordingApplication(owner: h.owner)
            let invalid = try await nativeCall {
                try await StopRecordingActivityIntent(sessionID: "", application: app).perform()
            }
            XCTAssertEqual(invalid.error as? RecordingNativeIntentError, .invalidSession)
            XCTAssertNil(invalid.reply)
            XCTAssertNil(app.lastOutcome)
            let oldAttributes = RecordingActivityAttributes(meetingID: h.id)
            let staleIntent = StopRecordingActivityIntent(
                sessionID: oldAttributes.meetingID.uuidString, application: app
            )
            XCTAssertEqual(staleIntent.sessionID, oldAttributes.meetingID.uuidString)
            let stale = try await nativeCall { try await staleIntent.perform() }
            XCTAssertNil(stale.error)
            XCTAssertEqual(stale.reply?.value, "This control belongs to an earlier recording.")
            XCTAssertNotNil(stale.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .staleSession)
            let retained = await h.owner.snapshot()
            XCTAssertEqual(retained.sessionID, nextID)
            XCTAssertEqual(retained.phase, .recording)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[1].endCalls, 0)
            let matching = try await nativeCall {
                try await StopRecordingActivityIntent(
                    sessionID: nextID.uuidString, application: app
                ).perform()
            }
            XCTAssertNil(matching.error)
            XCTAssertEqual(matching.reply?.value, "Recording saved.")
            XCTAssertNotNil(matching.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .stopped)
            let settled = await h.owner.snapshot()
            XCTAssertEqual(settled.phase, .completed)
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertEqual(h.hardware.stopCalls, 2)
            XCTAssertEqual(h.owner.completedManifest?.sessionID, nextID)
        }
    }

    func testNativeStopKeepsFailedEndPendingAndExplicitRetryPreservesFailure() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.activity.handles[0].endOutcome = .notFound
            let foreground = NativeIntentForeground()
            foreground.shouldReject = false
            let app = RecordingApplication(owner: h.owner, foreground: foreground)
            let first = try await nativeCall {
                try await StopMeetingIntent(application: app).perform()
            }
            XCTAssertNil(first.error)
            XCTAssertEqual(first.reply?.value, "Stopping is still pending. Open LocalMinutes.")
            XCTAssertNotNil(first.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .cleanupPending)
            let failed = await h.owner.snapshot()
            XCTAssertEqual(failed.phase, .recoverableFailure)
            XCTAssertTrue(failed.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertTrue(foreground.requests.isEmpty)
            h.activity.handles[0].endOutcome = .applied
            let retried = try await nativeCall {
                try await StopMeetingIntent(application: app).perform()
            }
            XCTAssertNil(retried.error)
            XCTAssertEqual(retried.reply?.value,
                           "Open LocalMinutes to review recording permissions and status.")
            XCTAssertNotNil(retried.reply?.dialog)
            XCTAssertEqual(app.lastOutcome, .requiresForeground(.activityUnavailable))
            XCTAssertEqual(foreground.requests, [.activityUnavailable])
            let settled = await h.owner.snapshot()
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertEqual(settled.failure, .activityUnavailable)
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[0].endCalls, 2)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testNativeForegroundRequestFailureNeverChangesDeniedCaptureIntoSuccess() async throws {
        try await withHarness { h in
            h.permission.granted = false
            let foreground = NativeIntentForeground()
            let app = RecordingApplication(owner: h.owner, foreground: foreground)
            let call = try await nativeCall {
                try await StartMeetingIntent(application: app).perform()
            }
            XCTAssertEqual(call.error as? RecordingNativeIntentError, .foregroundUnavailable)
            XCTAssertNil(call.reply, "A failed foreground transition cannot return recording success")
            XCTAssertEqual(app.lastOutcome, .requiresForeground(.microphoneDenied))
            XCTAssertEqual(foreground.requests, [.microphoneDenied])
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failure, .microphoneDenied)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            XCTAssertNil(h.owner.completedManifest)
        }
    }

    func testNativeSDKConformancesAndThreeDiscoverableShortcutsArePresent() async throws {
        func acceptsRecordingAndActivity<I: AudioRecordingIntent & LiveActivityIntent>(_: I.Type) {}
        acceptsRecordingAndActivity(StartMeetingIntent.self)
        acceptsRecordingAndActivity(StopMeetingIntent.self)
        acceptsRecordingAndActivity(ToggleMeetingIntent.self)
        acceptsRecordingAndActivity(StopRecordingActivityIntent.self)
        XCTAssertTrue(StartMeetingIntent.isDiscoverable)
        XCTAssertTrue(StopMeetingIntent.isDiscoverable)
        XCTAssertTrue(ToggleMeetingIntent.isDiscoverable)
        XCTAssertFalse(StopRecordingActivityIntent.isDiscoverable)
        XCTAssertEqual(LocalMinutesShortcuts.appShortcuts.count, 3)
        if #available(iOS 26.0, *) {
            for modes in [StartMeetingIntent.supportedModes, StopMeetingIntent.supportedModes,
                          ToggleMeetingIntent.supportedModes] {
                XCTAssertTrue(modes.contains(.background))
                XCTAssertTrue(modes.contains(.foreground(.dynamic)))
            }
        }
    }

    func testNativeOverlappingTogglesShareOneCleanupAndALaterCallCanStart() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            h.activity.handles[0].holdEnd = true
            defer { h.activity.handles[0].releaseEnd() }
            let app = RecordingApplication(owner: h.owner)
            let first = NativeIntentCall()
            let firstTask = Task {
                do { first.reply = try await ToggleMeetingIntent(application: app).perform() }
                catch { first.error = error }
            }
            let held = await ownerEventually { h.activity.handles[0].endIsWaiting }
            XCTAssertTrue(held, "The native command must reach the real held cleanup barrier")
            guard held else { firstTask.cancel(); return }
            let second = NativeIntentCall()
            let secondProbe = OwnerTestProbe()
            let secondTask = Task {
                secondProbe.started = true
                do { second.reply = try await ToggleMeetingIntent(application: app).perform() }
                catch { second.error = error }
            }
            let entered = await ownerEventually { secondProbe.started }
            XCTAssertTrue(entered)
            XCTAssertNil(second.reply)
            XCTAssertNil(second.error)
            h.activity.handles[0].releaseEnd()
            try await complete { await firstTask.value; await secondTask.value }
            XCTAssertNil(first.error)
            XCTAssertNil(second.error)
            XCTAssertEqual(first.reply?.value, "Recording saved.")
            XCTAssertEqual(second.reply?.value, "Recording saved.")
            XCTAssertEqual(h.preparation.requests, [h.id])
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            XCTAssertEqual(h.activity.handles[0].endCalls, 1)
            h.preparation.result = .ready(directory: h.root.appendingPathComponent("later-native-toggle"))
            let later = try await nativeCall {
                try await ToggleMeetingIntent(application: app).perform()
            }
            XCTAssertNil(later.error)
            XCTAssertEqual(later.reply?.value, "Preparing recording.")
            XCTAssertEqual(h.preparation.requests.count, 2)
            XCTAssertEqual(h.hardware.startCalls, 2)
        }
    }

    func testNativeCancelledStartAndToggleCannotActivateAfterHeldModelPreparation() async throws {
        for useToggle in [false, true] {
            try await withHarness { h in
                h.preparation.hold = true
                let app = RecordingApplication(owner: h.owner)
                let call = NativeIntentCall()
                let task = Task {
                    do {
                        if useToggle {
                            call.reply = try await ToggleMeetingIntent(application: app).perform()
                        } else {
                            call.reply = try await StartMeetingIntent(application: app).perform()
                        }
                    } catch { call.error = error }
                }
                let held = await ownerEventually { h.preparation.isWaiting }
                XCTAssertTrue(held, "Cancellation must reach actual owner preparation")
                guard held else { task.cancel(); return }
                task.cancel()
                h.preparation.resolve(.ready(directory: h.directory))
                try await complete { await task.value }
                let state = await h.owner.snapshot()
                XCTAssertEqual(state.phase, .idle)
                XCTAssertNil(state.sessionID)
                XCTAssertFalse(state.cleanupPending)
                XCTAssertFalse(state.readiness.audioSessionActive)
                XCTAssertTrue(h.activity.requests.isEmpty)
                XCTAssertEqual(h.permission.requests, 0)
                XCTAssertEqual(h.hardware.startCalls, 0)
                XCTAssertFalse(h.hardware.sessionActive)
                XCTAssertNil(h.owner.completedManifest)
                XCTAssertNotEqual(call.reply?.value, "Recording is active.")
                XCTAssertNotEqual(call.reply?.value, "Recording saved.")
            }
        }
    }

    func testNativeSecondToggleCancelsHeldPreparationInsteadOfCoalescingAStart() async throws {
        try await withHarness { h in
            h.preparation.hold = true
            let app = RecordingApplication(owner: h.owner)
            let first = NativeIntentCall()
            let firstTask = Task {
                do { first.reply = try await ToggleMeetingIntent(application: app).perform() }
                catch { first.error = error }
            }
            let held = await ownerEventually { h.preparation.isWaiting }
            XCTAssertTrue(held)
            guard held else { firstTask.cancel(); return }
            let second = NativeIntentCall()
            let secondTask = Task {
                do { second.reply = try await ToggleMeetingIntent(application: app).perform() }
                catch { second.error = error }
            }
            let cancelling = await ownerEventually { await h.owner.snapshot().cleanupPending }
            XCTAssertTrue(cancelling,
                          "A second user toggle during preparation must close that admitted start")
            XCTAssertTrue(h.preparation.isWaiting,
                          "Cleanup must wait for the actual held model boundary to exit")
            XCTAssertNil(first.reply)
            XCTAssertNil(second.reply)
            h.preparation.resolve(.ready(directory: h.directory))
            try await complete { await firstTask.value; await secondTask.value }
            XCTAssertNil(first.error)
            XCTAssertNil(second.error)
            XCTAssertEqual(first.reply?.value, "No recording is active.")
            XCTAssertEqual(second.reply?.value, "No recording is active.")
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .idle)
            XCTAssertNil(state.sessionID)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertEqual(h.preparation.requests.count, 1)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertEqual(h.hardware.startCalls, 0)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertNil(h.owner.completedManifest)
        }
    }
}
#endif


// APPEND this entire fragment to the END of
// Tests/RecordingTests/RecordingSessionOwnerTests.swift. It reuses private
// helpers only in that same file; all existing assertions remain unchanged.

#if os(iOS)
@MainActor
extension RecordingSessionOwnerTests {
    func testNativeInterruptionNotificationDrainsCAFWaitsForCleanupAndRejectsOldTap() async throws {
        try await withHarness { h in
            try await recordOneBuffer(h)
            let oldTap = try XCTUnwrap(h.hardware.tap)
            let center = NotificationCenter()
            let monitor = IOSRecordingSignalMonitor(owner: h.owner, center: center)
            monitor.beginEpoch(sessionID: h.id)
            defer { monitor.endEpoch(sessionID: h.id); h.preparation.resolveFinish() }
            h.preparation.holdFinish = true
            center.post(name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            let joined = OwnerTestProbe()
            let flushing = Task { await monitor.flush(); joined.finished = true }
            defer { flushing.cancel() }
            let arrived = await ownerEventually { h.preparation.finishIsWaiting || joined.finished }
            XCTAssertTrue(arrived)
            XCTAssertTrue(h.preparation.finishIsWaiting)
            XCTAssertFalse(joined.finished, "Notification cleanup cannot acknowledge before transcript finish")
            let pending = await h.owner.snapshot()
            XCTAssertEqual(pending.phase, .interrupted)
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
            h.preparation.resolveFinish()
            try await complete { await flushing.value }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .interrupted)
            XCTAssertFalse(final.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertNil(h.hardware.tap)
            XCTAssertEqual(h.hardware.stopCalls, 1)
            let checkpointURL = h.directory.appendingPathComponent("capture-manifest.json")
            let bytes = try? Data(contentsOf: checkpointURL)
            XCTAssertNotNil(bytes)
            if let bytes {
                let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: bytes)
                XCTAssertEqual(manifest.sessionID, h.id)
                XCTAssertEqual(manifest.totalFrames, 64)
                XCTAssertEqual(try decode(manifest, directory: h.directory).count, 64)
            }
            let late = try signal(h)
            oldTap(late, AVAudioTime(sampleTime: 40_064, atRate: h.hardware.format.sampleRate))
            let afterLateBuffer = await h.owner.snapshot()
            XCTAssertEqual(afterLateBuffer.phase, .interrupted)
            XCTAssertFalse(afterLateBuffer.readiness.firstBufferAccepted)
            XCTAssertFalse(afterLateBuffer.readiness.audioSessionActive)
            XCTAssertEqual(try? Data(contentsOf: checkpointURL), bytes,
                "A retained old audio callback cannot add samples after interrupted flush")
        }
    }

    func testNativeMediaResetCancelsPendingCaptureAndStaleEpochEndCannotDetachReplacement() async throws {
        try await withHarness { h in
            let center = NotificationCenter()
            let monitor = IOSRecordingSignalMonitor(owner: h.owner, center: center)
            h.permission.hold = true
            let starting = Task { await h.owner.start(sessionID: h.id) }
            defer { starting.cancel(); h.permission.resolve(); monitor.endEpoch(sessionID: h.id) }
            let held = await ownerEventually { h.permission.isWaiting }
            XCTAssertTrue(held)
            monitor.beginEpoch(sessionID: h.id)
            center.post(name: AVAudioSession.mediaServicesWereResetNotification,
                        object: AVAudioSession.sharedInstance())
            try await complete { await monitor.flush() }
            let pendingInterrupted = await h.owner.snapshot()
            XCTAssertEqual(pendingInterrupted.phase, .interrupted)
            XCTAssertFalse(pendingInterrupted.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertEqual(h.hardware.startCalls, 0)
            h.permission.resolve()
            try await complete { await starting.value }
            XCTAssertEqual(h.hardware.startCalls, 0, "The old permission grant cannot reactivate reset capture")
            XCTAssertFalse(h.hardware.sessionActive)
            // Ensures a no-op RED stub also releases its real resources before
            // the replacement portion; this never changes the assertions above.
            try await complete { await h.owner.stop() }

            let replacementID = UUID()
            let replacementDirectory = h.root.appendingPathComponent("reset-replacement", isDirectory: true)
            h.preparation.result = .ready(directory: replacementDirectory)
            monitor.beginEpoch(sessionID: replacementID)
            defer { monitor.endEpoch(sessionID: replacementID) }
            try await complete { await h.owner.start(sessionID: replacementID) }
            try h.hardware.emit(signal(h), sampleTime: 90_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            monitor.endEpoch(sessionID: h.id)
            center.post(name: AVAudioSession.mediaServicesWereResetNotification,
                        object: AVAudioSession.sharedInstance())
            try await complete { await monitor.flush() }
            let replacement = await h.owner.snapshot()
            XCTAssertEqual(replacement.sessionID, replacementID)
            XCTAssertEqual(replacement.phase, .interrupted,
                "A stale old-epoch end cannot remove the replacement's native signal observation")
            XCTAssertFalse(replacement.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
            let data = try? Data(contentsOf: replacementDirectory.appendingPathComponent("capture-manifest.json"))
            XCTAssertNotNil(data)
            if let data {
                let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: data)
                XCTAssertEqual(manifest.sessionID, replacementID)
                XCTAssertEqual(manifest.totalFrames, 64)
                XCTAssertEqual(try decode(manifest, directory: replacementDirectory).count, 64)
            }
        }
    }
}
#endif


// APPEND to Tests/RecordingTests/RecordingSessionOwnerTests.swift after the final
// #endif. Existing file-private real owner/CAF helpers remain unchanged.
#if os(iOS)
@MainActor
extension RecordingSessionOwnerTests {
    func testNativeApplicationRetainsSignalObservationAfterStartReturnsAndInterruptsActualCAF() async throws {
        try await withHarness { h in
            let center = NotificationCenter()
            let application = RecordingApplication(owner: h.owner, signalCenter: center)
            let result = NativeIntentCall()
            try await complete {
                do { result.reply = try await StartMeetingIntent(application: application).perform() }
                catch { result.error = error }
            }
            XCTAssertNil(result.error)
            XCTAssertEqual(result.reply?.value, "Preparing recording.")
            try h.hardware.emit(signal(h), sampleTime: 40_000)
            let recording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            // Perform's start task has returned. Only the retained application
            // may keep native observation alive; the test owns no monitor.
            center.post(name: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            try await complete { await application.flushSignals() }
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .interrupted)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(state.readiness.audioSessionActive)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertNil(h.hardware.tap)
            let data = try? Data(contentsOf: h.directory.appendingPathComponent("capture-manifest.json"))
            XCTAssertNotNil(data)
            if let data {
                let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: data)
                // StartMeetingIntent allocates its own epoch UUID.
                XCTAssertEqual(manifest.sessionID, state.sessionID)
                XCTAssertEqual(manifest.totalFrames, 64)
                XCTAssertEqual(try decode(manifest, directory: h.directory).count, 64)
            }
        }
    }

    func testNativeStaleAppStopCannotDetachReplacementSignalObservation() async throws {
        try await withHarness { h in
            let center = NotificationCenter()
            let application = RecordingApplication(owner: h.owner, signalCenter: center)
            let first = NativeAppSignalOutcome()
            try await complete {
                do { first.value = try await application.perform(.start(h.id)) }
                catch { first.error = error }
            }
            XCTAssertNil(first.error)
            XCTAssertEqual(first.value, .starting)
            try h.hardware.emit(signal(h), sampleTime: 40_000)
            let initial = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(initial)
            let stopped = NativeAppSignalOutcome()
            try await complete {
                do { stopped.value = try await application.perform(.stop(expectedSessionID: h.id)) }
                catch { stopped.error = error }
            }
            XCTAssertNil(stopped.error)
            XCTAssertEqual(stopped.value, .stopped)
            XCTAssertNotNil(h.owner.completedManifest)
            let replacementID = UUID()
            let replacementDirectory = h.root.appendingPathComponent("app-signal-replacement", isDirectory: true)
            h.preparation.result = .ready(directory: replacementDirectory)
            let started = NativeAppSignalOutcome()
            try await complete {
                do { started.value = try await application.perform(.start(replacementID)) }
                catch { started.error = error }
            }
            XCTAssertNil(started.error)
            XCTAssertEqual(started.value, .starting)
            try h.hardware.emit(signal(h), sampleTime: 90_000)
            let active = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(active)
            let stale = NativeAppSignalOutcome()
            try await complete {
                do { stale.value = try await application.perform(.stop(expectedSessionID: h.id)) }
                catch { stale.error = error }
            }
            XCTAssertNil(stale.error)
            XCTAssertEqual(stale.value, .staleSession)
            center.post(name: AVAudioSession.mediaServicesWereResetNotification,
                        object: AVAudioSession.sharedInstance())
            try await complete { await application.flushSignals() }
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.sessionID, replacementID)
            XCTAssertEqual(state.phase, .interrupted,
                "Stale Stop may not tear down observation for the matching replacement epoch")
            XCTAssertFalse(state.cleanupPending)
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
            let data = try? Data(contentsOf: replacementDirectory.appendingPathComponent("capture-manifest.json"))
            XCTAssertNotNil(data)
            if let data {
                let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: data)
                XCTAssertEqual(manifest.sessionID, replacementID)
                XCTAssertEqual(manifest.totalFrames, 64)
                XCTAssertEqual(try decode(manifest, directory: replacementDirectory).count, 64)
            }
        }
    }
}

@MainActor
private final class NativeAppSignalOutcome {
    var value: RecordingIntentOutcome?
    var error: Error?
}

@MainActor
extension RecordingSessionOwnerTests {
    func testNativeApplicationObservesResetBeforePermissionReturnsAndRejectsLateGrant() async throws {
        try await withHarness { h in
            let center = NotificationCenter()
            let application = RecordingApplication(owner: h.owner, signalCenter: center)
            h.permission.hold = true
            let result = NativeAppSignalOutcome()
            let starting = Task {
                do { result.value = try await application.perform(.start(h.id)) }
                catch { result.error = error }
            }
            defer { starting.cancel(); h.permission.resolve() }
            let held = await ownerEventually { h.permission.isWaiting }
            XCTAssertTrue(held)
            center.post(name: AVAudioSession.mediaServicesWereResetNotification,
                        object: AVAudioSession.sharedInstance())
            try await complete { await application.flushSignals() }
            let interrupted = await h.owner.snapshot()
            XCTAssertEqual(interrupted.phase, .interrupted)
            XCTAssertFalse(interrupted.cleanupPending)
            XCTAssertEqual(h.hardware.startCalls, 0)
            h.permission.resolve()
            try await complete { await starting.value }
            XCTAssertNil(result.error)
            XCTAssertEqual(h.hardware.startCalls, 0, "A late grant cannot start after an app-observed reset")
            XCTAssertFalse(h.hardware.sessionActive)
            XCTAssertFalse(h.hardware.engineRunning)
            XCTAssertNil(h.owner.completedManifest)
        }
    }
}
#endif


// APPEND to Tests/RecordingTests/RecordingSessionOwnerTests.swift outside any
// #if os(iOS) block. Reuses the same-file actual owner/CAF harness in SPM/native.
// No production change or new helper is required for behavioral RED.
@MainActor
extension RecordingSessionOwnerTests {
    func testInterruptionDuringHeldModelPreparationSettlesInterruptedAndAllowsReplacement() async throws {
        try await withHarness { h in
            h.preparation.hold = true
            let started = OwnerTestProbe()
            let interrupted = OwnerTestProbe()
            let starting = Task {
                await h.owner.start(sessionID: h.id)
                started.finished = true
            }
            defer { starting.cancel(); h.preparation.resolve(.rejected(.modelUnavailable)) }
            let waiting = await ownerEventually { h.preparation.isWaiting }
            XCTAssertTrue(waiting, "Hold model preparation before coordinator activation or microphone permission")
            guard waiting else { return }
            let interrupting = Task {
                await h.owner.interrupt(sessionID: h.id)
                interrupted.finished = true
            }
            defer { interrupting.cancel() }
            let latched = await ownerEventually {
                let state = await h.owner.snapshot()
                return state.phase == .interrupted && state.cleanupPending
            }
            XCTAssertTrue(latched, "An interruption must own cleanup even before activationIssued")
            XCTAssertFalse(interrupted.finished, "Held preparation still owns unfinished resources")
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertEqual(h.hardware.startCalls, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertNil(h.owner.completedManifest)
            h.preparation.resolve(.ready(directory: h.directory))
            let settled = await ownerEventually { started.finished && interrupted.finished }
            XCTAssertTrue(settled, "Both waiters must join the same bounded teardown")
            guard settled else { return }
            await starting.value; await interrupting.value
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.sessionID, h.id)
            XCTAssertEqual(state.phase, .interrupted)
            XCTAssertFalse(state.cleanupPending)
            XCTAssertNil(state.failure)
            XCTAssertFalse(state.readiness.audioSessionActive)
            XCTAssertFalse(state.readiness.firstBufferAccepted)
            XCTAssertFalse(state.readiness.activityActive)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertEqual(h.hardware.startCalls, 0)
            XCTAssertTrue(h.activity.requests.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory.path))
            XCTAssertNil(h.owner.completedManifest)

            // Prove the internal coordinator is reusable, not just that the
            // resource epoch disappeared while its phase stayed .preparing.
            let replacementID = UUID()
            h.preparation.result = .ready(directory: h.root.appendingPathComponent("replacement", isDirectory: true))
            try await complete { await h.owner.start(sessionID: replacementID) }
            XCTAssertEqual(h.preparation.requests, [h.id, replacementID])
            if h.hardware.tap != nil { try h.hardware.emit(signal(h), sampleTime: 90_000) }
            let replacementRecording = await ownerEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(replacementRecording, "An interrupted preparation must not permanently wedge future recording")
            let replacement = await h.owner.snapshot()
            XCTAssertEqual(replacement.sessionID, replacementID)
            XCTAssertEqual(h.hardware.startCalls, 1)
            XCTAssertEqual(h.activity.requests, [replacementID])
            try await complete { await h.owner.stop(sessionID: replacementID) }
        }
    }
}
