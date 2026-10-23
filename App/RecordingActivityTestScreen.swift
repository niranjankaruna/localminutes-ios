#if DEBUG
import Foundation
import SwiftUI

/// Non-sensitive view fixture for Simulator UI tests only. This never prepares
/// a model, starts capture or creates an Activity. Excluded from Release builds.
@MainActor
struct RecordingActivityTestScreen: View {
    let application: RecordingApplication
    let finished: Bool
    private let sessionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                        0, 0, 0, 0, 0, 0, 0, 1))

    private var state: RecordingActivityAttributes.ContentState {
        if finished {
            return .init(status: "finished", recordingStartedAt: Date(timeIntervalSince1970: 1_000),
                         recordingEndedAt: Date(timeIntervalSince1970: 1_065))
        }
        return .init(status: "recording", recordingStartedAt: Date.now.addingTimeInterval(-65))
    }

    var body: some View {
        VStack(spacing: 24) {
            RecordingActivityControls(meetingID: sessionID, state: state)
            if let outcome = application.lastOutcome {
                Text(String(localized: RecordingIntentReplies.message(for: outcome)))
                    .accessibilityIdentifier("recording.activity.outcome")
            }
        }
        .padding()
    }
}
#endif
