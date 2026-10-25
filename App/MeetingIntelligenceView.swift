#if os(iOS)
import Foundation
import Observation
import SwiftUI

struct MeetingIntelligenceCitation: Identifiable {
    let id: String
    let sourceID: UUID
    let startSample: Int64
    let endSample: Int64
    let quote: String
    let asrRevision: String

    var time: String {
        let seconds = startSample / 16_000
        return String(format: "%02lld:%02lld:%02lld", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
    }
}

/// One detail screen owns one immutable meeting identity. Model work is retained
/// by app services; leaving this screen requests only this controller's work stop.
@MainActor @Observable
final class MeetingIntelligenceController {
    let meetingID: UUID
    private let services: LocalMinutesServices
    private(set) var summary: StoredGeneratedDocument?
    private(set) var answers: [StoredGeneratedDocument] = []
    var summaryText = ""
    var question = ""
    private(set) var message: String?
    private(set) var errorMessage: String?
    private(set) var modelRequired = false
    private(set) var isRunning = false
    private(set) var isSaving = false
    private(set) var cleanupPending = false
    private(set) var isResetting = false
    private(set) var editConflict = false
    private(set) var citations: [UUID: [MeetingIntelligenceCitation]] = [:]
    @ObservationIgnored private var sources: [UUID: StoredTranscriptSegment] = [:]
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var request: IntelligenceRequest?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var cancellation: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var resetSummaryTask: Task<Void, Never>?
    @ObservationIgnored private var saveOperation: (id: UUID, task: Task<Bool, Never>)?

    init(services: LocalMinutesServices, meetingID: UUID) {
        self.services = services
        self.meetingID = meetingID
    }

    var busy: Bool { isRunning || cleanupPending || isResetting }
    var hasSummaryEdits: Bool { summary.map { summaryText != $0.editedText } ?? false }

