import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LocalMinutesHomeView: View {
    let application: RecordingApplication
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            RecordingControlsView(application: application)
                .tabItem { Label("Record", systemImage: "mic") }
            if let services = application.services {
                MeetingHistoryView(services: services, application: application)
                    .tabItem { Label("Meetings", systemImage: "text.book.closed") }
                ModelBrowserView(controller: services.modelBrowser)
                    .tabItem { Label("Models", systemImage: "internaldrive") }
            }
        }
        .id(application.services.map { ObjectIdentifier($0) })
        .disabled(application.isRestoringLibrary || application.services?.maintainingLibrary == true)
        .tint(.teal)
        .task(id: application.services.map { ObjectIdentifier($0) }) { await application.services?.initialize() }
        .onChange(of: scenePhase) { _, phase in
            do {
                try application.recordScenePhase(phase)
                if phase == .background, let services = application.services {
                    _ = try services.persistMetricsCheckpoint()
                }
            }
            catch { application.services?.metrics?.recordError(.writeFailed) }
            if phase == .background { application.services?.cancelCurrentIntelligence() }
        }
    }
}

@MainActor
private struct MeetingHistoryView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    @State private var query = ""
    @State private var pendingDeletion: UUID?
    @State private var confirmingDeletion = false
    @State private var choosingBackup = false
    @State private var confirmingRestore = false
    @State private var pendingRestore: URL?
    @State private var backupURL: URL?
    @State private var reportText: String?
    @State private var working = false
    @State private var actionMessage: String?

    private var unavailable: Bool { working || services.maintainingLibrary || application.isRestoringLibrary }

    var body: some View {
        NavigationStack {
            List {
                if let error = services.library.errorMessage { Text(error).foregroundStyle(.red) }
                if let actionMessage { Text(actionMessage).foregroundStyle(.secondary) }
                if let message = services.libraryMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                if working { ProgressView("Preparing saved meetings…") }
                if let backupURL {
                    Section("Backup ready") {
                        ShareLink("Save or share library backup", item: backupURL)
                        Text("This backup includes meeting audio, transcripts, notes and generated content.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let reportText {
                    Section("Recording report") {
                        ShareLink("Share sampled recording report", item: reportText)
                        Text("Samples describe observed performance. Your locked-screen and long-meeting checks are still required.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { askToDelete(meeting.id) }
                            .disabled(unavailable)
                    }
                    .contextMenu {
                        Button("Delete meeting", role: .destructive) { askToDelete(meeting.id) }
                            .disabled(unavailable)
                    }
                }
            }
            .navigationTitle("Meetings")
            .searchable(text: $query, prompt: "Search meeting titles")
            .refreshable { await services.library.refresh() }
            .task { await services.library.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create library backup", systemImage: "square.and.arrow.up") { createBackup() }
                        Button("Restore library backup…", systemImage: "square.and.arrow.down") { choosingBackup = true }
                        Button("Prepare recording report", systemImage: "chart.bar") { prepareReport() }
                    } label: { Label("Library actions", systemImage: "ellipsis.circle") }
                    .disabled(unavailable)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                MeetingDetailView(services: services, application: application, id: id)
            }
            .confirmationDialog("Delete this meeting?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete meeting and all its data", role: .destructive) {
                    guard let id = pendingDeletion else { return }
                    pendingDeletion = nil; working = true
                    Task {
                        let removed = await services.deleteMeeting(id: id)
                        actionMessage = removed ? "Meeting deleted." : services.libraryMessage
                        working = false
                    }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Delete its audio, transcript, notes, summaries, answers and unfinished processing? This cannot be undone.")
            }
            .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let urls):
                        pendingRestore = urls.first
                        confirmingRestore = pendingRestore != nil
                    case .failure:
                        actionMessage = "The backup folder could not be opened."
                    }
                }
            }
            .confirmationDialog("Replace the current library?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("Use this backup", role: .destructive) { restoreBackup() }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                Text("Save edits and stop recording or playback first. This backup becomes the active library; the previous library is retained and installed models stay available.")
            }
            .disabled(services.maintainingLibrary || application.isRestoringLibrary)
        }
    }

    private func askToDelete(_ id: UUID) {
        guard !unavailable else { return }
        pendingDeletion = id; confirmingDeletion = true
    }

    private func createBackup() {
        guard !unavailable else { return }
        working = true; actionMessage = nil
        Task {
            defer { working = false }
            do { backupURL = try await application.exportLibraryBackup() }
            catch { actionMessage = "Stop recording, playback and local processing, then try creating the backup again." }
        }
    }

    private func restoreBackup() {
        guard !unavailable, let url = pendingRestore else { return }
        pendingRestore = nil; working = true; actionMessage = nil
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; working = false }
            do { try await application.restoreLibrary(from: url) }
            catch { actionMessage = "The backup could not be restored. The previous library remains available. Stop other work and check the selected backup folder." }
        }
    }

    private func prepareReport() {
        guard !unavailable else { return }
        do {
            let bytes = try services.exportEnduranceMetrics()
            guard let text = String(data: bytes, encoding: .utf8) else { return }
            reportText = text; actionMessage = nil
        } catch { actionMessage = "The recording report could not be prepared yet." }
    }
}

