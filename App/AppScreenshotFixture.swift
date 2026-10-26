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
    static var scene: AppScreenshotScene? {
        guard requested, let value = ProcessInfo.processInfo.environment["LOCALMINUTES_SCREENSHOT_SCENE"] else { return nil }
        return AppScreenshotScene(rawValue: value)
    }

    static func prepare(_ application: RecordingApplication) async throws {
        guard let scene, let services = application.services else { return }
        UIView.setAnimationsEnabled(false)
        await services.initialize()
        prepareModels(services.modelBrowser)
        if scene == .modelsStorage {
            await services.modelBrowser.prepareStorageCheck(recordingOwner: application.owner)
        }
    }

    static func prepareModels(_ controller: ModelBrowserController) {
        guard let scene else { return }
        controller.purpose = scene.usesSummaryModels ? .summary : .speechRecognition
        if scene.usesRepository && scene != .modelsCard { controller.loadBundledParakeetV3() }
    }

    static func scroll(_ proxy: ScrollViewProxy) {
        guard let scene else { return }
        proxy.scrollTo(scene.anchor, anchor: .top)
    }

    static var colorScheme: ColorScheme? {
        guard requested else { return nil }
        return ProcessInfo.processInfo.environment["LOCALMINUTES_UI_APPEARANCE"] == "dark" ? .dark : .light
    }

    static var recording: Bool {
        scene?.isRecording == true
    }

    static var snapshot: RecordingSnapshot {
        .init(phase: .recording, sessionID: meetingID,
              readiness: .init(audioSessionActive: true, firstBufferAccepted: true, activityActive: true),
              failure: nil, cleanupPending: false)
    }

    static var progress: RecordingProgress {
        .init(elapsedSeconds: 125, backlogSeconds: 2.5, status: .processing)
    }

    static var transcript: LiveTranscriptSnapshot {
        .init(sessionID: meetingID, finalized: [
            .init(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                  meetingID: meetingID, sequence: 0, startSample: 0, endSample: 80_000,
                  text: "We agreed to review the updated meeting experience on Friday.",
                  modelRevision: ParakeetCoreMLModel.manifest.revision)
        ], receivedSampleCount: 1_960_000)
    }
}
#endif

@MainActor
extension View {
    @ViewBuilder
    func screenshotReady(_ ready: Bool) -> some View {
        #if DEBUG
        if let scene = AppScreenshotFixture.scene {
            accessibilityIdentifier("screenshot.\(ready ? "ready" : "loading").\(scene.rawValue)")
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func screenshotAnchor(_ name: String) -> some View {
        #if DEBUG
        if AppScreenshotFixture.scene != nil { id(name) } else { self }
        #else
        self
        #endif
    }

    func screenshotScroll(_ proxy: ScrollViewProxy, ready: Bool) -> some View {
        onChange(of: ready, initial: true) { _, ready in
            #if DEBUG
            if ready { AppScreenshotFixture.scroll(proxy) }
            #endif
        }
    }
}