    func load() async {
        let token = UUID()
        loadID = token
        do {
            let summaries = try await services.store.generatedDocuments(meetingID: meetingID, kind: .summary, limit: 1)
            let savedAnswers = try await services.store.generatedDocuments(meetingID: meetingID, kind: .questionAnswer, limit: 50)
            let rows = summaries + savedAnswers
            let transcript = try await services.store.transcript(meetingID: meetingID)
            guard loadID == token else { return }
            sources = Dictionary(uniqueKeysWithValues: transcript.map { ($0.id, $0) })
            if !hasSummaryEdits && !isSaving {
                summary = rows.first { $0.kind == .summary }
                summaryText = summary?.editedText ?? ""
            }
            answers = rows.filter { $0.kind == .questionAnswer }
            citations = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, validatedCitations(in: $0)) })
        } catch {
            guard loadID == token else { return }
            errorMessage = "Saved generated notes could not be opened. Your original notes and transcript are unchanged."
        }
    }

    func summaryChanged() {
        debounce?.cancel()
        guard hasSummaryEdits, !busy, !editConflict else { return }
        debounce = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            _ = await flushSummaryEdits()
        }
    }

    /// Serialize CAS saves. Each write captures the original document/meeting
    /// and revision; a late completion can never write another screen's text.
    @discardableResult
    func flushSummaryEdits() async -> Bool {
        debounce?.cancel()
        while true {
            if let existing = saveOperation {
                guard await existing.task.value else { return false }
                continue
            }
            guard let document = summary, summaryText != document.editedText else { return true }
            guard !editConflict else { return false }
            let text = summaryText
            let token = UUID()
            isSaving = true
            let task = Task { @MainActor in
                defer {
                    if self.saveOperation?.id == token {
                        self.saveOperation = nil
                        self.isSaving = false
                    }
                }
                do {
                    let saved = try await self.services.store.saveGeneratedDocumentEdit(
                        id: document.id, meetingID: self.meetingID, text: text,
                        expectedRevision: document.editRevision,
                        modifiedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970))
                    guard self.summary?.id == document.id else { return false }
                    self.summary = saved
                    self.message = "Summary edit saved on this iPhone."
                    return true
                } catch GeneratedDocumentStoreError.staleRevision {
                    self.editConflict = true
                    self.errorMessage = "This summary changed elsewhere. Copy your draft before reopening the saved version."
                    return false
                } catch {
                    self.errorMessage = "The summary edit could not be saved. Keep this meeting open and tap Save summary to retry."
                    return false
                }
            }
            saveOperation = (token, task)
            guard await task.value else { return false }
        }
    }

    func reopenSavedSummary() {
        guard !busy, !isSaving else { return }
        debounce?.cancel()
        editConflict = false
        errorMessage = nil
        if let summary { summaryText = summary.editedText }
        Task { await load() }
    }

    func generateSummary() { begin(.summary) }

    func startFreshSummary() {
        guard !busy, !isSaving, !services.maintainingLibrary else { return }
        guard services.intelligence != nil else { modelRequired = true; return }
        isResetting = true
        resetSummaryTask = Task { @MainActor in
            defer { self.isResetting = false; self.resetSummaryTask = nil }
            guard await self.flushSummaryEdits() else { return }
            do {
                try Task.checkCancellation()
                try await self.services.summaryCheckpoints.remove(jobID: self.meetingID, meetingID: self.meetingID)
                try Task.checkCancellation()
                self.isResetting = false
                self.begin(.summary)
            } catch is CancellationError {} catch {
                self.errorMessage = "Saved progress could not be cleared. The existing summary and original notes are still available."
            }
        }
    }

    func ask() {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard question.utf8.count <= 2_048 else {
            errorMessage = "Please shorten your question to 2,048 bytes or fewer."
            return
        }
        begin(.question(question))
    }

    private func begin(_ kind: IntelligenceOperation) {
        guard request == nil, !isRunning, !cleanupPending, !isResetting, !services.maintainingLibrary else { return }
        let owned = IntelligenceRequest(meetingID: meetingID, operation: kind,
            createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970))
        request = owned
        isRunning = true
        modelRequired = false
        errorMessage = nil
        message = "Preparing local generation…"
        operation = Task { @MainActor in
            do {
                guard await self.flushSummaryEdits() else {
                    self.finish(owned)
                    return
                }
                await self.services.initialize()
                try Task.checkCancellation()
                guard self.services.startup.state == .ready else {
                    self.errorMessage = "Saved meetings are not ready. Reopen LocalMinutes and try again."
                    self.finish(owned)
                    return
                }
                guard let intelligence = self.services.intelligence else {
                    self.modelRequired = true
                    self.message = nil
                    self.finish(owned)
                    return
                }
                self.message = "Working locally on this meeting…"
                let saved = try await intelligence.run(owned)
                guard self.request?.id == owned.id, saved.meetingID == self.meetingID else { return }
                if saved.kind == .summary {
                    self.summary = saved
                    self.summaryText = saved.editedText
                    self.editConflict = false
                }
                self.message = "Saved on this iPhone. Review generated content against its sources."
                await self.load()
            } catch is CancellationError {
                self.message = "Generation cancelled."
            } catch ModelInstallationError.modelMissing {
                self.modelRequired = true
                self.message = nil
            } catch HeavyModelAdmissionError.busy {
                self.errorMessage = "Stop recording or wait for the current local model task to finish."
            } catch IntelligenceSessionError.busy {
                self.errorMessage = "Stop recording or wait for the current local model task to finish."
            } catch SummaryCheckpointError.identityMismatch {
                self.errorMessage = "Saved summary progress uses different notes, model or settings. Choose Start a fresh summary to discard that progress and use this meeting's current content."
            } catch {
                // Model output and database paths never appear in diagnostics.
                self.errorMessage = "A supported result could not be generated. Check that the model is installed and this meeting has a finalized transcript, then try again."
            }
            self.finish(owned)
        }
    }

    private func finish(_ owned: IntelligenceRequest) {
        guard request?.id == owned.id else { return }
        isRunning = false
        operation = nil
        cleanupPending = services.heavyAdmission?.snapshot().lease?.requestID == owned.id
        if cleanupPending {
            errorMessage = "Local model cleanup is pending. Tap Cancel to retry before starting another task."
        } else {
            request = nil
        }
    }

    func cancel() {
        resetSummaryTask?.cancel()
        guard let owned = request, cancellation == nil else { return }
        operation?.cancel()
        message = "Cancelling and releasing the local model…"
        cancellation = Task { @MainActor in
            defer { self.cancellation = nil }
            do {
                try await self.services.intelligence?.cancelAndDrain(requestID: owned.id)
                if self.request?.id == owned.id && !self.isRunning {
                    self.cleanupPending = false
                    self.request = nil
                    self.errorMessage = nil
                    self.message = "Generation cancelled."
                }
            } catch IntelligenceSessionError.staleRequest {
                // This may be a cancellation during storage/startup preparation.
                // The cancelled operation checks cancellation before native load.
            } catch {
                if self.request?.id == owned.id {
                    self.errorMessage = "Model cleanup is pending. Tap Cancel to retry."
                }
            }
        }
    }

    func leaveMeeting() {
        debounce?.cancel()
        cancel()
        // Unstructured save survives view removal and remains bound to this UUID.
        Task { _ = await flushSummaryEdits() }
    }

    private func validatedCitations(in document: StoredGeneratedDocument) -> [MeetingIntelligenceCitation] {
        guard document.meetingID == meetingID,
              let object = try? JSONSerialization.jsonObject(with: document.originalJSON) as? [String: Any],
              let rawMeeting = object["meeting_id"] as? String,
              UUID(uuidString: rawMeeting) == meetingID else { return [] }
        var raw = object["evidence"] as? [[String: Any]] ?? []
        for key in ["summary_points", "decisions", "actions"] {
            for point in object[key] as? [[String: Any]] ?? [] {
                raw += point["evidence"] as? [[String: Any]] ?? []
            }
        }
        var seen: Set<String> = []
        return raw.compactMap { value in
            guard let id = value["source_id"] as? String, let sourceID = UUID(uuidString: id),
                  let source = sources[sourceID], source.meetingID == meetingID,
                  let start = value["start_sample"] as? NSNumber,
                  let end = value["end_sample"] as? NSNumber,
                  start.doubleValue == Double(start.int64Value), end.doubleValue == Double(end.int64Value),
                  start.int64Value >= source.startSample, end.int64Value <= source.endSample,
                  end.int64Value > start.int64Value,
                  let quote = value["quote"] as? String, !quote.isEmpty,
                  Data(source.text.utf8).range(of: Data(quote.utf8)) != nil else { return nil }
            let key = "\(id):\(start.int64Value):\(end.int64Value):\(quote)"
            guard seen.insert(key).inserted else { return nil }
            return MeetingIntelligenceCitation(id: key, sourceID: sourceID,
                startSample: start.int64Value, endSample: end.int64Value,
                quote: quote, asrRevision: source.modelRevision)
        }
    }

    var exportText: String? {
        guard summary != nil || !answers.isEmpty else { return nil }
        var sections = ["LocalMinutes — generated content", "Meeting: \(meetingID.uuidString)"]
        if let summary {
            sections += ["Summary", summary.editedText, provenance(summary)]
            sections += exportCitations(summary.id)
        }
        for answer in answers {
            sections += ["Question: \(answer.question ?? "")", answer.editedText, provenance(answer)]
            sections += exportCitations(answer.id)
        }
        return sections.joined(separator: "\n\n")
    }

    private func provenance(_ document: StoredGeneratedDocument) -> String {
        "Model: \(document.modelRevision) · Prompt: \(document.promptVersion) · Edit revision: \(document.editRevision)"
    }

    private func exportCitations(_ documentID: UUID) -> [String] {
        (citations[documentID] ?? []).map {
            "[\($0.time)] \($0.quote)\nSource: \($0.sourceID.uuidString), samples \($0.startSample)..<\($0.endSample), ASR \($0.asrRevision)"
        }
    }
}

