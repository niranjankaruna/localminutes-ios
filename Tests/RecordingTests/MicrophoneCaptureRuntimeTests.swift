import AVFoundation
import AudioToolbox
import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesRecording

// UNCOMPILED TEST-FIRST DRAFT. Only permission and microphone hardware are
// doubles. Queue ownership, native conversion, CAF files and manifests are real.
private enum RuntimeTestError: Error {
    case hardwareFailure, timedOut, unsafeFixture, unexpectedAudio
}

@MainActor
private final class RuntimeProbe {
    var events: [CaptureRuntimeEvent] = []
    var trace: [String] = []
    var operationFinished = false

    func record(_ event: CaptureRuntimeEvent) {
        events.append(event)
        if case .stopped = event { trace.append("stopped") }
    }

    func stoppedCount(_ id: UUID) -> Int {
        events.filter {
            if case .stopped(let sessionID, _) = $0 { return sessionID == id }
            return false
        }.count
    }

    func successfulManifest(_ id: UUID) -> AudioCaptureManifest? {
        for event in events {
            if case .stopped(let sessionID, let manifest) = event,
               sessionID == id, let manifest {
                return manifest
            }
        }
        return nil
    }
}

@MainActor
private final class RuntimePermission: CapturePermissionSource {
    var requests = 0
    private let immediateResult: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?
    var isPending: Bool { continuation != nil }

    init(result: Bool? = true) { immediateResult = result }

    func requestRecordPermission() async -> Bool {
        requests += 1
        if let immediateResult { return immediateResult }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ result: Bool) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}

// Only this immutable test box crosses to the synthetic callback Dispatch queue.
// Its AV objects are constructed on MainActor, then accessed by exactly one
// callback at a time. They never escape the synchronous handler into a Task.
private final class RuntimeCallbackFixture: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime
    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        self.buffer = buffer
        self.time = time
    }
}

@MainActor
private final class RuntimeHardware: CaptureHardware {
    let probe: RuntimeProbe
    var format: AVAudioFormat
    var failActivation = false
    var failStart = false
    var sessionActive = false
    var engineRunning = false
    var readFormatWhileActive = false
    private(set) var currentTap: CaptureTapHandler?
    private(set) var retainedTaps: [CaptureTapHandler] = []

    init(probe: RuntimeProbe, format: AVAudioFormat) {
        self.probe = probe
        self.format = format
    }

    func activateSession() throws {
        probe.trace.append("activate")
        if failActivation { throw RuntimeTestError.hardwareFailure }
        sessionActive = true
    }

    func inputFormat() throws -> AVAudioFormat {
        probe.trace.append("format")
        readFormatWhileActive = sessionActive
        return format
    }

    func installTap(_ handler: @escaping CaptureTapHandler) throws {
        probe.trace.append("install")
        currentTap = handler
        retainedTaps.append(handler)
    }

    func startEngine() throws {
        probe.trace.append("start")
        if failStart { throw RuntimeTestError.hardwareFailure }
        engineRunning = true
    }

    func stopEngine() {
        probe.trace.append("stop")
        engineRunning = false
    }

    func removeTap() {
        probe.trace.append("remove")
        currentTap = nil
    }

    func deactivateSession() throws {
        probe.trace.append("deactivate")
        sessionActive = false
    }

    func emit(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) throws {
        let tap = try XCTUnwrap(currentTap, "Runtime must install an actual callback")
        tap(buffer, time)
    }

    func delivery(
        _ buffer: AVAudioPCMBuffer, time: AVAudioTime
    ) throws -> @Sendable () -> Void {
        let tap = try XCTUnwrap(currentTap, "Runtime must install an actual callback")
        let fixture = RuntimeCallbackFixture(buffer: buffer, time: time)
        return { tap(fixture.buffer, fixture.time) }
    }
}

@MainActor
private final class RuntimeHarness {
    let id = UUID()
    let root: URL
    let directory: URL
    let permission: RuntimePermission
    let hardware: RuntimeHardware
    let probe: RuntimeProbe
    let runtime: MicrophoneCaptureRuntime
    private let parent: URL

