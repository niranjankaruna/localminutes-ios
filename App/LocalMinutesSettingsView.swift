#if os(iOS)
import SwiftUI
import UIKit

enum MinutesSettingsRoute: Hashable { case speech, summary, about, device, storage, privacy, report }

@MainActor
struct LocalMinutesSettingsView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    @State private var path = NavigationPath()
    @State private var actions: LibraryActionsController
    @State private var showingBackup = false

    init(services: LocalMinutesServices, application: RecordingApplication, actions: LibraryActionsController) {
        self.services = services; self.application = application
        _actions = State(initialValue: actions)
        #if DEBUG
        if let scene = AppScreenshotFixture.scene, scene.isModels {
            switch scene {
            case .modelsAbout: _path = State(initialValue: NavigationPath([MinutesSettingsRoute.about]))
            case .modelsDevice: _path = State(initialValue: NavigationPath([MinutesSettingsRoute.about, .device]))
            case .modelsStorage: _path = State(initialValue: NavigationPath([MinutesSettingsRoute.about, .storage]))
            default: _path = State(initialValue: NavigationPath([scene.usesSummaryModels ? MinutesSettingsRoute.summary : .speech]))
            }
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: MinutesSettingsRoute.speech) {
                        settingsRow("Speech", subtitle: selectedModel(.speechRecognition), symbol: "waveform")
                    }.accessibilityIdentifier("settings.models.speech")
                    NavigationLink(value: MinutesSettingsRoute.summary) {
                        settingsRow("Summaries & answers", subtitle: selectedModel(.summary), symbol: "sparkles")
                    }.accessibilityIdentifier("settings.models.summary")
                } header: { Text("Models") } footer: { Text("Models work on this iPhone.") }
                Section("Library") {
                    Button { actions.prepareNewBackup(); showingBackup = true } label: {
                        Label("Back up meetings", systemImage: "square.and.arrow.up")
                    }
                        .accessibilityIdentifier("settings.backup").disabled(actions.unavailable)
                    Button { actions.choosingBackup = true } label: { Label("Restore backup", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("settings.restore").disabled(actions.unavailable)
                    if let message = actions.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                Section {
                    NavigationLink("Privacy", value: MinutesSettingsRoute.privacy)
                        .accessibilityIdentifier("settings.privacy")
                    NavigationLink("About & diagnostics", value: MinutesSettingsRoute.about)
                        .accessibilityIdentifier("settings.about")
                }
            }
            .minutesList().navigationTitle("Settings")
            .navigationDestination(for: MinutesSettingsRoute.self) { route in
                switch route {
                case .speech: ModelPurposeView(controller: services.modelBrowser, purpose: .speechRecognition, application: application)
                case .summary: ModelPurposeView(controller: services.modelBrowser, purpose: .summary, application: application)
                case .about: MinutesAboutView(controller: services.modelBrowser, application: application, actions: actions)
                case .device: ModelDeviceView(controller: services.modelBrowser)
                case .storage: StorageCheckView(controller: services.modelBrowser, application: application)
                case .privacy: MinutesPrivacyView()
                case .report: RecordingReportView(controller: actions)
                }
            }
            .modifier(LibraryRestoreModifier(controller: actions))
            .sheet(isPresented: $showingBackup) { LibraryBackupView(controller: actions) }
            .task { await services.modelBrowser.refresh() }
        }
    }
    private func selectedModel(_ purpose: ModelPurpose) -> String {
        let browser = services.modelBrowser
        if purpose == .summary && browser.appleEquipped { return "Apple Intelligence" }
        if let model = browser.installed.first(where: { $0.purpose == purpose && browser.isEquipped($0) }) {
            return ModelDisplay.name(model)
        }
        return "Choose a model"
    }
    private func settingsRow(_ title: String, subtitle: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        } icon: { Image(systemName: symbol).foregroundStyle(MinutesStyle.accent) }
    }
}

struct MinutesAboutView: View {
    let controller: ModelBrowserController
    let application: RecordingApplication?
    let actions: LibraryActionsController?
    var body: some View {
        List {
            Section {
                Text("LocalMinutes").font(.title2.weight(.semibold))
                if let identity = AppBuildIdentity.current() {
                    Text("Version \(identity.version) (build \(identity.build))")
                        .foregroundStyle(.secondary).accessibilityIdentifier("settings.appBuildIdentity")
                } else {
                    Text("Version and build unavailable").accessibilityIdentifier("settings.appBuildIdentity")
                }
            }
            Section {
                NavigationLink("This iPhone") { ModelDeviceView(controller: controller) }
                    .accessibilityIdentifier("settings.device")
                NavigationLink("Storage check") { StorageCheckView(controller: controller, application: application) }
                    .accessibilityIdentifier("settings.storage")
                if let actions {
                    NavigationLink("Recording report") { RecordingReportView(controller: actions) }
                }
            }
            Section { NavigationLink("Privacy") { MinutesPrivacyView() } }
        }
        .minutesList().navigationTitle("About & diagnostics")
        .screenshotReady(true)
    }
}

