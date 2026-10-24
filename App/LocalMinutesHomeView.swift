import AVFoundation
import Foundation
import SwiftUI

@MainActor
struct LocalMinutesHomeView: View {
    let application: RecordingApplication
    var body: some View {
        TabView {
            RecordingControlsView(application: application)
                .tabItem { Label("Record", systemImage: "mic") }
            if let services = application.services {
                MeetingHistoryView(services: services, application: application)
                    .tabItem { Label("Meetings", systemImage: "text.book.closed") }
                ModelSettingsView(services: services, application: application)
                    .tabItem { Label("Models", systemImage: "internaldrive") }
            }
        }
        .tint(.teal)
    }
}

@MainActor
private struct MeetingHistoryView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = services.library.errorMessage { Text(error).foregroundStyle(.red) }
                if services.library.meetings.isEmpty {
                    ContentUnavailableView("No meetings yet", systemImage: "text.book.closed",
                        description: Text("Install the speech model, then start your first meeting."))
                }
                ForEach(services.library.meetings.filter {
                    query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                }) { meeting in
                    NavigationLink(value: meeting.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meeting.title).font(.headline)
                            Text(meeting.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(meeting.capturedSampleCount / 16_000 / 60) min · \(meeting.recordingState == .recording ? "Unfinished" : meeting.recordingState.rawValue.capitalized)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("Meetings")
            .searchable(text: $query, prompt: "Search meeting titles")
            .refreshable { await services.library.refresh() }
            .task { await services.library.refresh() }
            .navigationDestination(for: UUID.self) { id in
                MeetingDetailView(services: services, application: application, id: id)
            }
        }
    }
}

