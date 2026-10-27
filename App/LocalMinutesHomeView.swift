import Foundation
import SwiftUI

enum LocalMinutesTab: Hashable { case meetings, record, settings }

@MainActor
struct LocalMinutesHomeView: View {
    let application: RecordingApplication
    @Environment(\.scenePhase) private var scenePhase
    @State private var privacy: RecordingPrivacyController
    @State private var libraryActions: LibraryActionsController
    @State private var selectedTab: LocalMinutesTab = .meetings
    @State private var meetingPath: [UUID] = []
    @State private var handledMeetingRequestID: UUID?

    init(application: RecordingApplication, privacy: RecordingPrivacyController? = nil) {
        self.application = application
        _privacy = State(initialValue: privacy ?? RecordingPrivacyController())
        _libraryActions = State(initialValue: LibraryActionsController(application: application))
        #if DEBUG
        if let scene = AppScreenshotFixture.scene {
            _selectedTab = State(initialValue: scene.isModels ? .settings : scene.isRecord ? .record : .meetings)
            _meetingPath = State(initialValue: scene.isMeeting ? [AppScreenshotFixture.detailMeetingID] : [])
        }
        #endif
    }

    var body: some View {
        RecordingPrivacyRoot(controller: privacy) {
            TabView(selection: $selectedTab) {
                Group {
                    if let services = application.services {
                        MeetingHistoryView(services: services, application: application, actions: libraryActions, path: $meetingPath,
                                           startRecording: { selectedTab = .record })
                    } else {
                        ContentUnavailableView("Meetings unavailable", systemImage: "externaldrive.badge.exclamationmark",
                            description: Text("Reopen LocalMinutes to try loading your library again."))
                    }
                }
                .tabItem { Label("Meetings", systemImage: "text.book.closed") }.tag(LocalMinutesTab.meetings)
                RecordingControlsView(application: application, openMeeting: { id in
                    meetingPath = [id]; selectedTab = .meetings
                })
                .tabItem { Label("Record", systemImage: "mic") }.tag(LocalMinutesTab.record)
                Group {
                    if let services = application.services {
                        LocalMinutesSettingsView(services: services, application: application, actions: libraryActions)
                    } else {
                        NavigationStack { MinutesPrivacyView() }
                    }
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(LocalMinutesTab.settings)
            }
            .id(application.services.map { ObjectIdentifier($0) })
            .tint(MinutesStyle.accent)
            .disabled(application.isRestoringLibrary || application.services?.maintainingLibrary == true)
            .overlay {
                if application.isRestoringLibrary {
                    ZStack {
                        MinutesStyle.background.ignoresSafeArea()
                        MinutesProgress(title: "Preparing your library", detail: "Keep LocalMinutes open.").padding(24)
                    }.accessibilityIdentifier("library.restoring")
                }
            }
            .task(id: application.services.map { ObjectIdentifier($0) }) { await application.services?.initialize() }
            .onChange(of: application.meetingNavigation?.requestID, initial: true) { _, requestID in
                #if DEBUG
                if AppScreenshotFixture.scene != nil { return }
                #endif
                guard let requestID, let id = application.meetingNavigation?.requestedMeetingID else {
                    meetingPath = []; handledMeetingRequestID = nil
                    return
                }
                guard handledMeetingRequestID != requestID else { return }
                handledMeetingRequestID = requestID
                meetingPath = [id]; selectedTab = .meetings
            }
            .onChange(of: scenePhase) { _, phase in
                do {
                    try application.recordScenePhase(phase)
                    if phase == .background, let services = application.services {
                        _ = try services.persistMetricsCheckpoint()
                    }
                } catch { application.services?.metrics?.recordError(.writeFailed) }
            }
        }
        .onChange(of: application.services.map { ObjectIdentifier($0) }) { previous, current in
            guard previous != nil, current != nil, previous != current else { return }
            // A restore (including reopening the retained library on failure)
            // invalidates detail controllers tied to the previous SQLite store.
            meetingPath = []
            handledMeetingRequestID = nil
            selectedTab = .meetings
        }
    }
}

@MainActor
private struct MeetingHistoryView: View {
    let services: LocalMinutesServices
    let application: RecordingApplication
    @Binding var path: [UUID]
    let startRecording: () -> Void
    @State private var query = ""
    @State private var pendingDeletion: UUID?
    @State private var confirmingDeletion = false
    @State private var deleting = false
    @State private var showingBackup = false
    @State private var showingReport = false
    @State private var screenshotPrepared = false
    @State private var actions: LibraryActionsController

