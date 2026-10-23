import AVFoundation
import AudioToolbox
import Foundation
import XCTest
import LocalMinutesCore
@testable import LocalMinutesRecording

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

    init(directory: URL) { result = .ready(directory: directory) }

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
    var deactivationFailures = 0

    init(probe: OwnerTestProbe, rate: Double, channels: AVAudioChannelCount) throws {
        self.probe = probe
        format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: rate, channels: channels
        ))
    }

    func activateSession() throws {
        probe.trace.append("audio.activate")
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
            let closing = await ownerEventually {
                let state = await h.owner.snapshot()
                return state.phase == .stopping && state.cleanupPending
            }
            XCTAssertTrue(closing)
            h.preparation.resolve(.ready(directory: h.directory))
            let returned = await ownerEventually { one.finished && two.finished }
            XCTAssertTrue(returned)
            if returned { await starting.value; await toggling.value }
            let final = await h.owner.snapshot()
            XCTAssertEqual(final.phase, .idle)
            XCTAssertNil(final.sessionID)
            XCTAssertFalse(final.cleanupPending)
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
