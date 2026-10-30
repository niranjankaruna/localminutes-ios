#if os(iOS)
import SwiftUI
import UIKit

@MainActor
struct RecordingPermissionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var controller: RecordingPermissionsController

    init(controller: RecordingPermissionsController? = nil) {
        #if DEBUG
        if let screenshot = AppScreenshotFixture.permissions {
            _controller = State(initialValue: controller ?? screenshot)
            return
        }
        #endif
        _controller = State(initialValue: controller ?? RecordingPermissionsController())
    }

    var body: some View {
        List {
            Section {
                MinutesLabeledValue(title: "Microphone", value: microphoneStatus)
                    .accessibilityIdentifier("recording.permissions.microphone")
                switch controller.microphone {
                case .notRequested:
                    Text("Allow access to record conversations you choose. This opens the iPhone microphone permission prompt.")
                        .foregroundStyle(.secondary)
                    Button(controller.requestingMicrophone ? "Requesting access…" : "Allow microphone") {
                        Task { await controller.requestMicrophone() }
                    }
                    .buttonStyle(MinutesButtonStyle())
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
                MinutesLabeledValue(title: "Live Activities", value: controller.liveActivitiesEnabled ? "Enabled" : "Disabled")
                    .accessibilityIdentifier("recording.permissions.liveActivities")
                Text(controller.liveActivitiesEnabled
                    ? "A Live Activity shows recording status and a Stop button on the Lock Screen."
                    : "Enable Live Activities in iPhone Settings → Apps → LocalMinutes. Recording needs a Live Activity to show its status and Stop button on the Lock Screen.")
                    .foregroundStyle(.secondary)
                if !controller.liveActivitiesEnabled { settingsButton }
            } header: { Text("Recording status") }

            Section("Action Button & Shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Open Recording, Open Meetings, or Open Last Meeting in the Action Button or Shortcuts settings.")
                    Text("These shortcuts open the app. Start recording when you are ready.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section("Record with your iPhone locked") {
                Text("Allow microphone access and choose a speech model in Settings → Speech. Start recording in the app, then wait until Recording appears before locking your iPhone.")
                    .foregroundStyle(.secondary)
                Text("The Live Activity shows recording status and lets you stop from the Lock Screen.")
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
        .buttonStyle(MinutesButtonStyle(kind: .secondary))
        .accessibilityIdentifier("recording.permissions.openSettings")
    }
}
#endif
