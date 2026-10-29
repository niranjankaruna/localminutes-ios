#if os(iOS)
import SwiftUI
import UIKit

@MainActor
struct RecordingPermissionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var controller: RecordingPermissionsController

    init(controller: RecordingPermissionsController? = nil) {
        _controller = State(initialValue: controller ?? RecordingPermissionsController())
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Microphone", value: microphoneStatus)
                    .accessibilityIdentifier("recording.permissions.microphone")
                switch controller.microphone {
                case .notRequested:
                    Text("Allow microphone access here. The microphone switch may not appear in iPhone Settings until you respond to the permission prompt.")
                        .foregroundStyle(.secondary)
                    Button(controller.requestingMicrophone ? "Requesting access…" : "Allow microphone") {
                        Task { await controller.requestMicrophone() }
                    }
                    .disabled(controller.requestingMicrophone)
                    .accessibilityIdentifier("recording.permissions.allowMicrophone")
                case .denied:
                    Text("Microphone access is off. Open iPhone Settings and enable Microphone for LocalMinutes. You can also find it under Privacy & Security → Microphone.")
                        .foregroundStyle(.secondary)
                    settingsButton
                case .allowed:
                    Text("Microphone access is allowed. LocalMinutes records only when you start a recording.")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Microphone access") } footer: {
                Text("Allowing access does not start a recording or require a speech model.")
            }

            Section {
                LabeledContent("Live Activities", value: controller.liveActivitiesEnabled ? "Enabled" : "Disabled")
                    .accessibilityIdentifier("recording.permissions.liveActivities")
                Text(controller.liveActivitiesEnabled
                    ? "A Live Activity shows recording status and a Stop button on the Lock Screen."
                    : "Enable Live Activities in iPhone Settings → Apps → LocalMinutes. Recording needs a Live Activity to show its status and Stop button on the Lock Screen.")
                    .foregroundStyle(.secondary)
                if !controller.liveActivitiesEnabled { settingsButton }
            } header: { Text("Recording status") }

            Section("Action Button & Shortcuts") {
                Text("Allow microphone access and equip a speech model in Settings → Speech. Start, Stop, and Toggle Recording from the Action Button or Shortcuts run in the background. A Live Activity shows recording status. If an action cannot run, it reports the reason without opening LocalMinutes.")
                    .foregroundStyle(.secondary)
            }
        }
        .minutesList().navigationTitle("Recording permissions")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { controller.refresh() }
        }
    }

    private var microphoneStatus: String {
        switch controller.microphone {
        case .notRequested: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Denied"
        }
    }

    private var settingsButton: some View {
        Button("Open iPhone Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}
#endif
