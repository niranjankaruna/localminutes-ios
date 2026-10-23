#if os(iOS)
import AppIntents
import Foundation
import SwiftUI

/// Shared by the real widget and app. It contains only generic status, dates and
/// an epoch-scoped intent value, never capture state or meeting/transcript text.
struct RecordingActivityControls: View {
    let meetingID: UUID
    let state: RecordingActivityAttributes.ContentState

    private var allowsStop: Bool {
        ["preparing", "recording", "stopping"].contains(state.status)
    }

    private var status: LocalizedStringResource {
        switch state.status {
        case "preparing": "Preparing"
        case "recording": "Recording"
        case "stopping": "Stopping"
        case "finished": "Recording saved"
        case "interrupted": "Recording interrupted"
        default: "Recording unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LocalMinutes").font(.headline)
                    Text(String(localized: status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                RecordingActivityElapsed(state: state)
            }
            Button(intent: StopRecordingActivityIntent(sessionID: meetingID.uuidString)) {
                Label("Stop Recording", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!allowsStop)
            .accessibilityLabel("Stop Recording")
            .accessibilityIdentifier("recording.activity.stop")
        }
    }
}

struct RecordingActivityElapsed: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        if let start = state.recordingStartedAt {
            Text(timerInterval: start...Date.distantFuture,
                 pauseTime: state.recordingEndedAt, countsDown: false, showsHours: true)
                .monospacedDigit()
                .accessibilityIdentifier("recording.activity.elapsed")
                .accessibilityHint("Elapsed recording time")
        }
    }
}
#endif
