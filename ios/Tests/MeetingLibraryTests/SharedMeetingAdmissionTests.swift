import AVFoundation
import Foundation
import XCTest
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
#else
@testable import LocalMinutes
#endif

// Shared admission/lifecycle evidence only. Permission, model preparation and
// ActivityKit/hardware are boundaries; SQLite, deletion, coordinator, capture
// queue/conversion and CAF bytes are actual. No inference/device pass is claimed.
private enum SharedAdmissionTestError: Error { case timedOut, unsafeFixture }

@MainActor
private func admissionEventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

@MainActor
private final class SharedAdmissionLatch {
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
private final class SharedAdmissionPreparation: RecordingPreparationSource {
    let store: SQLiteMeetingStore
    let recordings: URL
    var prepareLatch: SharedAdmissionLatch?
    var finishLatch: SharedAdmissionLatch?
    private(set) var requests: [UUID] = []
    private(set) var finishes: [UUID] = []
    init(store: SQLiteMeetingStore, recordings: URL) { self.store = store; self.recordings = recordings }
    func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        requests.append(sessionID)
        await prepareLatch?.wait()
        if Task.isCancelled { return .rejected(.modelUnavailable) }
        do {
            if try await store.meeting(id: sessionID) == nil {
                try await store.createMeeting(MeetingRecord(id: sessionID, title: "Original admission fixture",
                    createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recording))
            }
            return .ready(directory: recordings.appendingPathComponent(sessionID.uuidString, isDirectory: true))
        } catch { return .rejected(.writeFailed) }
    }
    func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure? {
        finishes.append(sessionID)
        await finishLatch?.wait()
        return nil
    }
}

@MainActor
private final class SharedAdmissionPermission: CapturePermissionSource {
    var latch: SharedAdmissionLatch?
    private(set) var requests = 0
    func requestRecordPermission() async -> Bool { requests += 1; await latch?.wait(); return true }
}

@MainActor
private final class SharedAdmissionHardware: CaptureHardware {
    let format: AVAudioFormat
    private(set) var tap: CaptureTapHandler?
    private(set) var activations = 0
    private(set) var running = false
    private(set) var active = false
    init() throws {
        format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    }
    func activateSession() throws { activations += 1; active = true }
    func inputFormat() throws -> AVAudioFormat { format }
    func installTap(_ handler: @escaping CaptureTapHandler) throws { tap = handler }
    func startEngine() throws { running = true }
    func stopEngine() { running = false }
    func removeTap() { tap = nil }
    func deactivateSession() throws { active = false }
    func emit() throws {
        let samples = try sharedAdmissionSignal(format: format)
        let callback = try XCTUnwrap(tap)
        callback(samples, AVAudioTime(sampleTime: 9_000, atRate: 16_000))
    }
}

private func sharedAdmissionSignal(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
    buffer.frameLength = 64
    try XCTUnwrap(buffer.floatChannelData?[0]).update(repeating: 0.25, count: 64)
    return buffer
}

@MainActor
private final class SharedAdmissionActivity: LiveActivityHandle {
    private(set) var state: LiveActivityResourceState = .active
    private var observer: LiveActivityStateObserver?
    func setStateObserver(_ observer: LiveActivityStateObserver?) { self.observer = observer }
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome { .applied }
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        state = .ended
        observer?(.ended)
        return .applied
    }
}

@MainActor
private final class SharedAdmissionActivityBackend: LiveActivityBackend {
    private(set) var handles: [SharedAdmissionActivity] = []
    var areActivitiesEnabled: Bool { true }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle {
        let handle = SharedAdmissionActivity()
        handles.append(handle)
        return handle
    }
}

@MainActor
private final class SharedAdmissionOperation<Value: Sendable> { var result: Result<Value, Error>? }

