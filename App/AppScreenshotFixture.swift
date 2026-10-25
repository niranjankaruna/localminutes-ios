#if DEBUG && os(iOS)
import Foundation
import SwiftUI

/// Display inputs for screenshot capture, never microphone or inference output.
@MainActor
enum AppScreenshotFixture {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-screenshots")
    }

    static let meetingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    static var colorScheme: ColorScheme? {
        guard requested else { return nil }
        return ProcessInfo.processInfo.environment["LOCALMINUTES_UI_APPEARANCE"] == "dark" ? .dark : .light
    }

    static var recording: Bool {
        requested && ProcessInfo.processInfo.arguments.contains("--ui-screenshot-recording")
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
