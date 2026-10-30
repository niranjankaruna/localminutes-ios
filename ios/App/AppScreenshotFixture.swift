import SwiftUI
#if DEBUG && os(iOS)
import Foundation
import UIKit

/// Display inputs for screenshot capture, never microphone or inference output.
@MainActor
enum AppScreenshotFixture {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-screenshots")
    }

    static let meetingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let detailMeetingID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private(set) static var restoreBackupURL: URL?
    static var scene: AppScreenshotScene? {
        guard requested, let value = ProcessInfo.processInfo.environment["LOCALMINUTES_SCREENSHOT_SCENE"] else { return nil }
        return AppScreenshotScene(rawValue: value)
    }

    static func prepare(_ application: RecordingApplication) async throws {
        guard let scene, let services = application.services else { return }
        UIView.setAnimationsEnabled(false)
        await services.initialize()
        prepareModels(services.modelBrowser)
        if scene == .meetingsRestoreConfirmation { restoreBackupURL = try await application.exportLibraryBackup() }
        if scene == .modelsStorage {
            await services.modelBrowser.prepareStorageCheck(recordingOwner: application.owner)
        }
    }

    static func prepareModels(_ controller: ModelBrowserController) {
        guard let scene else { return }
        controller.purpose = scene.usesSummaryModels ? .summary : .speechRecognition
    }

    static func scroll(_ proxy: ScrollViewProxy) {
        guard let scene else { return }
        if !scene.anchor.isEmpty { proxy.scrollTo(scene.anchor, anchor: .top) }
    }

    static var colorScheme: ColorScheme? {
        guard requested else { return nil }
        return ProcessInfo.processInfo.environment["LOCALMINUTES_UI_APPEARANCE"] == "dark" ? .dark : .light
    }

    static var recording: Bool {
        scene?.isRecording == true
    }

    static var snapshot: RecordingSnapshot {
        switch scene {
        case .recordPreparing:
            return .init(phase: .preparing, sessionID: meetingID, readiness: .init(), failure: nil, cleanupPending: false)
        case .recordStopping:
            return .init(phase: .stopping, sessionID: meetingID, readiness: .init(), failure: nil, cleanupPending: true)
        case .recordMicrophoneDenied, .recordCaptureFailure, .recordStorageFull:
            return .init(phase: .failed, sessionID: meetingID, readiness: .init(),
                failure: scene == .recordMicrophoneDenied ? .microphoneDenied : scene == .recordStorageFull ? .storageFull : .captureUnavailable,
                cleanupPending: false)
        default: break
        }
        return .init(phase: .recording, sessionID: meetingID,
              readiness: .init(audioSessionActive: true, firstBufferAccepted: true, activityActive: true),
              failure: nil, cleanupPending: false)
    }

    static var progress: RecordingProgress {
        .init(elapsedSeconds: 125, backlogSeconds: scene == .recordCatchingUp ? 45 : 2.5,
              status: scene == .recordCatchingUp ? .lagging : .processing)
    }

    static var transcript: LiveTranscriptSnapshot {
        if scene == .recordListening { return .init(sessionID: meetingID, finalized: [], receivedSampleCount: 0) }
        return .init(sessionID: meetingID, finalized: [
            .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                  meetingID: meetingID, sequence: 0, startSample: 0, endSample: 80_000,
                  text: "We agreed to review the updated meeting experience on Friday.",
                  modelRevision: ParakeetCoreMLModel.manifest.revision)
        ], receivedSampleCount: 1_960_000)
    }

    enum TranscriptStream: String { case finalized, partial }
    static var transcriptStream: TranscriptStream? {
        guard scene == .recordTranscript,
              let value = ProcessInfo.processInfo.environment["LOCALMINUTES_UI_TRANSCRIPT_STREAM"] else { return nil }
        return TranscriptStream(rawValue: value)
    }

    /// Long display-only input for the actual recording scroll view. It never
    /// changes capture state, writes transcript rows or invokes speech inference.
    static func scrollingTranscript(finalCount: Int, partial: String = "") -> LiveTranscriptSnapshot {
        let count = min(25, max(0, finalCount))
        let detail = String(repeating: "We are reviewing the meeting notes and next steps. ", count: 4)
        let segments: [StoredTranscriptSegment] = (0..<count).map { index -> StoredTranscriptSegment in
            let identifier = String(format: "20000000-0000-0000-0000-%012d", index + 1)
            let start = Int64(index) * 80_000
            let end = Int64(index + 1) * 80_000
            let text = index == 24 ? "Newest finalized transcript segment." : "Transcript segment \(index + 1). " + detail
            return StoredTranscriptSegment(id: UUID(uuidString: identifier)!,
                meetingID: meetingID, sequence: index, startSample: start, endSample: end, text: text,
                modelRevision: ParakeetCoreMLModel.manifest.revision)
        }
        return .init(sessionID: meetingID, partial: partial, finalized: segments,
                     receivedSampleCount: Int64(segments.count) * 80_000)
    }

    static var permissions: RecordingPermissionsController? {
        guard let scene, [.recordPermissions, .recordPermissionsDenied, .recordPermissionsAllowed,
                          .recordActivitiesDisabled, .settingsPermissions].contains(scene) else { return nil }
        return RecordingPermissionsController(source: ScreenshotPermissionsSource(
            microphone: scene == .recordPermissionsDenied ? .denied :
                [.recordPermissionsAllowed, .recordActivitiesDisabled].contains(scene) ? .allowed : .notRequested,
            liveActivitiesEnabled: scene != .recordActivitiesDisabled))
    }
}

@MainActor
private final class ScreenshotPermissionsSource: RecordingPermissionsSource {
    let microphone: RecordingMicrophonePermission
    let liveActivitiesEnabled: Bool
    init(microphone: RecordingMicrophonePermission, liveActivitiesEnabled: Bool) {
        self.microphone = microphone; self.liveActivitiesEnabled = liveActivitiesEnabled
    }
    func requestMicrophone() async {}
}

/// The actual launch storyboard, hosted long enough to inspect its layout.
/// Receipts explicitly identify this as hostedLaunch, not an OS launch capture.
struct ScreenshotLaunchView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController()!
        controller.overrideUserInterfaceStyle = AppScreenshotFixture.colorScheme == .dark ? .dark : .light
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

/// A separate accessibility leaf keeps the readiness identifier off production
/// containers, where SwiftUI can propagate it to their controls and safe-area insets.
@MainActor
private struct ScreenshotReadinessMarker: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Screenshot readiness"
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = identifier
    }
}
#endif

@MainActor
extension View {
    @ViewBuilder
    func screenshotReady(_ ready: Bool) -> some View {
        #if DEBUG && os(iOS)
        if let scene = AppScreenshotFixture.scene {
            overlay(alignment: .topLeading) {
                ScreenshotReadinessMarker(identifier: "screenshot.\(ready ? "ready" : "loading").\(scene.rawValue)")
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func screenshotAnchor(_ name: String) -> some View {
        #if DEBUG && os(iOS)
        if AppScreenshotFixture.scene != nil { id(name) } else { self }
        #else
        self
        #endif
    }

    func screenshotScroll(_ proxy: ScrollViewProxy, ready: Bool) -> some View {
        onChange(of: ready, initial: true) { _, ready in
            #if DEBUG && os(iOS)
            if ready { AppScreenshotFixture.scroll(proxy) }
            #endif
        }
    }
}