@MainActor
private final class SharedAdmissionFixture {
    let parent: URL
    let root: URL
    let recordings: URL
    let store: SQLiteMeetingStore
    let usage: MeetingUsageRegistry
    let preparation: SharedAdmissionPreparation
    let permission: SharedAdmissionPermission
    let hardware: SharedAdmissionHardware
    let activities: SharedAdmissionActivityBackend
    let owner: RecordingSessionOwner
    let deletion: MeetingDeletionCoordinator
    init(requiresStartup: Bool = false) throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-shared-admission-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: false)
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        let usage = MeetingUsageRegistry(requiresStartup: requiresStartup)
        let preparation = SharedAdmissionPreparation(store: store, recordings: recordings)
        let permission = SharedAdmissionPermission()
        let hardware = try SharedAdmissionHardware()
        let activities = SharedAdmissionActivityBackend()
        self.parent = parent; self.root = root; self.recordings = recordings; self.store = store
        self.usage = usage; self.preparation = preparation; self.permission = permission
        self.hardware = hardware; self.activities = activities
        owner = RecordingSessionOwner(permission: permission, hardware: hardware,
            activityBackend: activities, preparation: preparation, usageAdmission: usage)
        deletion = MeetingDeletionCoordinator(store: store, recordingsRoot: recordings, usage: usage)
    }

    func directory(_ id: UUID) -> URL { recordings.appendingPathComponent(id.uuidString, isDirectory: true) }
    func createDurableMeeting(_ id: UUID) async throws -> [String: Data] {
        try await store.createMeeting(MeetingRecord(id: id, title: "Original owned admission fixture",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recording))
        let writer = try SegmentCAFWriter(directory: directory(id), sessionID: id, maximumSegmentFrames: 64)
        try writer.append(sharedAdmissionSignal(format: hardware.format))
        let manifest = try writer.finish()
        XCTAssertEqual(manifest.totalFrames, 64)
        let paths = manifest.segments.map(\.relativePath) + ["capture-manifest.json"]
        return try Dictionary(uniqueKeysWithValues: paths.map { ($0, try Data(contentsOf: directory(id).appendingPathComponent($0))) })
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        preparation.prepareLatch?.release()
        preparation.finishLatch?.release()
        permission.latch?.release()
        let probe = SharedAdmissionOperation<Void>()
        let stopping = Task { @MainActor in await owner.stop(); probe.result = .success(()) }
        guard await admissionEventually({ probe.result != nil }) else {
            stopping.cancel()
            XCTFail("Owner cleanup did not settle; retain the generated fixture", file: file, line: line); return
        }
        await stopping.value
        let state = await owner.snapshot()
        guard !state.cleanupPending, !hardware.active, !hardware.running, hardware.tap == nil,
              activities.handles.allSatisfy({ $0.state == .ended || $0.state == .dismissed }) else {
            XCTFail("Owner resources remain live; retain the fixture", file: file, line: line); return
        }
        do { try await store.close() }
        catch { XCTFail("Real SQLite fixture could not close", file: file, line: line); return }
        guard root.lastPathComponent.hasPrefix("localminutes-shared-admission-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath() == parent,
              root.resolvingSymlinksInPath() == root else {
            XCTFail("Refuse cleanup outside the generated root", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned fixture cleanup failed", file: file, line: line) }
    }
}

@MainActor
final class SharedMeetingAdmissionTests: XCTestCase {
    private func withFixture(requiresStartup: Bool = false,
        _ body: @MainActor (SharedAdmissionFixture) async throws -> Void) async throws {
        let h = try SharedAdmissionFixture(requiresStartup: requiresStartup)
        do { try await body(h) }
        catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    private func complete<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let result = SharedAdmissionOperation<Value>()
        let task = Task { @MainActor in
            do { result.result = .success(try await operation()) }
            catch { result.result = .failure(error) }
        }
        guard await admissionEventually({ result.result != nil }) else {
            task.cancel(); XCTFail("Shared admission operation exceeded its bounded deadline")
            throw SharedAdmissionTestError.timedOut
        }
        await task.value
        return try XCTUnwrap(result.result).get()
    }

    private func assertDeletionBlocked(_ h: SharedAdmissionFixture, id: UUID,
        original: [String: Data]) async throws {
        do {
            try await h.deletion.delete(meetingID: id)
            XCTFail("The real shared owner reservation must reject deletion before any mutation")
        } catch { XCTAssertEqual(error as? MeetingDeletionError, .meetingInUse) }
        let row = try await h.store.meeting(id: id)
        XCTAssertNotNil(row)
        XCTAssertTrue(FileManager.default.fileExists(atPath: h.directory(id).path))
        for (name, bytes) in original {
            XCTAssertEqual(try? Data(contentsOf: h.directory(id).appendingPathComponent(name)), bytes)
        }
    }

    func testOwnerReservationBlocksRealDeletionBeforeHeldPreparation() async throws {
        try await withFixture { h in
            let id = UUID()
            let original = try await h.createDurableMeeting(id)
            let preparation = SharedAdmissionLatch()
            h.preparation.prepareLatch = preparation
            let starting = Task { await h.owner.start(sessionID: id) }
            defer { starting.cancel(); preparation.release() }
            let held = await admissionEventually { preparation.isWaiting }
            XCTAssertTrue(held)
            let state = await h.owner.snapshot()
            XCTAssertEqual(state.phase, .preparing)
            XCTAssertEqual(state.sessionID, id)
            XCTAssertEqual(h.permission.requests, 0)
            XCTAssertEqual(h.hardware.activations, 0)
            try await self.assertDeletionBlocked(h, id: id, original: original)
            starting.cancel()
            preparation.release()
            try await self.complete { await starting.value }
            try await self.complete { await h.owner.stop() }
            try await h.deletion.delete(meetingID: id)
            let deleted = try await h.store.meeting(id: id)
            XCTAssertNil(deleted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory(id).path))
        }
    }

    func testCancelledOwnerRetainsUsageThroughHeldTranscriptCleanupBeforeDeletion() async throws {
        try await withFixture { h in
            let id = UUID()
            let original = try await h.createDurableMeeting(id)
            let permission = SharedAdmissionLatch()
            let finishing = SharedAdmissionLatch()
            h.permission.latch = permission
            h.preparation.finishLatch = finishing
            let starting = Task { await h.owner.start(sessionID: id) }
            defer { starting.cancel(); permission.release(); finishing.release() }
            let heldPermission = await admissionEventually { permission.isWaiting }
            XCTAssertTrue(heldPermission)
            XCTAssertEqual(h.activities.handles.count, 1)
            starting.cancel()
            permission.release()
            let heldFinish = await admissionEventually { finishing.isWaiting }
            XCTAssertTrue(heldFinish, "Cancellation must enter the real owner's transcript cleanup barrier")
            let pending = await h.owner.snapshot()
            XCTAssertTrue(pending.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertEqual(h.hardware.activations, 0)
            try await self.assertDeletionBlocked(h, id: id, original: original)
            finishing.release()
            try await self.complete { await starting.value }
            try await self.complete { await h.owner.stop() }
            let settled = await h.owner.snapshot()
            XCTAssertFalse(settled.cleanupPending)
            XCTAssertNil(h.owner.completedManifest)
            XCTAssertTrue(h.activities.handles.allSatisfy { $0.state == .ended })
            try await h.deletion.delete(meetingID: id)
            let deleted = try await h.store.meeting(id: id)
            XCTAssertNil(deleted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory(id).path))
        }
    }

    func testStartupPendingAndFailureDenyOwnerBeforeAllPreparationAndOSUseUntilSuccess() async throws {
        try await withFixture(requiresStartup: true) { h in
            for failStartup in [false, true] {
                if failStartup { h.usage.completeStartup(success: false) }
                let deniedID = UUID()
                try await self.complete { await h.owner.start(sessionID: deniedID) }
                let denied = await h.owner.snapshot()
                XCTAssertNotEqual(denied.phase, .preparing)
                XCTAssertNotEqual(denied.phase, .recording)
                XCTAssertTrue(h.preparation.requests.isEmpty)
                XCTAssertEqual(h.permission.requests, 0)
                XCTAssertTrue(h.activities.handles.isEmpty)
                XCTAssertEqual(h.hardware.activations, 0)
                let row = try await h.store.meeting(id: deniedID)
                XCTAssertNil(row)
                XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory(deniedID).path))
                try await self.complete { await h.owner.stop() }
            }
            h.usage.completeStartup(success: true)
            let acceptedID = UUID()
            try await self.complete { await h.owner.start(sessionID: acceptedID) }
            XCTAssertEqual(h.preparation.requests, [acceptedID])
            XCTAssertEqual(h.permission.requests, 1)
            XCTAssertEqual(h.activities.handles.count, 1)
            XCTAssertEqual(h.hardware.activations, 1)
            try h.hardware.emit()
            let recording = await admissionEventually { await h.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            try await self.complete { await h.owner.stop() }
            let manifest = try XCTUnwrap(h.owner.completedManifest)
            XCTAssertEqual(manifest.sessionID, acceptedID)
            XCTAssertEqual(manifest.totalFrames, 64)
            let checkpoint = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: h.directory(acceptedID).appendingPathComponent("capture-manifest.json")))
            XCTAssertEqual(checkpoint, manifest)
            let caf = try XCTUnwrap(manifest.segments.first)
            XCTAssertEqual(try AVAudioFile(forReading: h.directory(acceptedID).appendingPathComponent(caf.relativePath)).length, 64)
        }
    }

    func testExactUsageTokenRejectsStaleReleaseAfterReplacement() async throws {
        try await withFixture { h in
            let id = UUID()
            let original = try await h.createDurableMeeting(id)
            guard let first = h.usage.acquireRecordingUsage(meetingID: id) else {
                return XCTFail("The registry adapter must issue an actual shared recording token")
            }
            XCTAssertNil(h.usage.acquireRecordingUsage(meetingID: id))
            h.usage.releaseRecordingUsage(meetingID: UUID(), token: first)
            try await self.assertDeletionBlocked(h, id: id, original: original)
            h.usage.releaseRecordingUsage(meetingID: id, token: first)
            guard let replacement = h.usage.acquireRecordingUsage(meetingID: id) else {
                return XCTFail("Exact release must permit a later independent reservation")
            }
            XCTAssertNotEqual(first, replacement)
            h.usage.releaseRecordingUsage(meetingID: id, token: first)
            h.usage.releaseRecordingUsage(meetingID: id, token: UUID())
            try await self.assertDeletionBlocked(h, id: id, original: original)
            h.usage.releaseRecordingUsage(meetingID: id, token: replacement)
            try await h.deletion.delete(meetingID: id)
            let deleted = try await h.store.meeting(id: id)
            XCTAssertNil(deleted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.directory(id).path))
        }
    }
}