struct ModelDeviceView: View {
    let controller: ModelBrowserController
    var body: some View {
        List {
            Section {
                LabeledContent("Free storage", value: MinutesStyle.bytes(controller.resources.freeDiskBytes))
                LabeledContent("Total memory", value: MinutesStyle.bytes(controller.resources.totalMemoryBytes, memory: true))
                LabeledContent("Available to this app") {
                    Text(MinutesStyle.bytes(controller.resources.availableAppMemoryBytes, memory: true))
                        .accessibilityIdentifier("models.device.availableMemory")
                }
            } header: {
                Text("This iPhone").accessibilityIdentifier("models.device.heading")
            } footer: {
                Text("Available memory changes as other apps run. Model estimates are guidance.")
            }
        }
        .minutesList().navigationTitle("This iPhone").navigationBarTitleDisplayMode(.inline)
        .screenshotReady(true)
        .task { await controller.refresh() }
    }
}

struct StorageCheckView: View {
    let controller: ModelBrowserController
    let application: RecordingApplication?
    var body: some View {
        List {
            Section {
                if controller.isPreparingStorageCheck { ProgressView("Checking storage…") }
                if let report = controller.storageCheckReport {
                    Label(report.audit.status == .complete ? "Storage check ready" : "Storage check incomplete", systemImage: "checkmark.shield")
                        .font(.headline)
                        .accessibilityIdentifier(report.audit.status == .complete ? "settings.storageAudit.ready" : "settings.storageAudit.status")
                    Text("Environment: \(environment(report.audit.environment))")
                        .accessibilityIdentifier("settings.storageAudit.environment")
                    Text("Inspected items: \(report.audit.inspectedItemCount)")
                        .accessibilityIdentifier("settings.storageAudit.itemCount")
                    Text("Metadata groups: \(report.audit.groups.count)")
                        .accessibilityIdentifier("settings.storageAudit.groupCount")
                    if let json = controller.storageCheckJSON {
                        ShareLink("Share storage check", item: json)
                            .frame(minHeight: 44).accessibilityIdentifier("settings.storageAudit.share")
                    }
                }
                if let error = controller.storageCheckError {
                    Text(error).foregroundStyle(MinutesStyle.recording).accessibilityIdentifier("settings.storageAudit.error")
                }
                Button(controller.storageCheckReport == nil ? "Prepare storage check" : "Run again") {
                    Task { await controller.prepareStorageCheck(recordingOwner: application?.owner) }
                }
                .frame(minHeight: 44).accessibilityIdentifier("settings.storageAudit.prepare")
                .disabled(application?.owner == nil || controller.isWorking || controller.isInspecting || controller.isPreparingStorageCheck)
            } footer: {
                Text("No meeting content or file paths are shared. This check does not verify Lock Screen access.")
            }
        }
        .minutesList().navigationTitle("Storage check")
        .screenshotReady(!controller.isPreparingStorageCheck)
    }
    private func environment(_ value: StorageAuditEnvironment) -> String {
        switch value {
        case .iOSDevice: "iOS Device"
        case .iOSSimulator: "iOS Simulator"
        case .macOS: "macOS"
        case .other: "Other"
        }
    }
}

struct MinutesPrivacyView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(MinutesStyle.accent)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your meetings stay with you.").font(.title2.weight(.semibold))
                    Text("Audio, transcripts, summaries, and answers are processed on your iPhone. No account or cloud processing.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("You choose what to share.").font(.title2.weight(.semibold))
                    Text("Meeting content leaves the app only when you export or share it.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Microphone").font(.headline)
                    Text("Microphone permission is used only for recordings you start. Change access in iPhone Settings.")
                        .foregroundStyle(.secondary).accessibilityIdentifier("recording.microphoneExplanation")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live Activity").font(.headline)
                    Text("A Live Activity shows recording status and lets you stop from the Lock Screen.")
                        .foregroundStyle(.secondary).accessibilityIdentifier("recording.liveActivityExplanation")
                }
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.buttonStyle(MinutesButtonStyle(kind: .secondary))
            }.font(.body).lineSpacing(4).padding(24)
        }
        .background(MinutesStyle.background).navigationTitle("Privacy")
    }
}
#endif