    init(services: LocalMinutesServices, application: RecordingApplication, actions: LibraryActionsController,
         path: Binding<[UUID]>, startRecording: @escaping () -> Void) {
        self.services = services; self.application = application; _path = path
        self.startRecording = startRecording
        _actions = State(initialValue: actions)
    }
    private var unavailable: Bool { actions.unavailable || deleting }
    private var days: [Date] {
        Array(Set(services.library.meetings.map { Calendar.current.startOfDay(for: $0.createdAt) })).sorted(by: >)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error = services.library.errorMessage {
                    Section { Text(error).foregroundStyle(MinutesStyle.recording) }
                }
                if let message = actions.message ?? services.libraryMessage {
                    Section { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                if services.library.meetings.isEmpty && !services.library.isLoadingHistory && services.library.errorMessage == nil {
                    MinutesEmptyState(title: query.isEmpty ? "No meetings yet" : "No matching meetings",
                        symbol: query.isEmpty ? "text.book.closed" : "magnifyingglass",
                        detail: query.isEmpty ? "Record a conversation. Keep the details." : "Try a different meeting title.",
                        actionTitle: query.isEmpty ? "Record a meeting" : "Clear search",
                        action: { if query.isEmpty { startRecording() } else { query = "" } },
                        identifier: "meeting.history.empty")
                        .listRowBackground(Color.clear)
                }
                ForEach(days, id: \.self) { day in
                    Section(dayTitle(day)) {
                        ForEach(services.library.meetings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }) { meeting in
                            NavigationLink(value: meeting.id) {
                                MeetingHistoryRow(meeting: meeting,
                                    content: services.library.contentStatuses[meeting.id] ?? .unknown)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { askToDelete(meeting.id) }.disabled(unavailable)
                            }
                            .contextMenu {
                                Button("Delete meeting", systemImage: "trash", role: .destructive) { askToDelete(meeting.id) }
                                    .disabled(unavailable)
                            }
                        }
                    }
                }
                if services.library.isLoadingHistory { ProgressView("Loading meetings…") }
                if services.library.hasMoreMeetings {
                    Button("Load more meetings") { Task { await services.library.loadMoreMeetings() } }
                        .accessibilityIdentifier("meeting.history.loadMore")
                        .disabled(unavailable || services.library.isLoadingHistory)
                }
            }
            .minutesList().navigationTitle("Meetings")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search meeting titles")
            .refreshable { await services.library.refresh() }
            .task(id: query) { await services.library.searchHistory(query) }
            .onChange(of: path) { _, value in if value.isEmpty { Task { await services.library.refresh() } } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if services.library.hasMoreMeetings {
                            Button("Load more meetings") { Task { await services.library.loadMoreMeetings() } }
                                .accessibilityIdentifier("meeting.history.loadMore.menu")
                                .disabled(services.library.isLoadingHistory)
                        }
                        Button("Back up meetings", systemImage: "square.and.arrow.up") {
                            actions.prepareNewBackup(); showingBackup = true
                        }
                            .accessibilityIdentifier("meeting.history.backup.create")
                        Button("Restore backup", systemImage: "square.and.arrow.down") { actions.choosingBackup = true }
                            .accessibilityIdentifier("meeting.history.backup.restore")
                        Button("Recording report", systemImage: "chart.bar") { showingReport = true }
                            .accessibilityIdentifier("meeting.history.report.prepare")
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Library actions").accessibilityIdentifier("meeting.history.actions")
                    .disabled(unavailable)
                }
            }
            .navigationDestination(for: UUID.self) {
                MeetingDetailView(services: services, application: application, id: $0)
            }
            .navigationDestination(isPresented: $showingReport) { RecordingReportView(controller: actions) }
            .sheet(isPresented: $showingBackup) { LibraryBackupView(controller: actions) }
            .modifier(LibraryRestoreModifier(controller: actions))
            .confirmationDialog("Delete this meeting?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete meeting", role: .destructive) {
                    guard let id = pendingDeletion else { return }
                    pendingDeletion = nil; deleting = true
                    Task { _ = await services.deleteMeeting(id: id); deleting = false }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Its audio, transcript, notes, summaries, and answers will be permanently deleted.")
            }
            .screenshotReady(screenshotPrepared)
            .task {
                #if DEBUG
                if let scene = AppScreenshotFixture.scene, scene.isHistory {
                    if scene == .meetingsSearch { query = "Alpha" }
                    await services.library.searchHistory(query)
                    if scene == .meetingsBackup { showingBackup = true }
                    screenshotPrepared = true
                }
                #endif
            }
        }
    }
    private func askToDelete(_ id: UUID) {
        guard !unavailable else { return }
        pendingDeletion = id; confirmingDeletion = true
    }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct MeetingHistoryRow: View {
    let meeting: MeetingRecord
    let content: MeetingContentStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.title).font(.headline)
                .accessibilityIdentifier("meeting.history.title.\(meeting.id.uuidString)")
            Text("\(meeting.createdAt.formatted(date: .omitted, time: .shortened)) · \(meeting.capturedSampleCount / 16_000 / 60) min")
                .font(.subheadline).foregroundStyle(.secondary)
            if let attention {
                Label(attention, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("meeting.history.attention")
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meeting.history.row.\(meeting.id.uuidString)")
        .accessibilityValue(accessibleContentStatus)
    }
    private var attention: String? {
        switch meeting.recordingState {
        case .recording: "Unfinished recording"
        case .interrupted, .failed: "Recording needs review"
        case .recovered: "Recovered audio"
        case .completed: content.transcript == .absent ? "Transcript unavailable" : nil
        }
    }
    private var accessibleContentStatus: String {
        let transcript = content.transcript == .available ? "Transcript available" :
            content.transcript == .absent ? "No transcript" : "Transcript status unavailable"
        let summary = content.summary == .available ? "Summary available" :
            content.summary == .absent ? "Summary not generated" : "Summary status unavailable"
        return "\(transcript). \(summary)."
    }
}
