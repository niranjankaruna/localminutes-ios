import Foundation
import SwiftUI

/// A projection of the app-owned coordinator. Leaving this screen only stops
/// its snapshot polling; recording resources remain owned by the application.
@MainActor
struct RecordingControlsView: View {
    let application: RecordingApplication
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: RecordingSnapshot?
    @State private var isStarting = false
    @State private var isStopping = false
    @State private var commandError: String?

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
                    status
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    if let live = application.services?.live,
                       live.transcript.sessionID != nil {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            Text("Live transcript").font(.headline)
                            Text("\(live.transcript.receivedSampleCount / 16_000) seconds transcribed locally")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(live.transcript.finalized) { segment in
                                Text(segment.text).textSelection(.enabled)
                            }
                            if !live.transcript.partial.isEmpty {
                                Text(live.transcript.partial).italic().foregroundStyle(.secondary)
                            }
                            if live.transcript.failure != nil {
                                Text("Live transcription stopped with an error. Review this meeting before relying on its transcript.")
                                    .foregroundStyle(.red)
                            }
                            if let services = application.services, let id = live.transcript.sessionID {
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
        guard let owner = application.owner else { return }
        let latest = await owner.snapshot()
        guard !Task.isCancelled else { return }
        snapshot = latest
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
