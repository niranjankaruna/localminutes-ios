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
    @State private var player: AVAudioPlayer?
    @State private var playbackMessage: String?

    var body: some View {
        List {
            if let error = services.library.errorMessage { Text(error).foregroundStyle(.red) }
            Section("Meeting name") {
                TextField("Meeting name", text: $title)
                    .onSubmit { Task { await services.library.rename(title) } }
                Button("Save name") { Task { await services.library.rename(title) } }
            }
            Section("Original notes") {
                MeetingNotesEditor(controller: services.library)
            }
            Section("Transcript") {
                TextField("Find in this transcript", text: $search)
                    .onChange(of: search) { _, query in Task { await services.library.search(query) } }
                if services.library.transcript.isEmpty {
                    Text("No finalized transcript is available.").foregroundStyle(.secondary)
                }
                ForEach(search.isEmpty ? services.library.transcript : services.library.matches) { segment in
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
                if player != nil { Button("Stop playback") { stopPlayback() } }
            }
            Section("Export") {
                if let text = try? services.library.export(markdown: false) {
                    ShareLink("Share text", item: text)
                }
                if let markdown = try? services.library.export(markdown: true) {
                    ShareLink("Share Markdown", item: markdown)
                }
                Text("Sharing sends the selected meeting to the app you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(services.library.selected?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            await services.library.open(id: id)
            title = services.library.selected?.title ?? ""
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
            stopPlayback()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: location.fileURL)
            audio.currentTime = Double(location.frameOffset) / 16_000
            guard audio.prepareToPlay(), audio.play() else {
                throw MeetingPlaybackError.unreadableAudio
            }
            player = audio
            playbackMessage = "Playing the selected audio segment."
        } catch {
            stopPlayback()
            playbackMessage = "This audio segment could not be played."
        }
    }

    private func stopPlayback() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
