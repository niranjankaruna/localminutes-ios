#if os(iOS)
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class LibraryActionsController {
    let application: RecordingApplication
    var choosingBackup = false
    var confirmingRestore = false
    private(set) var backupURL: URL?
    private(set) var report: String?
    private(set) var working = false
    private(set) var message: String?
    private var restoreURL: URL?

    init(application: RecordingApplication) { self.application = application }
    var unavailable: Bool {
        working || application.isRestoringLibrary || application.services?.maintainingLibrary == true
    }
    func prepareNewBackup() {
        guard !unavailable else { return }
        backupURL = nil
        message = nil
    }
    func createBackup() async {
        #if DEBUG
        if let scene = AppScreenshotFixture.scene, [.meetingsBackupPreparing, .meetingsBackupFailure].contains(scene) {
            prepareScreenshotPresentation(); return
        }
        #endif
        guard !unavailable else { return }
        working = true; message = nil
        defer { working = false }
        do { backupURL = try await application.exportLibraryBackup() }
        catch { message = "Stop recording, playback, and processing, then try again." }
    }
    func chooseBackup(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            restoreURL = urls.first
            confirmingRestore = restoreURL != nil
        case .failure: message = "The backup folder could not be opened."
        }
    }
    func cancelRestore() { restoreURL = nil }
    func restore() async {
        guard !unavailable, let url = restoreURL else { return }
        restoreURL = nil; working = true; message = nil
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            working = false
        }
        do {
            try await application.restoreLibrary(from: url)
            message = "Your library is ready. The previous library is retained."
        } catch {
            message = "The backup could not be restored. Your previous library is available. Stop other work and check the backup folder."
        }
    }
    func prepareReport() {
        guard !unavailable else { return }
        message = nil
        do {
            guard let bytes = try application.services?.exportEnduranceMetrics(),
                  let text = String(data: bytes, encoding: .utf8) else {
                message = "No recording report is available yet."
                return
            }
            report = text
        } catch { message = "The recording report could not be prepared yet." }
    }

    #if DEBUG
    func prepareScreenshotPresentation() {
        switch AppScreenshotFixture.scene {
        case .meetingsBackupPreparing: working = true
        case .meetingsBackupFailure: message = "The backup could not be prepared. Stop recording and try again."
        case .meetingsRestoreFailure: message = "The backup could not be restored. Your previous library is available."
        default: break
        }
    }
    #endif
}

struct LibraryRestoreModifier: ViewModifier {
    @Bindable var controller: LibraryActionsController
    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $controller.choosingBackup, allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                Task { @MainActor in controller.chooseBackup(result) }
            }
            .alert("Restore this backup?", isPresented: $controller.confirmingRestore) {
                Button("Restore backup") { Task { await controller.restore() } }
                    .accessibilityIdentifier("meeting.history.backup.restore.confirm")
                Button("Cancel", role: .cancel) { controller.cancelRestore() }
            } message: {
                Text("This becomes your active library. The previous library is retained, and installed models stay available.")
            }
    }
}

struct LibraryBackupView: View {
    @Bindable var controller: LibraryActionsController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if controller.working {
                        MinutesProgress(title: "Preparing backup")
                            .accessibilityIdentifier("meeting.history.backup.progress")
                    } else if let url = controller.backupURL {
                        MinutesEmptyState(title: "Backup is ready", symbol: "checkmark.shield",
                            detail: "Includes audio, transcripts, notes, summaries, and answers.")
                        ShareLink(item: url) { Label("Save or share backup", systemImage: "square.and.arrow.up") }
                            .buttonStyle(MinutesButtonStyle())
                            .accessibilityLabel("Save or share library backup")
                            .accessibilityIdentifier("meeting.history.backup.share")
                    }
                    if let message = controller.message {
                        MinutesMessage(text: message, isError: controller.backupURL == nil)
                            .accessibilityIdentifier("meeting.history.backup.error")
                        if controller.backupURL == nil {
                            Button("Try again") { Task { await controller.createBackup() } }
                                .buttonStyle(MinutesButtonStyle())
                                .accessibilityIdentifier("meeting.history.backup.retry")
                        }
                    }
                }.frame(maxWidth: 440).padding(MinutesStyle.pageInset).frame(maxWidth: .infinity)
            }
            .background(MinutesStyle.background)
            .navigationTitle("Back up meetings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .screenshotReady(!controller.working && controller.backupURL != nil)
            .task { if controller.backupURL == nil { await controller.createBackup() } }
        }.minutesSheet(compact: true)
    }
}

struct RecordingReportView: View {
    @Bindable var controller: LibraryActionsController
    var body: some View {
        List {
            Section {
                Text("Observed recording and transcription performance.").foregroundStyle(.secondary)
                    .accessibilityIdentifier("meeting.history.report.description")
                if let report = controller.report {
                    ShareLink(item: report) { Label("Share report", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("meeting.history.report.share")
                } else if let message = controller.message { Text(message) }
                Button("Prepare recording report") { controller.prepareReport() }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("meeting.history.report.prepare")
                    .disabled(controller.unavailable)
            } footer: {
                Text("Sampled measurements are not a guarantee of recording performance.")
            }
        }
        .minutesList().navigationTitle("Recording report").navigationBarTitleDisplayMode(.inline)
        .task { controller.prepareReport() }
    }
}
#endif
