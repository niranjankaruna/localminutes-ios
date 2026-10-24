import AVFoundation
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import LocalMinutes

/// Hosted view-hierarchy/capture-lifetime evidence only. Posting the OS
/// boundary on an isolated center does not prove a physical task-switcher or
/// locked-screen snapshot. No screenshot or meeting content is exported.
@MainActor
final class NativeRootPrivacyTests: XCTestCase {
    func testOwningSceneNotificationsOpaqueCoverTheHostedRootAndRestoreAccessibility() async throws {
        let center = NotificationCenter()
        let privacy = RecordingPrivacyController(center: center)
        let root = RecordingPrivacyRoot(controller: privacy) {
            Text("Original synthetic private meeting text")
                .accessibilityIdentifier("privacy.test.privateText")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.red)
        }
        let hosted = try PrivacyHostedWindow(root: root)
        defer { hosted.close() }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(privacy.isObscured)
        XCTAssertFalse(hosted.contentView.accessibilityElementsHidden)

        center.post(name: UIScene.willDeactivateNotification, object: NSObject())
        XCTAssertFalse(privacy.isObscured, "A notification for another owner cannot replace this window")
        center.post(name: UIScene.willDeactivateNotification, object: hosted.scene)
        // UIKit snapshots immediately; no animation or async Task may postpone
        // the actual cover until after this notification returns.
        XCTAssertTrue(privacy.isObscured)
        assertOpaqueCover(hosted)
        XCTAssertTrue(hosted.contentView.accessibilityElementsHidden,
                      "Private underlying content must disappear from accessibility while obscured")
        center.post(name: UIScene.didEnterBackgroundNotification, object: hosted.scene)
        assertOpaqueCover(hosted)
        XCTAssertEqual(coverCount(in: hosted.window), 1, "Repeated inactive/background events must reuse one cover")
        center.post(name: UIScene.didActivateNotification, object: NSObject())
        XCTAssertTrue(privacy.isObscured, "An unrelated activation must not expose this scene")
        center.post(name: UIScene.didActivateNotification, object: hosted.scene)
        XCTAssertFalse(privacy.isObscured)
        XCTAssertNil(cover(in: hosted.window))
        XCTAssertFalse(hosted.contentView.accessibilityElementsHidden)
    }

    func testActualHomeRootPrivacyPreservesRunningOwnedCaptureAndRealCAFFlush() async throws {
        let harness = try PrivacyCaptureHarness()
        let center = NotificationCenter()
        let privacy = RecordingPrivacyController(center: center)
        let hosted = try PrivacyHostedWindow(root: LocalMinutesHomeView(application: harness.application, privacy: privacy))
        defer { hosted.close() }
        do {
            _ = try await harness.application.perform(.start(harness.id))
            try harness.hardware.emit(frames: 3_200)
            let recording = await eventually { await harness.owner.snapshot().phase == .recording }
            XCTAssertTrue(recording)
            let before = await harness.owner.snapshot()
            XCTAssertTrue(before.readiness.activityActive)
            XCTAssertTrue(before.readiness.audioSessionActive)
            XCTAssertTrue(before.readiness.firstBufferAccepted)
            try await Task.sleep(for: .milliseconds(30))
            center.post(name: UIScene.willDeactivateNotification, object: hosted.scene)
            center.post(name: UIScene.didEnterBackgroundNotification, object: hosted.scene)
            XCTAssertTrue(privacy.isObscured)
            assertOpaqueCover(hosted)
            XCTAssertTrue(hosted.contentView.accessibilityElementsHidden)
            let hidden = await harness.owner.snapshot()
            XCTAssertEqual(hidden.sessionID, harness.id); XCTAssertEqual(hidden.phase, .recording)
            XCTAssertFalse(hidden.cleanupPending)
            XCTAssertTrue(harness.hardware.running)
            XCTAssertEqual(harness.hardware.stopCalls, 0); XCTAssertEqual(harness.hardware.deactivateCalls, 0)
            try harness.hardware.emit(frames: 1_600)
            center.post(name: UIScene.didActivateNotification, object: hosted.scene)
            XCTAssertFalse(privacy.isObscured)
            XCTAssertFalse(hosted.contentView.accessibilityElementsHidden)
            let activeAgain = await harness.owner.snapshot()
            XCTAssertEqual(activeAgain.sessionID, harness.id); XCTAssertEqual(activeAgain.phase, .recording)
            await harness.owner.stop()
            let completed = await harness.owner.snapshot()
            XCTAssertEqual(completed.phase, .completed); XCTAssertFalse(completed.cleanupPending)
            let manifest = try XCTUnwrap(harness.owner.completedManifest)
            XCTAssertEqual(manifest.totalFrames, 4_800, "Audio accepted before and during cover must drain into the actual CAF")
            var decoded: Int64 = 0
            for segment in manifest.segments {
                let audio = try AVAudioFile(forReading: harness.preparation.directory.appendingPathComponent(segment.relativePath),
                                            commonFormat: .pcmFormatFloat32, interleaved: false)
                let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
                try audio.read(into: pcm)
                XCTAssertGreaterThan(pcm.frameLength, 0)
                let samples = try XCTUnwrap(pcm.floatChannelData?.pointee)
                XCTAssertEqual(samples[0], 0.25, accuracy: 0.001)
                decoded += Int64(pcm.frameLength)
            }
            XCTAssertEqual(decoded, manifest.totalFrames)
        } catch {
            await harness.owner.stop()
            try? harness.remove()
            throw error
        }
        try harness.remove()
    }

    private func assertOpaqueCover<Content: View>(_ hosted: PrivacyHostedWindow<Content>,
                                                file: StaticString = #filePath, line: UInt = #line) {
        guard let view = cover(in: hosted.window) else {
            return XCTFail("The actual owning window has no privacy cover", file: file, line: line)
        }
        XCTAssertFalse(view.isHidden, file: file, line: line)
        XCTAssertEqual(view.alpha, 1, file: file, line: line)
        XCTAssertTrue(view.isOpaque, file: file, line: line)
        XCTAssertEqual(view.backgroundColor?.cgColor.alpha, 1, file: file, line: line)
        XCTAssertTrue(view.convert(view.bounds, to: hosted.window).contains(hosted.window.bounds), file: file, line: line)
    }
    private func cover(in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == RecordingPrivacyController.coverAccessibilityIdentifier { return view }
        return view.subviews.lazy.compactMap { self.cover(in: $0) }.first
    }
    private func coverCount(in view: UIView) -> Int {
        (view.accessibilityIdentifier == RecordingPrivacyController.coverAccessibilityIdentifier ? 1 : 0)
            + view.subviews.reduce(0) { $0 + coverCount(in: $1) }
    }
    private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return false
    }
}