    init(
        permissionResult: Bool? = true,
        rate: Double = 16_000,
        channels: AVAudioChannelCount = 1,
        configuration: CaptureRuntimeTestConfiguration? = nil,
        afterAdmission: (@Sendable () -> Void)? = nil
    ) throws {
        let fixtureParent = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath().standardizedFileURL
        let fixtureRoot = fixtureParent.appendingPathComponent("localminutes-runtime-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: false)
        let permissionSource = RuntimePermission(result: permissionResult)
        let eventProbe = RuntimeProbe()
        let hardwareBoundary = RuntimeHardware(
            probe: eventProbe,
            format: try XCTUnwrap(AVAudioFormat(
                standardFormatWithSampleRate: rate, channels: channels
            ))
        )
        let captureRuntime: MicrophoneCaptureRuntime
        if let configuration {
            captureRuntime = MicrophoneCaptureRuntime(
                permission: permissionSource, hardware: hardwareBoundary,
                onEvent: { eventProbe.record($0) }, configuration: configuration,
                afterAdmission: afterAdmission
            )
        } else {
            precondition(afterAdmission == nil, "Hooks require the internal test initializer")
            captureRuntime = MicrophoneCaptureRuntime(
                permission: permissionSource, hardware: hardwareBoundary,
                onEvent: { eventProbe.record($0) }
            )
        }
        parent = fixtureParent
        root = fixtureRoot
        directory = fixtureRoot.appendingPathComponent("meeting")
        permission = permissionSource
        probe = eventProbe
        hardware = hardwareBoundary
        runtime = captureRuntime
    }

    func replaceEmptyMeetingDirectoryWithFile() throws {
        guard directory.deletingLastPathComponent().resolvingSymlinksInPath().path == root.path,
              root.deletingLastPathComponent().resolvingSymlinksInPath().path == parent.path,
              directory.resolvingSymlinksInPath().path == directory.path,
              try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            XCTFail("Fault fixture must replace only this test's empty owned meeting directory")
            throw RuntimeTestError.unsafeFixture
        }
        try FileManager.default.removeItem(at: directory)
        try Data("synthetic filesystem fault".utf8).write(to: directory)
    }

    func cleanupIfQuiescent(file: StaticString = #filePath, line: UInt = #line) {
        permission.resolve(false)
        let snapshot = runtime.snapshot()
        guard snapshot.activeSessionID == nil, !snapshot.cleanupPending else {
            XCTFail("Runtime remains active; retain its owned synthetic fixture", file: file, line: line)
            return
        }
        guard root.isFileURL, root.lastPathComponent.hasPrefix("localminutes-runtime-test-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath().path == parent.path,
              root.resolvingSymlinksInPath().path == root.path else {
            XCTFail("Refuse cleanup outside the generated test root", file: file, line: line)
            return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned fixture cleanup failed: \(error)", file: file, line: line) }
    }
}

private final class RuntimeCallbackPause: Sendable {
    let entered = Atomic<Bool>(false)
    let completed = Atomic<Bool>(false)
    let timedOut = Atomic<Bool>(false)
    let admissionCount = Atomic<Int>(0)
    let release = DispatchSemaphore(value: 0)

    func afterAdmission() {
        _ = admissionCount.wrappingAdd(1, ordering: .relaxed)
        entered.store(true, ordering: .releasing)
        // Deliberately blocking TEST HOOK. The public production initializer
        // always supplies nil. One deadline, never an unbounded callback wait.
        if release.wait(timeout: .now() + .seconds(2)) != .success {
            timedOut.store(true, ordering: .releasing)
        }
    }
}

@MainActor
final class MicrophoneCaptureRuntimeTests: XCTestCase {
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ predicate: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !predicate() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    private func complete(
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        let completion = RuntimeProbe()
        let task = Task {
            await operation()
            completion.operationFinished = true
        }
        guard await waitUntil({ completion.operationFinished }) else {
            task.cancel()
            XCTFail("\(label) exceeded its bounded test deadline", file: file, line: line)
            throw RuntimeTestError.timedOut
        }
        await task.value
    }

    private func start(_ h: RuntimeHarness) async throws {
        try await complete("start") {
            await h.runtime.start(sessionID: h.id, directory: h.directory)
        }
    }

    private func stop(_ h: RuntimeHarness, id: UUID? = nil) async throws {
        let sessionID = id ?? h.id
        try await complete("stop") { await h.runtime.stop(sessionID: sessionID) }
    }

    private func signal(
        rate: Double = 16_000,
        channels: AVAudioChannelCount = 1,
        frames: AVAudioFrameCount = 64,
        value: (Int, Int) -> Float = { _, _ in 0.25 }
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: rate, channels: channels
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let planes = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) { planes[channel][frame] = value(frame, channel) }
        }
        return buffer
    }