@MainActor
struct MeetingIntelligenceView: View {
    @Bindable var controller: MeetingIntelligenceController
    let playCitation: @MainActor (MeetingCitationNavigationTarget) async -> Void
    @State private var confirmingFreshSummary = false

    var body: some View {
        Group {
            Section("Summary") {
                if controller.summary != nil {
                    TextEditor(text: $controller.summaryText)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Generated meeting summary")
                        .accessibilityIdentifier("meeting.generatedSummary.editor")
                        .disabled(controller.busy)
                        .onChange(of: controller.summaryText) { _, _ in controller.summaryChanged() }
                    if controller.isSaving { Text("Saving summary…").font(.caption) }
                    Button("Save summary") { Task { _ = await controller.flushSummaryEdits() } }
                        .disabled(controller.busy || !controller.hasSummaryEdits || controller.isSaving)
                    if controller.editConflict {
                        Button("Reopen saved summary", role: .destructive) { controller.reopenSavedSummary() }
                    }
                    if let document = controller.summary {
                        provenance(document)
                        citationRows(document)
                    }
                } else {
                    Text("Generate a local summary from this meeting's finalized transcript and original notes.")
                        .foregroundStyle(.secondary)
                }
                Button(controller.summary == nil ? "Generate or resume summary" : "Generate or resume another summary") {
                    controller.generateSummary()
                }
                .disabled(controller.busy || controller.editConflict)
                .accessibilityIdentifier("meeting.generatedSummary.generate")
                Button("Start a fresh summary…", role: .destructive) { confirmingFreshSummary = true }
                    .disabled(controller.busy || controller.editConflict || controller.isSaving)
            }
            Section("Ask this meeting") {
                TextField("Ask a question about this meeting", text: $controller.question, axis: .vertical)
                    .disabled(controller.busy)
                    .accessibilityIdentifier("meeting.qa.question")
                Button("Ask") { controller.ask() }
                    .disabled(controller.busy || controller.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("meeting.qa.ask")
                ForEach(controller.answers) { answer in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(answer.question ?? "Saved question").font(.headline).textSelection(.enabled)
                        Text(answer.editedText).textSelection(.enabled)
                            .accessibilityIdentifier("meeting.qa.answer")
                        provenance(answer)
                        citationRows(answer)
                    }
                    .padding(.vertical, 5)
                }
            }
            Section {
                if controller.isRunning {
                    ProgressView(controller.message ?? "Working locally…")
                        .accessibilityIdentifier("meeting.intelligence.running")
                } else if let message = controller.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if controller.busy { Button("Cancel", role: .cancel) { controller.cancel() } }
                if controller.modelRequired {
                    Text("Download the summary model to summarize this meeting or ask questions.")
                        .accessibilityIdentifier("meeting.intelligence.modelRequired")
                }
                if let error = controller.errorMessage { Text(error).foregroundStyle(.red) }
                if let text = controller.exportText {
                    ShareLink("Share generated notes and answers", item: text)
                        .disabled(controller.hasSummaryEdits || controller.isSaving)
                }
                Text("Generated content is separate from original notes and transcripts. Review it before sharing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Start summary from the beginning?", isPresented: $confirmingFreshSummary, titleVisibility: .visible) {
            Button("Discard progress and generate", role: .destructive) { controller.startFreshSummary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Discard unfinished summary progress for this meeting and generate again. Saved summaries, original notes and the transcript stay available.")
        }
    }

    private func provenance(_ document: StoredGeneratedDocument) -> some View {
        VStack(alignment: .leading) {
            Text("Model \(document.modelRevision) · \(document.promptVersion)")
            if document.editRevision > 0 {
                Text("Edited copy · citations describe the original generated result.")
            }
        }.font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func citationRows(_ document: StoredGeneratedDocument) -> some View {
        ForEach(controller.citations[document.id] ?? []) { citation in
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(citation.quote)”").font(.callout).textSelection(.enabled)
                Button("Play source at \(citation.time)") {
                    guard let target = controller.citationNavigationTarget(documentID: document.id, citationID: citation.id) else { return }
                    Task { await playCitation(target) }
                }.font(.caption)
                Text("Transcript source \(citation.sourceID.uuidString)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