@MainActor
private final class PrivacyHostedWindow<Content: View> {
    let scene: UIWindowScene
    let window: UIWindow
    private let hosting: UIHostingController<Content>
    var contentView: UIView { hosting.view }
    init(root: Content) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                             "Hosted iOS app must supply an actual scene before privacy assertions")
        let window = UIWindow(windowScene: scene)
        let hosting = UIHostingController(rootView: root)
        self.scene = scene; self.window = window; self.hosting = hosting
        window.frame = scene.screen.bounds
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.loadViewIfNeeded()
        window.layoutIfNeeded(); hosting.view.layoutIfNeeded()
    }
    func close() { window.isHidden = true; window.rootViewController = nil }
}

@MainActor
private final class PrivacyCaptureHarness {
    let id = UUID()
    let root: URL
    let preparation: PrivacyPreparation
    let hardware: PrivacyCaptureHardware
    let owner: RecordingSessionOwner
    let application: RecordingApplication
    init() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-privacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let preparation = PrivacyPreparation(directory: root.appendingPathComponent("Audio", isDirectory: true))
        let hardware = PrivacyCaptureHardware()
        let owner = RecordingSessionOwner(permission: PrivacyPermission(), hardware: hardware,
            activityBackend: PrivacyActivityBackend(), preparation: preparation)
        self.root = root; self.preparation = preparation; self.hardware = hardware; self.owner = owner
        application = RecordingApplication(owner: owner, signalCenter: NotificationCenter())
    }
    func remove() throws {
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-privacy-"), root.resolvingSymlinksInPath() == root else {
            throw PrivacyFixtureError.invalidInput
        }
        try FileManager.default.removeItem(at: root)
    }
}

private enum PrivacyFixtureError: Error { case invalidInput }
@MainActor
private final class PrivacyPermission: CapturePermissionSource {
    func requestRecordPermission() async -> Bool { true }
}
@MainActor
private final class PrivacyPreparation: RecordingPreparationSource {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            return .ready(directory: directory)
        } catch { return .rejected(.writeFailed) }
    }
}
@MainActor
private final class PrivacyCaptureHardware: CaptureHardware {
    private var handler: CaptureTapHandler?
    private var cursor: Int64 = 0
    private(set) var running = false
    private(set) var stopCalls = 0
    private(set) var deactivateCalls = 0
    func activateSession() throws {}
    func inputFormat() throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    }
    func installTap(_ handler: @escaping CaptureTapHandler) throws { self.handler = handler }
    func startEngine() throws { running = true }
    func stopEngine() { running = false; stopCalls += 1 }
    func removeTap() { handler = nil }
    func deactivateSession() throws { deactivateCalls += 1 }
    func emit(frames: Int) throws {
        let callback = try XCTUnwrap(handler)
        let format = try inputFormat()
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        try XCTUnwrap(buffer.floatChannelData?.pointee).update(repeating: 0.25, count: frames)
        callback(buffer, AVAudioTime(sampleTime: cursor, atRate: 16_000))
        cursor += Int64(frames)
    }
}
@MainActor
private final class PrivacyActivityBackend: LiveActivityBackend {
    var areActivitiesEnabled: Bool { true }
    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle { PrivacyActivityHandle() }
}
@MainActor
private final class PrivacyActivityHandle: LiveActivityHandle {
    private(set) var state: LiveActivityResourceState = .active
    private var observer: LiveActivityStateObserver?
    func setStateObserver(_ observer: LiveActivityStateObserver?) { self.observer = observer }
    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome { .applied }
    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        state = .ended; observer?(.ended); return .applied
    }
}
