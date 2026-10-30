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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("LocalMinutes", systemImage: "mic.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(String(localized: status)).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                RecordingActivityElapsed(state: state).font(.title2.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            Button(intent: StopRecordingActivityIntent(sessionID: meetingID.uuidString)) {
                Image(systemName: "stop.fill")
                    .font(.title3.weight(.semibold)).foregroundStyle(.red)
                    .frame(width: 52, height: 52)
                    .background(.red.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
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
