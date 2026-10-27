#if os(iOS)
import Foundation
import SwiftUI

@MainActor
struct MeetingDetailView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    let id: UUID
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var controller: MeetingLibraryController
    @State private var intelligenceController: MeetingIntelligenceController
    @State private var section: MeetingContentTab = .summary
    @State private var search = ""
    @State private var title = ""
    @State private var renaming = false
    @State private var renameSaving = false
    @State private var editingNotes = false
    @State private var showingExport = false
    @State private var showingModels = false
    @State private var confirmingDeletion = false
    @State private var deleting = false
    @State private var deletionMessage: String?
    @State private var playbackMessage: String?
    @State private var playbackRequestID: UUID?
    @State private var recoveredTranscript: [StoredTranscriptSegment]?
    @State private var selectedTranscriptSegmentID: UUID?
    @State private var citationNavigationRequestID: UUID?
    @State private var screenshotPrepared = false

    init(services: LocalMinutesServices, application: RecordingApplication, id: UUID) {
        self.services = services; self.application = application; self.id = id
        _controller = State(initialValue: MeetingLibraryController(store: services.store))
        _intelligenceController = State(initialValue: MeetingIntelligenceController(services: services, meetingID: id))
        #if DEBUG
        switch AppScreenshotFixture.scene {
        case .meetingNotes: _section = State(initialValue: .notes)
        case .meetingTranscript, .meetingTranscriptSearch, .meetingNoTranscript: _section = State(initialValue: .transcript)
        case .meetingAnswers: _section = State(initialValue: .ask)
        default: break
        }
        #endif
    }
    private var unavailable: Bool { deleting || services.maintainingLibrary || application.isRestoringLibrary }
    private var transcript: [StoredTranscriptSegment] { recoveredTranscript ?? controller.transcript }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading
                    MeetingContentPicker(selection: $section)
                    if controller.isLoadingDetail { ProgressView("Loading meeting…") }
                    if let error = controller.errorMessage ?? deletionMessage {
                        MinutesMessage(text: error, isError: true)
                    }
                    if !controller.isLoadingDetail {
                        switch section {
                        case .summary, .ask:
                            MeetingIntelligenceView(controller: intelligenceController,
                                content: section, chooseModel: { showingModels = true },
                                playCitation: playCitation)
                                .id("meeting.intelligence.top")
                        case .transcript: transcriptContent
                        case .notes: notesContent
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 32)
            }
            .background(MinutesStyle.background)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: citationNavigationRequestID) { _, _ in
                if let selectedTranscriptSegmentID { proxy.scrollTo(selectedTranscriptSegmentID, anchor: .center) }
            }
            .onChange(of: intelligenceController.modelRequired) { _, required in
                if required { proxy.scrollTo("meeting.intelligence.top", anchor: .top) }
            }
            .onChange(of: intelligenceController.errorMessage) { _, message in
                if message != nil { proxy.scrollTo("meeting.intelligence.top", anchor: .top) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if section == .ask && !controller.isLoadingDetail {
                MeetingQuestionComposer(controller: intelligenceController)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingExport = true } label: {
                    Image(systemName: "square.and.arrow.up").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Export meeting").accessibilityIdentifier("meeting.export.open")
                .disabled(controller.selected == nil)
                Menu {
                    Button("Rename meeting", systemImage: "pencil") {
                        title = controller.selected?.title ?? ""; renaming = true
                    }.accessibilityIdentifier("meeting.rename")
                    Button("Recover transcript", systemImage: "arrow.clockwise") {
                        section = .transcript; resumeTranscript()
                    }.disabled(intelligenceController.busy || services.recoveringMeetingID != nil)
                    Button("Delete meeting", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                        .accessibilityIdentifier("meeting.delete")
                        .disabled(intelligenceController.busy || services.recoveringMeetingID != nil)
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Meeting actions").accessibilityIdentifier("meeting.actions")
            }
        }
        .sheet(isPresented: $editingNotes) { MeetingNotesEditView(controller: controller) }
        .sheet(isPresented: $showingExport) {
            MeetingExportView(controller: controller, intelligence: intelligenceController)
        }
        .sheet(isPresented: $showingModels, onDismiss: intelligenceController.modelSelectionChanged) {
            ModelSetupSheet(controller: services.modelBrowser, application: application, purpose: .summary)
        }
        .sheet(isPresented: $renaming) { renameSheet }
        .confirmationDialog("Delete this meeting?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete meeting", role: .destructive) {
                deleting = true; stopOwnedPlayback()
                Task {
                    if await services.deleteMeeting(id: id) { dismiss() }
                    else { deletionMessage = services.libraryMessage ?? "The meeting could not be deleted yet." }
                    deleting = false
                }
            }.accessibilityIdentifier("meeting.delete.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its audio, transcript, notes, summaries, and answers will be permanently deleted.")
        }
        .disabled(unavailable)
        .task(id: id) {
            await controller.open(id: id)
            title = controller.selected?.title ?? ""
            await intelligenceController.load()
            #if DEBUG
            intelligenceController.prepareScreenshotState()
            if AppScreenshotFixture.scene == .meetingTranscriptSearch {
                search = "shared-term"; await controller.search(search)
            }
            if let scene = AppScreenshotFixture.scene, [.meetingExport, .meetingShare].contains(scene) { showingExport = true }
            if AppScreenshotFixture.scene?.isMeeting == true { screenshotPrepared = true }
            #endif
        }
        .onChange(of: services.recoveringMeetingID) { previous, current in
            if previous == id, current == nil {
                Task {
                    recoveredTranscript = try? await services.store.transcript(meetingID: id)
                    if !search.isEmpty { await controller.search(search) }
                    await intelligenceController.load()
                }
            }
        }
        .onDisappear {
            stopOwnedPlayback()
            intelligenceController.leaveMeeting(cancelGeneration: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { intelligenceController.leaveMeeting(cancelGeneration: false) }
        }
        .screenshotReady(screenshotPrepared)
        .privacySensitive()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.selected?.title ?? "Meeting")
                .font(.title.bold()).tracking(-0.5)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("meeting.title")
            if let meeting = controller.selected {
                Text("\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(meeting.capturedSampleCount / 16_000 / 60) min")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
    }

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(controller.note?.text.isEmpty == false ? controller.note!.text : "No notes yet.")
                .font(.body).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                .accessibilityIdentifier("meeting.notes.content")
            Button("Edit notes") { editingNotes = true }
                .frame(minHeight: 44).accessibilityIdentifier("meeting.notes.edit")
        }
    }

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if services.recoveringMeetingID == id {
                MinutesProgress(title: "Recovering transcript", detail: "Reading saved audio on this iPhone.",
                    cancel: { services.cancelTranscriptRecovery() })
            }
            if let message = services.libraryMessage { MinutesMessage(text: message) }
            if transcript.isEmpty {
                MinutesEmptyState(title: "Transcript unavailable", symbol: "waveform",
                    detail: "Resume transcription from the saved audio.",
                    actionTitle: "Resume transcription", action: resumeTranscript,
                    identifier: "meeting.transcript.empty")
                    .disabled(intelligenceController.busy || services.recoveringMeetingID != nil)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find in this transcript", text: $search)
                        .accessibilityIdentifier("meeting.transcript.search")
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search").frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                if !search.isEmpty && controller.matches.isEmpty {
                    Text("No matching transcript.").foregroundStyle(.secondary)
                }
                ForEach(search.isEmpty ? transcript : controller.matches) { segment in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { Task { await playSegment(at: segment.startSample) } } label: {
                            Label(MinutesStyle.timestamp(samples: segment.startSample), systemImage: "play.circle")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }
                        .accessibilityLabel("Play source at \(MinutesStyle.timestamp(samples: segment.startSample))")
                        Text(segment.text).font(.body).lineSpacing(5).textSelection(.enabled)
                            .accessibilityIdentifier("meeting.transcript.segment.\(segment.id.uuidString)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(selectedTranscriptSegmentID == segment.id ? MinutesStyle.accent.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 16))
                    .id(segment.id)
                    .accessibilityAddTraits(selectedTranscriptSegmentID == segment.id ? [.isSelected] : [])
                }
                if !search.isEmpty && controller.hasMoreTranscriptMatches {
                    Button("Load more matches") { Task { await controller.loadMoreTranscriptMatches() } }
                        .accessibilityIdentifier("meeting.transcript.loadMore")
                }
            }
            if let playbackMessage { MinutesMessage(text: playbackMessage) }
            if services.playback != nil || application.playbackOwnership?.hasPlaybackOwnership == true {
                Button { stopPlayback() } label: { Label("Stop playback", systemImage: "stop.fill") }
                    .buttonStyle(MinutesButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("meeting.playback.stop")
            }
        }
        .task(id: search) { await controller.search(search) }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section("Meeting name") { TextField("Meeting name", text: $title).submitLabel(.done) }
                if let error = controller.errorMessage { Text(error).foregroundStyle(MinutesStyle.recording) }
            }
            .minutesList().navigationTitle("Rename meeting").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renaming = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        renameSaving = true
                        Task {
                            await controller.rename(title.trimmingCharacters(in: .whitespacesAndNewlines))
                            renameSaving = false
                            if controller.errorMessage == nil { renaming = false }
                        }
                    }.disabled(renameSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled(renameSaving)
    }

    private func resumeTranscript() {
        guard !unavailable, !intelligenceController.busy, services.recoveringMeetingID == nil else { return }
        stopOwnedPlayback()
        services.resumeTranscript(meetingID: id)
    }

    private func playCitation(_ target: MeetingCitationNavigationTarget) async {
        guard target.meetingID == id, transcript.contains(where: { $0.id == target.segmentID && $0.meetingID == id }) else { return }
        search = ""; section = .transcript
        selectedTranscriptSegmentID = target.segmentID
        citationNavigationRequestID = UUID()
        await playSegment(at: target.startSample)
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
#endif