@MainActor
private struct MeetingDetailView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    let id: UUID
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var search = ""
    @State private var controller: MeetingLibraryController
    @State private var intelligenceController: MeetingIntelligenceController
    @State private var playbackMessage: String?
    @State private var playbackRequestID: UUID?
    @State private var confirmingDeletion = false
    @State private var deleting = false
    @State private var deletionMessage: String?
    @State private var recoveredTranscript: [StoredTranscriptSegment]?

    private var unavailable: Bool { deleting || services.maintainingLibrary || application.isRestoringLibrary }

    init(services: LocalMinutesServices, application: RecordingApplication, id: UUID) {
        self.services = services; self.application = application; self.id = id
        _controller = State(initialValue: MeetingLibraryController(store: services.store))
        _intelligenceController = State(initialValue: MeetingIntelligenceController(services: services, meetingID: id))
    }

    var body: some View {
        List {
            if let error = controller.errorMessage { Text(error).foregroundStyle(.red) }
            if let deletionMessage { Text(deletionMessage).foregroundStyle(.red) }
            Section("Meeting name") {
                TextField("Meeting name", text: $title)
                    .onSubmit { Task { await controller.rename(title) } }
                Button("Save name") { Task { await controller.rename(title) } }
            }
            Section("Original notes") {
                MeetingNotesEditor(controller: controller)
            }
            MeetingIntelligenceView(controller: intelligenceController, playCitation: { sample in
                await playSegment(at: sample)
            })
            Section("Transcript") {
                if services.recoveringMeetingID == id {
                    ProgressView("Resuming transcript from saved audio…")
                    Button("Cancel transcript recovery", role: .cancel) { services.cancelTranscriptRecovery() }
                } else {
                    Button("Resume transcript from saved audio") {
                        stopOwnedPlayback()
                        services.resumeTranscript(meetingID: id)
                    }
                    .disabled(unavailable || intelligenceController.busy || services.recoveringMeetingID != nil)
                }
                if let message = services.libraryMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                TextField("Find in this transcript", text: $search)
                    .onChange(of: search) { _, query in Task { await controller.search(query) } }
                if (recoveredTranscript ?? controller.transcript).isEmpty {
                    Text("No finalized transcript is available.").foregroundStyle(.secondary)
                }
                ForEach(search.isEmpty ? (recoveredTranscript ?? controller.transcript) : controller.matches) { segment in
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
            Section {
                Button("Delete meeting", role: .destructive) { confirmingDeletion = true }
                    .disabled(unavailable || intelligenceController.busy || services.recoveringMeetingID != nil)
            }
        }
        .navigationTitle(controller.selected?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            await controller.open(id: id)
            title = controller.selected?.title ?? ""
            await intelligenceController.load()
        }
        .onChange(of: services.recoveringMeetingID) { previous, current in
            if previous == id, current == nil {
                Task {
                    // Refresh only transcript rows; keep the note editor and
                    // any unsaved original note bound to its existing controller.
                    recoveredTranscript = try? await services.store.transcript(meetingID: id)
                    if !search.isEmpty { await controller.search(search) }
                    await intelligenceController.load()
                }
            }
        }
        .confirmationDialog("Delete this meeting?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete meeting and all its data", role: .destructive) {
                deleting = true; stopOwnedPlayback()
                Task {
                    if await services.deleteMeeting(id: id) { dismiss() }
                    else { deletionMessage = services.libraryMessage ?? "The meeting could not be deleted yet." }
                    deleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete its audio, transcript, notes, summaries, answers and unfinished processing? This cannot be undone.")
        }
        .disabled(unavailable)
        .onDisappear {
            stopOwnedPlayback()
            intelligenceController.leaveMeeting()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { intelligenceController.leaveMeeting() }
        }
        .privacySensitive()
    }

    private func timestamp(_ sample: Int64) -> String {
        let seconds = sample / 16_000
        return String(format: "%02lld:%02lld:%02lld", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    private func playSegment(at sample: Int64) async {
        let requestID = UUID()
        playbackRequestID = requestID
        if let state = await application.owner?.snapshot(),
           state.cleanupPending || [.preparing, .recording, .stopping].contains(state.phase) {
            guard playbackRequestID == requestID else { return }
            playbackMessage = "Stop recording before playing meeting audio."
            playbackRequestID = nil
            return
        }
        guard playbackRequestID == requestID else { return }
        do {
            let directory = services.meetingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
            let manifest = try JSONDecoder().decode(AudioCaptureManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("capture-manifest.json")))
            guard let location = try MeetingPlaybackMapper.locate(globalSample: sample,
                meetingID: id, manifest: manifest, meetingDirectory: directory) else {
                playbackMessage = "Audio is unavailable at this time."
                playbackRequestID = nil
                return
            }
            let result = await application.playAudio(at: location, requestID: requestID)
            guard playbackRequestID == requestID else { return }
            switch result {
            case .playing: playbackMessage = "Playing the selected audio segment."
            case .blockedByRecording: playbackMessage = "Stop recording before playing meeting audio."
            case .cleanupPending: playbackMessage = "Audio cleanup is pending. Tap Stop playback to retry."
            default: playbackMessage = "This audio segment could not be played."
            }
        } catch {
            guard playbackRequestID == requestID else { return }
            stopOwnedPlayback()
            playbackMessage = "This audio segment could not be played."
        }
    }

    private func stopOwnedPlayback() {
        guard let requestID = playbackRequestID else { return }
        playbackRequestID = nil
        playbackMessage = application.stopPlayback(expectedRequestID: requestID) == .cleanupPending
            ? "Audio cleanup is pending. Tap Stop playback to retry." : nil
    }

    private func stopPlayback() {
        playbackRequestID = nil
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
    @State private var lastEdit: StoredManualNote?
    @State private var saveError: String?
    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $text)
            .frame(minHeight: 120)
            .accessibilityLabel("Original meeting notes")
            .task(id: controller.selected?.id) {
                if let edit = lastEdit, edit.meetingID != controller.selected?.id {
                    pending?.cancel()
                    Task { await persist(edit) }
                    lastEdit = nil
                    saveError = nil
                }
                text = controller.note?.text ?? ""
            }
            .onChange(of: text) { _, value in
                pending?.cancel()
                guard let edit = controller.reserveManualNoteEdit(value) else { return }
                lastEdit = edit
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await persist(edit)
                }
            }
            .onDisappear {
                pending?.cancel()
                if let edit = lastEdit { Task { await persist(edit) } }
            }
            if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func persist(_ edit: StoredManualNote) async {
        do {
            try await controller.saveNotes(edit)
            guard controller.selected?.id == edit.meetingID, lastEdit == edit else { return }
            lastEdit = nil
            saveError = nil
        } catch {
            guard controller.selected?.id == edit.meetingID, lastEdit == edit else { return }
            saveError = "The latest note has not been saved. Keep this meeting open and try again."
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
                    Text("Refresh the same app with iLoader every seven days. Keep its bundle IDs and do not delete it before renewing.")
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