@MainActor
private struct MeetingDetailView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    let id: UUID
    @State private var title = ""
    @State private var search = ""
    @State private var controller: MeetingLibraryController
    @State private var playbackMessage: String?

    init(services: LocalMinutesServices, application: RecordingApplication, id: UUID) {
        self.services = services; self.application = application; self.id = id
        _controller = State(initialValue: MeetingLibraryController(store: services.store))
    }

    var body: some View {
        List {
            if let error = controller.errorMessage { Text(error).foregroundStyle(.red) }
            Section("Meeting name") {
                TextField("Meeting name", text: $title)
                    .onSubmit { Task { await controller.rename(title) } }
                Button("Save name") { Task { await controller.rename(title) } }
            }
            Section("Original notes") {
                MeetingNotesEditor(controller: controller)
            }
            Section("Transcript") {
                TextField("Find in this transcript", text: $search)
                    .onChange(of: search) { _, query in Task { await controller.search(query) } }
                if controller.transcript.isEmpty {
                    Text("No finalized transcript is available.").foregroundStyle(.secondary)
                }
                ForEach(search.isEmpty ? controller.transcript : controller.matches) { segment in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(segment.text).textSelection(.enabled)
                        Button {
                            Task { await playSegment(at: segment.startSample) }
                        } label: {
                            Label("Play segment at \(timestamp(segment.startSample))", systemImage: "play.circle")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                }
                if let playbackMessage { Text(playbackMessage).font(.caption).foregroundStyle(.secondary) }
                if services.playback != nil || application.playbackOwnership?.hasPlaybackOwnership == true {
                    Button("Stop playback") { stopPlayback() }
                }
            }
            Section("Export") {
                if let text = try? controller.export(markdown: false) {
                    ShareLink("Share text", item: text)
                }
                if let markdown = try? controller.export(markdown: true) {
                    ShareLink("Share Markdown", item: markdown)
                }
                Text("Sharing sends the selected meeting to the app you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(controller.selected?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            await controller.open(id: id)
            title = controller.selected?.title ?? ""
        }
        .onDisappear { stopPlayback() }
        .privacySensitive()
    }

    private func timestamp(_ sample: Int64) -> String {
        let seconds = sample / 16_000
        return String(format: "%02lld:%02lld:%02lld", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private func playSegment(at sample: Int64) async {
        if let state = await application.owner?.snapshot(),
           state.cleanupPending || [.preparing, .recording, .stopping].contains(state.phase) {
            playbackMessage = "Stop recording before playing meeting audio."
            return
        }
        do {
            let directory = services.meetingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            let manifest = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json")))
            guard let location = try MeetingPlaybackMapper.locate(globalSample: sample,
                meetingID: id, manifest: manifest, meetingDirectory: directory) else {
                playbackMessage = "Audio is unavailable at this time."; return
            }
            switch await application.playAudio(at: location) {
            case .playing: playbackMessage = "Playing the selected audio segment."
            case .blockedByRecording: playbackMessage = "Stop recording before playing meeting audio."
            case .cleanupPending: playbackMessage = "Audio cleanup is pending. Tap Stop playback to retry."
            default: playbackMessage = "This audio segment could not be played."
            }
        } catch {
            stopPlayback()
            playbackMessage = "This audio segment could not be played."
        }
    }

    private func stopPlayback() {
        playbackMessage = application.stopPlayback() == .cleanupPending
            ? "Audio cleanup is pending. Tap Stop playback to retry." : nil
    }
}

@MainActor
struct ActiveMeetingNotesView: View {
    let id: UUID
    @State private var controller: MeetingLibraryController
    init(services: LocalMinutesServices, id: UUID) {
        self.id = id
        _controller = State(initialValue: MeetingLibraryController(store: services.store))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Original notes").font(.headline)
            MeetingNotesEditor(controller: controller)
            if let error = controller.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task(id: id) { await controller.open(id: id) }
    }
}

@MainActor
struct MeetingNotesEditor: View {
    let controller: MeetingLibraryController
    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    var body: some View {
        TextEditor(text: $text)
            .frame(minHeight: 120)
            .accessibilityLabel("Original meeting notes")
            .task(id: controller.selected?.id) { text = controller.note?.text ?? "" }
            .onChange(of: text) { _, value in
                guard value != controller.note?.text else { return }
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await controller.saveNotes(value)
                }
            }
            .onDisappear {
                pending?.cancel()
                let value = text
                if value != controller.note?.text { Task { await controller.saveNotes(value) } }
            }
    }
}

@MainActor
private struct ModelSettingsView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    @State private var busyRecording = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Offline speech") {
                    Label(services.speechInstalled ? "Speech model verified" : "Speech model required",
                          systemImage: services.speechInstalled ? "checkmark.shield" : "arrow.down.circle")
                    Text("English · 73 MB · runs on this iPhone").font(.caption)
                    Button(services.speechInstalled ? "Download speech model again" : "Download speech model") {
                        Task { await download(StreamingEnglishModel.manifest) }
                    }.disabled(services.isChangingModels)
                    if services.speechInstalled {
                        Button("Remove speech model", role: .destructive) {
                            Task { await services.remove(StreamingEnglishModel.manifest) }
                        }.disabled(services.isChangingModels)
                    }
                }
                Section("Local summary model") {
                    Text(services.summaryInstalled ? "Summary model verified" : "Optional download · 1.12 GB")
                    Text("Summary quality and app integration are still being verified.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Download summary model") { Task { await download(LocalMinutesServices.summaryManifest) } }
                        .disabled(services.isChangingModels)
                    if services.summaryInstalled {
                        Button("Remove summary model", role: .destructive) {
                            Task { await services.remove(LocalMinutesServices.summaryManifest) }
                        }.disabled(services.isChangingModels)
                    }
                }
                if let message = services.operationMessage {
                    Section { ProgressView(message); Button("Cancel download") { services.cancelDownload() } }
                }
                if let error = services.modelError { Text(error).foregroundStyle(.red) }
                if busyRecording { Text("Stop recording before changing models.").foregroundStyle(.secondary) }
                Section("Action Button") {
                    Text("In iPhone Settings, choose Action Button → Shortcut → Toggle LocalMinutes Recording.")
                    Text("Locked start and free-signing behavior require your phone checks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy and renewal") {
                    Text("After installation, speech processing uses local files and the CPU. Downloads need internet.")
                    Text("Refresh the same app with Sideloadly every seven days. Keep its bundle IDs and do not delete it before renewing.")
                    Text("Record meetings only with the participants’ consent.")
                }
            }
            .navigationTitle("Models & Settings")
            .task { await services.refreshModels() }
        }
    }

    private func download(_ manifest: ModelManifest) async {
        if let state = await application.owner?.snapshot(),
           state.cleanupPending || [.preparing, .recording, .stopping].contains(state.phase) {
            busyRecording = true; return
        }
        busyRecording = false
        services.download(manifest)
    }
}
