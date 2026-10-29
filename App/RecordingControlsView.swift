import Foundation
import SwiftUI
import UIKit

/// Capture is owned by RecordingApplication. Switching tabs or opening setup
/// only changes this projection and never releases microphone resources.
@MainActor
struct RecordingControlsView: View {
    let application: RecordingApplication
    var openMeeting: (UUID) -> Void = { _ in }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var timerSize: CGFloat = 36
    @State private var snapshot: RecordingSnapshot?
    @State private var progress: RecordingProgress?
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var commandError: String?
    @State private var showingSetup = false
    @State private var showingPrivacy = false
    @State private var showingNotes = false
    @State private var pendingStoppedMeeting: UUID?
    @State private var screenshotPrepared = false
    #if DEBUG
    @State private var fixtureTranscript: LiveTranscriptSnapshot?
    #endif

    private enum TranscriptAnchor { static let latest = "recording.transcript.latest" }
    private struct TranscriptScrollUpdate: Equatable {
        let visible: Bool
        let sessionID: UUID?
        let lastSegmentID: UUID?
        let partial: String
    }

    private var transcriptScrollUpdate: TranscriptScrollUpdate {
        let transcript = displayedTranscript
        return .init(visible: snapshot?.phase == .recording && !showingNotes && scenePhase == .active,
                     sessionID: transcript?.sessionID, lastSegmentID: transcript?.finalized.last?.id,
                     partial: transcript?.partial ?? "")
    }

