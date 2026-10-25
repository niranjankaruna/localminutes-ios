import Foundation
import SwiftUI

/// A projection of the app-owned coordinator. Leaving this screen only stops
/// its snapshot polling; recording resources remain owned by the application.
@MainActor
struct RecordingControlsView: View {
    let application: RecordingApplication
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: RecordingSnapshot?
    @State private var progress: RecordingProgress?
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var commandError: String?

    private var displayedTranscript: LiveTranscriptSnapshot? {
        #if DEBUG
        if AppScreenshotFixture.recording { return AppScreenshotFixture.transcript }
        #endif
        return application.services?.live.transcript
    }

    private var hasActiveSession: Bool {
        guard let snapshot else { return false }
        return snapshot.cleanupPending ||
            [.preparing, .recording, .stopping].contains(snapshot.phase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Your meetings stay on this iPhone.")
                        .font(.title2.weight(.semibold))
                    Text("Microphone permission lets LocalMinutes record meetings you explicitly start. Allow access when prompted; you can change permission in iPhone Settings.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("recording.microphoneExplanation")
                    Text("A Live Activity shows recording status and a Stop control on the Lock Screen. Enable Live Activities for LocalMinutes in iPhone Settings if needed.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("recording.liveActivityExplanation")
                    status
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if snapshot?.phase == .recording {
                        recordingProgress
                    }
                    VStack(spacing: 12) {
                        Button {
                            Task { await start() }
                        } label: {
                            Label("Start Recording", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isStarting || hasActiveSession)
                        .accessibilityIdentifier("recording.start")

                        Button {
                            Task { await stop() }
                        } label: {
                            Label("Stop Recording", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isStopping || !hasActiveSession)
                        .accessibilityIdentifier("recording.stop")
                    }
                    .controlSize(.large)
                    if let transcript = displayedTranscript, transcript.sessionID != nil {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            Text("Live transcript").font(.headline)
                            Text("\(transcript.receivedSampleCount / 16_000) seconds transcribed locally")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(transcript.finalized) { segment in
                                Text(segment.text).textSelection(.enabled)
                            }
                            if !transcript.partial.isEmpty {
                                Text(transcript.partial).italic().foregroundStyle(.secondary)
                            }
                            if transcript.failure != nil {
                                Text("Live transcription stopped with an error. Review this meeting before relying on its transcript.")
                                    .foregroundStyle(.red)
                            }
                            if let services = application.services, let id = transcript.sessionID {
                                ActiveMeetingNotesView(services: services, id: id).id(id)
                            }
                        }
                        .privacySensitive()
                    }
                    if let commandError {
                        Text(commandError).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("LocalMinutes")
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var recordingProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let elapsed = progress?.elapsedSeconds {
                Text("Elapsed \(elapsedTime(elapsed))")
                    .monospacedDigit()
                    .accessibilityIdentifier("recording.elapsed")
            } else {
                Text("Elapsed time unavailable")
                    .accessibilityIdentifier("recording.elapsed")
            }
            Group {
                switch progress?.status ?? .unknown {
                case .caughtUp:
                    Text("Transcription is caught up.")
                        .foregroundStyle(.secondary)
                case .processing:
                    if let seconds = progress?.backlogSeconds {
                        Text("Processing audio: about \(seconds, specifier: "%.1f") seconds queued.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Transcription progress is not available yet.")
                            .foregroundStyle(.secondary)
                    }
                case .lagging:
                    if let seconds = progress?.backlogSeconds {
                        Text("Transcription is behind: about \(seconds, specifier: "%.1f") seconds queued.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Transcription progress is not available yet.")
                            .foregroundStyle(.secondary)
                    }
                case .unknown:
                    Text("Transcription progress is not available yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .accessibilityIdentifier("recording.backlog")
        }
    }

    private func elapsedTime(_ seconds: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }

    @ViewBuilder
    private var status: some View {
        if isStopping || snapshot?.cleanupPending == true || snapshot?.phase == .stopping {
            Text("Stopping recording…")
        } else if snapshot?.phase == .recording {
            Label("Recording is active.", systemImage: "waveform")
                .accessibilityIdentifier("recording.active")
        } else if isStarting || snapshot?.phase == .preparing {
            ProgressView("Preparing recording…")
        } else if let failure = snapshot?.failure {
            Text(String(localized: RecordingIntentReplies.message(for: .blocked(failure))))
                .accessibilityIdentifier(failure == .modelUnavailable ?
                                        "recording.modelRequired" : "recording.status")
        } else if let outcome = application.lastOutcome,
                  outcome != .recording && outcome != .starting {
            Text(String(localized: RecordingIntentReplies.message(for: outcome)))
                .accessibilityIdentifier(outcome == .blocked(.modelUnavailable) ?
                                        "recording.modelRequired" : "recording.status")
        } else {
            Text("Start a meeting when you are ready.")
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        #if DEBUG
        if AppScreenshotFixture.recording {
            snapshot = AppScreenshotFixture.snapshot
            progress = AppScreenshotFixture.progress
            return
        }
        #endif
        guard let owner = application.owner else { return }
        let latest = await owner.snapshot()
        guard !Task.isCancelled else { return }
        snapshot = latest
        let recorder = application.services?.metrics
        let origin = recorder?.firstAudioQueuedAtNanoseconds
        let sampled = recorder?.snapshot()
        let observedAt = recorder?.nowNanoseconds() ?? 0
        progress = RecordingProgressPresenter.make(recording: latest,
            firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: observedAt, metrics: sampled)
    }

    private func start() async {
        guard !isStarting else { return }
        isStarting = true
        commandError = nil
        defer { isStarting = false }
        do { _ = try await application.perform(.start(UUID())) }
        catch { commandError = "The recording command needs attention. Review its status." }
        await refresh()
    }

    private func stop() async {
        guard !isStopping, let sessionID = snapshot?.sessionID else { return }
        isStopping = true
        commandError = nil
        defer { isStopping = false }
        do { _ = try await application.perform(.stop(expectedSessionID: sessionID)) }
        catch { commandError = "The recording command needs attention. Review its status." }
        await refresh()
    }
}