    private func decodedSamples(
        _ manifest: AudioCaptureManifest, directory: URL
    ) throws -> [Float] {
        var samples: [Float] = []
        XCTAssertFalse(manifest.segments.isEmpty, "Real accepted audio must produce a CAF segment")
        for segment in manifest.segments {
            guard segment.relativePath == URL(fileURLWithPath: segment.relativePath).lastPathComponent,
                  segment.relativePath.hasSuffix(".caf") else {
                throw RuntimeTestError.unsafeFixture
            }
            let file = try AVAudioFile(
                forReading: directory.appendingPathComponent(segment.relativePath)
            )
            XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(
                (file.fileFormat.settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue, 16
            )
            XCTAssertEqual(file.length, segment.frameCount)
            guard file.length > 0, file.length <= 16_000 else {
                throw RuntimeTestError.unexpectedAudio
            }
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
            ))
            try file.read(into: buffer)
            let plane = try XCTUnwrap(buffer.floatChannelData?[0])
            samples += Array(UnsafeBufferPointer(start: plane, count: Int(buffer.frameLength)))
        }
        XCTAssertEqual(Int64(samples.count), manifest.totalFrames)
        let saved = try JSONDecoder().decode(
            AudioCaptureManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json"))
        )
        XCTAssertEqual(saved, manifest, "The stopped event must describe the durable real checkpoint")
        return samples
    }

    func testDeniedPermissionNeverActivatesHardwareOrReportsReadiness() async throws {
        let h = try RuntimeHarness(permissionResult: false)
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        XCTAssertEqual(h.permission.requests, 1)
        XCTAssertTrue(h.hardware.probe.trace.isEmpty ||
            h.hardware.probe.trace == ["stopped"])
        XCTAssertTrue(h.probe.events.contains(.failed(h.id, .microphoneDenied)))
        XCTAssertFalse(h.probe.events.contains(.sessionActivated(h.id)))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.runtime.snapshot().failure, .microphoneDenied)
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
        XCTAssertNil(h.probe.successfulManifest(h.id))
    }

    func testStopDuringPermissionWaitRejectsTheLateGrant() async throws {
        let h = try RuntimeHarness(permissionResult: nil)
        let request = Task {
            await h.runtime.start(sessionID: h.id, directory: h.directory)
            h.probe.operationFinished = true
        }
        defer {
            h.permission.resolve(false)
            request.cancel()
            h.cleanupIfQuiescent()
        }
        let pending = await waitUntil { h.permission.isPending }
        XCTAssertTrue(pending, "The runtime must actually request permission")
        try await stop(h)
        h.permission.resolve(true)
        let returned = await waitUntil { h.probe.operationFinished }
        XCTAssertTrue(returned)
        if returned { await request.value }
        XCTAssertTrue(h.probe.events.contains(.cancelled(h.id)))
        XCTAssertFalse(h.probe.trace.contains("activate"))
        XCTAssertFalse(h.probe.trace.contains("start"))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
        XCTAssertNil(h.runtime.snapshot().activeSessionID)
    }

    func testCancelledPermissionTaskCannotStartHardwareAfterGrant() async throws {
        let h = try RuntimeHarness(permissionResult: nil)
        let request = Task {
            await h.runtime.start(sessionID: h.id, directory: h.directory)
            h.probe.operationFinished = true
        }
        defer {
            h.permission.resolve(false)
            request.cancel()
            h.cleanupIfQuiescent()
        }
        let pending = await waitUntil { h.permission.isPending }
        XCTAssertTrue(pending)
        request.cancel()
        h.permission.resolve(true)
        let returned = await waitUntil { h.probe.operationFinished }
        XCTAssertTrue(returned)
        if returned { await request.value }
        XCTAssertTrue(h.probe.events.contains(.cancelled(h.id)))
        XCTAssertFalse(h.probe.trace.contains("activate"))
        XCTAssertFalse(h.probe.trace.contains("start"))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
    }

    func testActualFormatIsReadAfterActivationAndBeforeTapAndStart() async throws {
        let h = try RuntimeHarness(rate: 48_000, channels: 2)
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        XCTAssertEqual(Array(h.probe.trace.prefix(4)), ["activate", "format", "install", "start"])
        XCTAssertTrue(h.hardware.readFormatWhileActive)
        XCTAssertEqual(h.runtime.snapshot().activeSessionID, h.id)
        XCTAssertTrue(h.runtime.snapshot().audioSessionActive)
        XCTAssertFalse(h.runtime.snapshot().firstBufferAccepted)
        XCTAssertTrue(h.probe.events.contains(.sessionActivated(h.id)))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        try await stop(h)
        XCTAssertFalse(h.hardware.sessionActive)
        XCTAssertFalse(h.hardware.engineRunning)
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
        let deactivation = try XCTUnwrap(h.probe.trace.firstIndex(of: "deactivate"))
        let stopped = try XCTUnwrap(h.probe.trace.firstIndex(of: "stopped"))
        XCTAssertLessThan(deactivation, stopped)
    }

    func testFirstBufferSignalRequiresQueueAcceptanceAndIsEmittedOnlyOnce() async throws {
        let h = try RuntimeHarness()
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        XCTAssertFalse(h.runtime.snapshot().firstBufferAccepted)
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        let buffer = try signal()
        try h.hardware.emit(buffer, time: AVAudioTime(sampleTime: 90_000, atRate: 16_000))
        let accepted = await waitUntil { h.probe.events.contains(.firstBufferAccepted(h.id)) }
        XCTAssertTrue(accepted)
        XCTAssertTrue(h.runtime.snapshot().firstBufferAccepted)
        try h.hardware.emit(buffer, time: AVAudioTime(sampleTime: 90_064, atRate: 16_000))
        try await stop(h)
        XCTAssertEqual(h.probe.events.filter { $0 == .firstBufferAccepted(h.id) }.count, 1)
        let manifest = try XCTUnwrap(h.probe.successfulManifest(h.id))
        XCTAssertEqual(manifest.totalFrames, 128)
    }

    func testOversizedBufferCannotFabricateFirstBufferReadiness() async throws {
        let h = try RuntimeHarness(configuration: CaptureRuntimeTestConfiguration(
            queueCapacity: 2, maxFramesPerBuffer: 4
        ))
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        try h.hardware.emit(
            signal(frames: 5), time: AVAudioTime(sampleTime: 700, atRate: 16_000)
        )
        let failed = await waitUntil { h.probe.events.contains(.failed(h.id, .queueLoss)) }
        XCTAssertTrue(failed, "An invalid queue input needs an explicit stop/failure")
        try await stop(h)
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.runtime.snapshot().failure, .queueLoss)
        XCTAssertNil(h.probe.successfulManifest(h.id))
    }

    func testInvalidSampleTimestampIsExplicitAndDoesNotReachTheQueue() async throws {
        let h = try RuntimeHarness()
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        let hostOnly = AVAudioTime(hostTime: 1)
        XCTAssertFalse(hostOnly.isSampleTimeValid)
        try h.hardware.emit(signal(), time: hostOnly)
        let failed = await waitUntil {
            h.probe.events.contains(.failed(h.id, .invalidTimestamp))
        }
        XCTAssertTrue(failed)
        try await stop(h)
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.runtime.snapshot().failure, .invalidTimestamp)
        XCTAssertNil(h.probe.successfulManifest(h.id))
    }

    func testDuplicateAndStaleRequestsAndRetainedOldTapDoNotReplaceTheEpoch() async throws {
        let h = try RuntimeHarness()
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        let oldDelivery = try h.hardware.delivery(
            signal(), time: AVAudioTime(sampleTime: 123, atRate: 16_000)
        )
        let nextID = UUID()
        let nextDirectory = h.root.appendingPathComponent("replacement")
        try await start(h)
        try await complete("competing start") {
            await h.runtime.start(sessionID: nextID, directory: nextDirectory)
        }
        try await stop(h, id: nextID)
        XCTAssertEqual(h.permission.requests, 1)
        XCTAssertEqual(h.probe.trace.filter { $0 == "activate" }.count, 1)
        XCTAssertEqual(h.probe.trace.filter { $0 == "start" }.count, 1)
        XCTAssertFalse(h.probe.trace.contains("stop"), "Stale stop cannot stop the current epoch")
        try await stop(h)
        try await stop(h)
        XCTAssertEqual(h.probe.trace.filter { $0 == "stop" }.count, 1)
        XCTAssertEqual(h.probe.trace.filter { $0 == "remove" }.count, 1)
        XCTAssertEqual(h.probe.trace.filter { $0 == "deactivate" }.count, 1)
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)

        try await complete("replacement start") {
            await h.runtime.start(sessionID: nextID, directory: nextDirectory)
        }
        oldDelivery()
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(h.runtime.snapshot().firstBufferAccepted)
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(nextID)))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertEqual(h.probe.successfulManifest(h.id)?.totalFrames, 0)
        try h.hardware.emit(signal(), time: AVAudioTime(sampleTime: 1_000, atRate: 16_000))
        try await stop(h, id: nextID)
        XCTAssertEqual(h.probe.successfulManifest(nextID)?.totalFrames, 64)
        XCTAssertEqual(h.probe.stoppedCount(nextID), 1)
    }

    func testActivationAndEngineStartFailuresAreExplicitAndCleanedUp() async throws {
        for failActivation in [true, false] {
            let h = try RuntimeHarness()
            defer { h.cleanupIfQuiescent() }
            h.hardware.failActivation = failActivation
            h.hardware.failStart = !failActivation
            try await start(h)
            let failure: CaptureRuntimeFailure = failActivation ? .sessionUnavailable : .captureUnavailable
            XCTAssertTrue(h.probe.events.contains(.failed(h.id, failure)))
            XCTAssertEqual(h.runtime.snapshot().failure, failure)
            XCTAssertNil(h.runtime.snapshot().activeSessionID)
            XCTAssertFalse(h.runtime.snapshot().audioSessionActive)
            XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
            XCTAssertNil(h.probe.successfulManifest(h.id))
            XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
            if failActivation {
                XCTAssertFalse(h.probe.trace.contains("install"))
                XCTAssertFalse(h.probe.trace.contains("start"))
            } else {
                XCTAssertTrue(h.probe.trace.contains("remove"))
                XCTAssertTrue(h.probe.trace.contains("deactivate"))
            }
        }
    }

    func testUnsupportedNativeInputFormatIsPreparationRejection() async throws {
        let h = try RuntimeHarness()
        defer { h.cleanupIfQuiescent() }
        h.hardware.format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: false
        ))
        try await start(h)
        XCTAssertTrue(h.probe.events.contains(.failed(h.id, .preparationRejected)))
        XCTAssertEqual(h.runtime.snapshot().failure, .preparationRejected)
        XCTAssertFalse(h.probe.trace.contains("start"))
        XCTAssertTrue(h.probe.trace.contains("deactivate"))
        XCTAssertFalse(h.probe.events.contains(.firstBufferAccepted(h.id)))
        XCTAssertNil(h.probe.successfulManifest(h.id))
        // This is not a simulated midstream conversion error. The separate
        // PCMStreamConverter native-error regression owns that boundary.
    }

    func testActualWriteFailureCannotEmitASuccessfulManifest() async throws {
        let h = try RuntimeHarness()
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        try h.replaceEmptyMeetingDirectoryWithFile()
        try h.hardware.emit(signal(), time: AVAudioTime(sampleTime: 500, atRate: 16_000))
        let failed = await waitUntil { h.probe.events.contains(.failed(h.id, .writeFailed)) }
        XCTAssertTrue(failed)
        try await stop(h)
        XCTAssertEqual(h.runtime.snapshot().failure, .writeFailed)
        XCTAssertNil(h.probe.successfulManifest(h.id))
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
        XCTAssertFalse(h.runtime.snapshot().audioSessionActive)
    }

    func testActualQueueResamplingAndSixteenBitCAFDecodePreserveTheSignal() async throws {
        let h = try RuntimeHarness(rate: 48_000, channels: 2)
        defer { h.cleanupIfQuiescent() }
        try await start(h)
        for index in 0..<4 {
            let buffer = try signal(rate: 48_000, channels: 2, frames: 480) {
                _, channel in channel == 0 ? 0.25 : 0.5
            }
            try h.hardware.emit(
                buffer, time: AVAudioTime(sampleTime: Int64(40_000 + index * 480), atRate: 48_000)
            )
            // Overwrite borrowed input immediately. The runtime must already
            // own its copy; a worker cannot retain this AVAudioPCMBuffer.
            for channel in 0..<2 {
                buffer.floatChannelData?[channel].update(repeating: -0.75, count: 480)
            }
        }
        try await stop(h)
        let manifest = try XCTUnwrap(h.probe.successfulManifest(h.id))
        XCTAssertEqual(manifest.sessionID, h.id)
        XCTAssertLessThanOrEqual(abs(manifest.totalFrames - 640), 2)
        let decoded = try decodedSamples(manifest, directory: h.directory)
        guard decoded.count > 128 else {
            XCTFail("Native resampling must produce real audio, not an empty manifest")
            return
        }
        for sample in decoded.dropFirst(64).dropLast(64) {
            XCTAssertEqual(sample, 0.375, accuracy: 0.001)
        }
        XCTAssertFalse(h.probe.events.contains(.failed(h.id, .conversionFailed)))
        XCTAssertFalse(h.probe.events.contains(.failed(h.id, .writeFailed)))
    }

    func testStopWaitsForAnAdmittedCallbackThenDrainsBeforeDeactivationAndAcknowledgement() async throws {
        let pause = RuntimeCallbackPause()
        let h = try RuntimeHarness(
            configuration: CaptureRuntimeTestConfiguration(),
            afterAdmission: { pause.afterAdmission() }
        )
        defer {
            pause.release.signal()
            h.cleanupIfQuiescent()
        }
        try await start(h)
        let delivery = try h.hardware.delivery(
            signal(), time: AVAudioTime(sampleTime: 9_000, atRate: 16_000)
        )
        let lateDelivery = try h.hardware.delivery(
            signal(), time: AVAudioTime(sampleTime: 9_064, atRate: 16_000)
        )
        DispatchQueue(label: "LocalMinutes.tests.runtime.callback").async {
            delivery()
            pause.completed.store(true, ordering: .releasing)
        }
        let entered = await waitUntil { pause.entered.load(ordering: .acquiring) }
        XCTAssertTrue(entered, "The hook must run after the actual admission claim")
        let stopping = Task {
            await h.runtime.stop(sessionID: h.id)
            h.probe.operationFinished = true
        }
        defer { stopping.cancel() }
        let closed = await waitUntil {
            h.probe.trace.contains("remove") && h.runtime.snapshot().cleanupPending
        }
        XCTAssertTrue(closed)
        XCTAssertFalse(h.probe.operationFinished)
        XCTAssertEqual(h.probe.stoppedCount(h.id), 0)
        XCTAssertFalse(h.probe.trace.contains("deactivate"))
        lateDelivery()
        XCTAssertEqual(pause.admissionCount.load(ordering: .acquiring), 1,
                       "Closing must reject a late callback before it reaches the queue/hook")
        pause.release.signal()
        let callbackReturned = await waitUntil { pause.completed.load(ordering: .acquiring) }
        let stopReturned = await waitUntil { h.probe.operationFinished }
        XCTAssertTrue(callbackReturned)
        XCTAssertTrue(stopReturned)
        if stopReturned { await stopping.value }
        XCTAssertFalse(pause.timedOut.load(ordering: .acquiring))
        let manifest = try XCTUnwrap(h.probe.successfulManifest(h.id))
        XCTAssertEqual(manifest.totalFrames, 64,
                       "queue.finish must follow the in-flight enqueue, not merely stop/removeTap")
        let decoded = try decodedSamples(manifest, directory: h.directory)
        XCTAssertEqual(decoded.count, 64)
        for sample in decoded { XCTAssertEqual(sample, 0.25, accuracy: 0.0002) }
        let deactivation = try XCTUnwrap(h.probe.trace.firstIndex(of: "deactivate"))
        let stopped = try XCTUnwrap(h.probe.trace.firstIndex(of: "stopped"))
        XCTAssertLessThan(deactivation, stopped)
        XCTAssertEqual(h.probe.stoppedCount(h.id), 1)
        XCTAssertNil(h.runtime.snapshot().activeSessionID)
        XCTAssertFalse(h.runtime.snapshot().cleanupPending)
    }
}