    private var displayedTranscript: LiveTranscriptSnapshot? {
        #if DEBUG
        if AppScreenshotFixture.recording { return fixtureTranscript ?? AppScreenshotFixture.transcript }
        #endif
        return application.services?.live.transcript
    }
    private var speechReady: Bool {
        #if DEBUG
        if AppScreenshotFixture.scene == .recordIdle || AppScreenshotFixture.recording { return true }
        #endif
        return application.services?.speechInstalled == true
    }
    private var hasActiveSession: Bool {
        guard let snapshot else { return false }
        return snapshot.cleanupPending || [.preparing, .recording, .stopping].contains(snapshot.phase)
    }
    private var preparing: Bool { isStarting || snapshot?.phase == .preparing }
    private var stopping: Bool { isStopping || snapshot?.phase == .stopping || snapshot?.cleanupPending == true }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    recordingContent
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("recording.content.scroll")
                .task(id: transcriptScrollUpdate) {
                    guard transcriptScrollUpdate.visible else { return }
                    // Let the new text and bottom anchor participate in layout
                    // before scrolling. A newer update cancels this request.
                    await Task.yield()
                    guard !Task.isCancelled, transcriptScrollUpdate.visible else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(TranscriptAnchor.latest, anchor: .bottom)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MinutesStyle.background)
            .navigationTitle(hasActiveSession ? "Recording" : "Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPrivacy = true } label: {
                        Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Recording privacy").accessibilityIdentifier("recording.privacy")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if hasActiveSession || (speechReady && (snapshot?.failure == nil || snapshot?.failure == .modelUnavailable)) {
                    recordingHeader
                }
            }
            .sheet(isPresented: $showingSetup, onDismiss: {
                Task { await application.services?.refreshModels(); await refresh() }
            }) {
                if let controller = application.services?.modelBrowser {
                    ModelSetupSheet(controller: controller, application: application, purpose: .speechRecognition)
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                NavigationStack {
                    MinutesPrivacyView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingPrivacy = false } } }
                }
            }
            .screenshotReady(screenshotPrepared)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            #if DEBUG
            if AppScreenshotFixture.scene?.isRecord == true {
                showingNotes = AppScreenshotFixture.scene == .recordNotes
                await refresh(); screenshotPrepared = true
                if let stream = AppScreenshotFixture.transcriptStream {
                    fixtureTranscript = AppScreenshotFixture.scrollingTranscript(finalCount: 24)
                    // UI tests observe the production scroll view as content
                    // arrives; no microphone, model or persistent rows are used.
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    switch stream {
                    case .finalized:
                        fixtureTranscript = AppScreenshotFixture.scrollingTranscript(finalCount: 25)
                    case .partial:
                        fixtureTranscript = AppScreenshotFixture.scrollingTranscript(finalCount: 24,
                            partial: String(repeating: "Live partial speech continues. ", count: 40) + "Latest partial words.")
                    }
                }
                return
            }
            #endif
            await application.services?.initialize()
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if stopping {
                MinutesProgress(title: "Finishing recording", detail: "Waiting for audio cleanup.")
                if let failure = snapshot?.failure {
                    MinutesMessage(text: String(localized: RecordingIntentReplies.message(for: .blocked(failure))), isError: true)
                }
            } else if snapshot?.phase == .recording {
                activeRecording
            } else if preparing {
                MinutesProgress(title: "Getting ready", detail: "Preparing the microphone and speech model.")
            } else if let failure = snapshot?.failure, failure != .modelUnavailable {
                failureView(failure)
            } else if application.services == nil {
                MinutesEmptyState(title: "Recording unavailable", symbol: "externaldrive.badge.exclamationmark",
                    detail: "Reopen LocalMinutes to load local storage.")
            } else if !speechReady && application.services?.speechSelectionChecked == false {
                MinutesProgress(title: "Checking your speech model", detail: "Restoring your saved selection.")
            } else if !speechReady {
                MinutesEmptyState(title: "Set up transcription", symbol: "waveform",
                    detail: "Install a speech model before your first recording.",
                    actionTitle: "Choose speech model", action: { showingSetup = true },
                    identifier: "recording.modelRequired")
            } else {
                readyToRecord
                if snapshot?.failure == .modelUnavailable {
                    MinutesMessage(text: "The speech model could not be loaded. Try again or choose another model.", isError: true)
                }
            }
            if let commandError { MinutesMessage(text: commandError, isError: true) }
        }
    }

    private var recordingHeader: some View {
        VStack(spacing: 8) {
            if hasActiveSession { stopControl } else { startControl }
            Text(hasActiveSession ? progress?.elapsedSeconds.map { MinutesStyle.duration(seconds: $0) } ?? "—" : "00:00")
                .font(.system(size: timerSize, weight: .regular, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityLabel(hasActiveSession
                    ? progress?.elapsedSeconds.map { "Elapsed \(MinutesStyle.duration(seconds: $0))" } ?? "Elapsed time unavailable"
                    : "Ready to record")
                .accessibilityIdentifier("recording.elapsed")
            if snapshot?.phase == .recording {
                Label("Recording", systemImage: "record.circle.fill")
                    .foregroundStyle(MinutesStyle.recording).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("recording.active")
                Text(transcriptionStatus).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("recording.backlog")
                Picker("While recording", selection: $showingNotes) {
                    Text("Transcript").tag(false)
                    Text("Notes").tag(true)
                }.pickerStyle(.segmented).frame(minHeight: 44)
                    .accessibilityIdentifier("recording.content.tabs")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
        .background(MinutesStyle.background)
    }

    private var readyToRecord: some View {
        VStack(spacing: 20) {
            Text("New meeting").font(.title2.weight(.semibold))
            Button { showingSetup = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech model ready").font(.subheadline.weight(.semibold))
                        Text("Available offline").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                }.minutesCard()
            }
            .buttonStyle(.plain).accessibilityLabel("Speech model ready. Change model")
            Label("Only on this iPhone", systemImage: "lock").font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var activeRecording: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let transcript = displayedTranscript {
                if showingNotes, let services = application.services, let id = transcript.sessionID {
                    ActiveMeetingNotesView(services: services, id: id).id(id)
                } else {
                    ForEach(transcript.finalized) { segment in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(MinutesStyle.timestamp(samples: segment.startSample)).font(.caption).foregroundStyle(.secondary)
                            Text(segment.text).font(.title3).lineSpacing(5).textSelection(.enabled)
                                .accessibilityIdentifier("recording.liveTranscript.\(segment.id.uuidString)")
                        }
                    }
                    if !transcript.partial.isEmpty {
                        Text(transcript.partial).font(.body).lineSpacing(5).foregroundStyle(.secondary)
                            .accessibilityIdentifier("recording.liveTranscript.partial")
                    }
                    if transcript.finalized.isEmpty && transcript.partial.isEmpty { Text("Listening…").foregroundStyle(.secondary) }
                    Color.clear.frame(height: 1).id(TranscriptAnchor.latest).accessibilityHidden(true)
                }
                if transcript.failure != nil {
                    MinutesMessage(text: "Live transcription stopped. Review the saved audio after recording.", isError: true)
                }
            }
        }.privacySensitive()
    }

    private var transcriptionStatus: String {
        switch progress?.status ?? .unknown {
        case .caughtUp: "Transcript is up to date"
        case .processing: "Transcribing on this iPhone"
        case .lagging:
            if let seconds = progress?.backlogSeconds { "Transcript catching up · \(Int(seconds.rounded())) sec behind" }
            else { "Transcript catching up" }
        case .unknown: "Waiting for transcription progress"
        }
    }

    private var startControl: some View {
        VStack(spacing: 12) {
            Button { Task { await start() } } label: {
                Circle().fill(MinutesStyle.recording).frame(width: 66, height: 66)
                    .padding(7).overlay(Circle().strokeBorder(MinutesStyle.recording, lineWidth: 2))
            }
            .buttonStyle(MinutesPressStyle()).disabled(isStarting)
            .accessibilityLabel("Start Recording").accessibilityIdentifier("recording.start")
            Text("Start recording").font(.body.weight(.semibold)).foregroundStyle(MinutesStyle.recording)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(MinutesStyle.background)
    }

    private var stopControl: some View {
        Button { Task { await stop() } } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(MinutesStyle.recording).frame(width: 28, height: 28)
                    .frame(width: 72, height: 72).background(MinutesStyle.recording.opacity(0.1), in: Circle())
                Text(preparing ? "Cancel preparation" : stopping ? "Stopping…" : "Stop recording")
                    .font(.body.weight(.semibold)).foregroundStyle(MinutesStyle.recording)
            }.frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(MinutesPressStyle()).disabled(isStopping)
        .accessibilityLabel("Stop Recording").accessibilityIdentifier("recording.stop")
        .background(MinutesStyle.background)
    }

    @ViewBuilder private func failureView(_ failure: RecordingFailure) -> some View {
        MinutesEmptyState(title: failure == .microphoneDenied ? "Microphone is off" : "Recording needs attention",
            symbol: failure == .microphoneDenied ? "mic.slash" : "exclamationmark.circle",
            detail: failure == .storageFull ? "Free up space on this iPhone, then try again." :
                String(localized: RecordingIntentReplies.message(for: .blocked(failure))))
        if failure == .microphoneDenied || failure == .activityUnavailable {
            Button("Open iPhone Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }.buttonStyle(MinutesButtonStyle())
        }
        Button("Try again") { Task { await start() } }.buttonStyle(MinutesButtonStyle(kind: .secondary))
        if let id = snapshot?.sessionID {
            Button("Review saved meeting") { openMeeting(id) }.frame(minHeight: 44)
        }
    }

    private func refresh() async {
        #if DEBUG
        if AppScreenshotFixture.scene == .recordModelRequired {
            snapshot = .init(phase: .idle, sessionID: nil, readiness: .init(), failure: .modelUnavailable, cleanupPending: false)
            return
        }
        if AppScreenshotFixture.recording {
            snapshot = AppScreenshotFixture.snapshot; progress = AppScreenshotFixture.progress; return
        }
        #endif
        guard let owner = application.owner else { return }
        let latest = await owner.snapshot()
        guard !Task.isCancelled else { return }
        snapshot = latest
        let recorder = application.services?.metrics
        progress = RecordingProgressPresenter.make(recording: latest,
            firstAudioQueuedAtNanoseconds: recorder?.firstAudioQueuedAtNanoseconds,
            observedAtNanoseconds: recorder?.nowNanoseconds() ?? 0, metrics: recorder?.snapshot())
        if latest.phase == .completed, !latest.cleanupPending,
           let pendingStoppedMeeting, latest.sessionID == pendingStoppedMeeting {
            self.pendingStoppedMeeting = nil
            openMeeting(pendingStoppedMeeting)
        }
    }

    private func start() async {
        guard !isStarting, !hasActiveSession else { return }
        isStarting = true; commandError = nil; pendingStoppedMeeting = nil
        defer { isStarting = false }
        do {
            let outcome = try await application.perform(.start(UUID()))
            switch outcome {
            case .starting, .recording: break
            default: commandError = String(localized: RecordingIntentReplies.message(for: outcome))
            }
        }
        catch { commandError = "Recording could not start. Review permissions and try again." }
        await refresh()
        if snapshot?.failure != nil { commandError = nil }
    }
    private func stop() async {
        guard !isStopping, let sessionID = snapshot?.sessionID else { return }
        isStopping = true; commandError = nil; pendingStoppedMeeting = sessionID
        defer { isStopping = false }
        do {
            let outcome = try await application.perform(.stop(expectedSessionID: sessionID))
            switch outcome {
            case .stopped, .cleanupPending: break
            default: commandError = String(localized: RecordingIntentReplies.message(for: outcome))
            }
        }
        catch { commandError = "Recording could not stop yet. Try again." }
        await refresh()
    }
}
