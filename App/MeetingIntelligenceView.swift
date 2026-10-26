#if os(iOS)
import Foundation
import Observation
import SwiftUI
import UIKit

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
    var answerDrafts: [UUID: String] = [:]
    private(set) var savingAnswerIDs: Set<UUID> = []
    private(set) var answerEditConflicts: Set<UUID> = []
    private(set) var answerSaveErrors: [UUID: String] = [:]
    @ObservationIgnored private var sources: [UUID: StoredTranscriptSegment] = [:]
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var request: IntelligenceRequest?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var cancellation: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var resetSummaryTask: Task<Void, Never>?
    @ObservationIgnored private var saveOperation: (id: UUID, task: Task<Bool, Never>)?
    @ObservationIgnored private var answerSaveOperations: [UUID: (id: UUID, task: Task<Bool, Never>)] = [:]

    init(services: LocalMinutesServices, meetingID: UUID) {
        self.services = services
        self.meetingID = meetingID
    }

    var busy: Bool { isRunning || cleanupPending || isResetting }
    func modelSelectionChanged() {
        if services.summaryInstalled { modelRequired = false }
    }
    #if DEBUG
    func prepareScreenshotState() {
        if AppScreenshotFixture.scene == .meetingModelRequired { modelRequired = true }
    }
    #endif
    var hasSummaryEdits: Bool { summary.map { summaryText != $0.editedText } ?? false }
    var hasAnswerEdits: Bool {
        answers.contains { answer in answerDrafts[answer.id].map { $0 != answer.editedText } == true }
    }

    /// Each saved display copy retains its original document, meeting and CAS
    /// revision. Concurrent callers join the same write, then drain newer text.
    func flushAnswerEdits(documentID: UUID) async -> Bool {
        while true {
            if let existing = answerSaveOperations[documentID] {
                guard await existing.task.value else { return false }
                continue
            }
            guard let document = answers.first(where: { $0.id == documentID && $0.meetingID == meetingID }),
                  document.kind == .questionAnswer else { return false }
            guard !answerEditConflicts.contains(documentID) else { return false }
            guard let text = answerDrafts[documentID], text != document.editedText else { return true }
            let token = UUID()
            savingAnswerIDs.insert(documentID)
            let task = Task { @MainActor in
                defer {
                    if self.answerSaveOperations[documentID]?.id == token {
                        self.answerSaveOperations[documentID] = nil
                        self.savingAnswerIDs.remove(documentID)
                    }
                }
                do {
                    let saved = try await self.services.store.saveGeneratedDocumentEdit(id: document.id,
                        meetingID: self.meetingID, text: text, expectedRevision: document.editRevision,
                        modifiedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970))
                    guard let index = self.answers.firstIndex(where: { $0.id == document.id }) else { return false }
                    self.answers[index] = saved
                    self.answerSaveErrors[documentID] = nil
                    return true
                } catch GeneratedDocumentStoreError.staleRevision {
                    self.answerEditConflicts.insert(documentID)
                    self.answerSaveErrors[documentID] = "This answer changed elsewhere. Copy your draft before reopening the saved version."
                    return false
                } catch {
                    self.answerSaveErrors[documentID] = "The answer edit could not be saved. Keep this meeting open and tap Save answer to retry."
                    return false
                }
            }
            answerSaveOperations[documentID] = (token, task)
            guard await task.value else { return false }
        }
    }

    func flushAllAnswerEdits() async -> Bool {
        var saved = true
        for id in answers.map(\.id) {
            if !(await flushAnswerEdits(documentID: id)) { saved = false }
        }
        return saved
    }

    func reopenSavedAnswer(documentID: UUID) async {
        guard !busy, !savingAnswerIDs.contains(documentID),
              answers.contains(where: { $0.id == documentID && $0.meetingID == meetingID }) else { return }
        let draft = answerDrafts[documentID]
        do {
            let rows = try await services.store.generatedDocuments(meetingID: meetingID, kind: .questionAnswer, limit: 50)
            guard answerDrafts[documentID] == draft, !savingAnswerIDs.contains(documentID),
                  let index = answers.firstIndex(where: { $0.id == documentID }) else { return }
            guard let saved = rows.first(where: { $0.id == documentID }) else { throw GeneratedDocumentStoreError.notFound }
            answers[index] = saved
            answerDrafts[documentID] = saved.editedText
            answerEditConflicts.remove(documentID)
            answerSaveErrors[documentID] = nil
        } catch {
            answerSaveErrors[documentID] = "The saved answer could not be reopened. Your local draft is still available."
        }
    }

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
            let retained = answers.filter { document in
                savingAnswerIDs.contains(document.id) || answerEditConflicts.contains(document.id)
                    || answerDrafts[document.id].map { $0 != document.editedText } == true
                    // A concurrent save can finish while this load awaits its
                    // transcript read. Never restore that older database read.
                    || savedAnswers.first(where: { $0.id == document.id }).map { $0.editRevision < document.editRevision } == true
            }
            let retainedByID = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
            answers = savedAnswers.map { retainedByID[$0.id] ?? $0 }
            answers += retained.filter { document in !savedAnswers.contains(where: { $0.id == document.id }) }
            for answer in answers where retainedByID[answer.id] == nil {
                answerDrafts[answer.id] = answer.editedText
            }
            citations = Dictionary(uniqueKeysWithValues: (summaries + answers).map { ($0.id, validatedCitations(in: $0)) })
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
                guard await self.flushAllAnswerEdits() else {
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
            } catch AppleFoundationRuntimeError.unavailable(let availability) {
                self.message = nil
                self.errorMessage = availability.explanation
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
        Task {
            _ = await flushSummaryEdits()
            _ = await flushAllAnswerEdits()
        }
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
    let content: MeetingContentTab
    let chooseModel: () -> Void
    let playCitation: @MainActor (MeetingCitationNavigationTarget) async -> Void
    @State private var editingSummary = false
    @State private var editingAnswer: StoredGeneratedDocument?
    @State private var showingDetails = false
    @State private var confirmingFreshSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if controller.busy {
                MinutesProgress(title: content == .ask ? "Finding an answer" : "Summarizing",
                    detail: controller.cleanupPending ? "Finishing the current operation…" : "Working on this iPhone.",
                    cancel: controller.cancel)
                    .accessibilityIdentifier("meeting.intelligence.running")
            }
            if controller.modelRequired {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose a model for summaries and answers.")
                        .accessibilityIdentifier("meeting.intelligence.modelRequired")
                    Button("Choose model", action: chooseModel)
                        .buttonStyle(MinutesButtonStyle())
                        .accessibilityIdentifier("meeting.intelligence.chooseModel")
                }.minutesCard()
            }
            if let error = controller.errorMessage { MinutesMessage(text: error, isError: true) }
            if content == .summary { summaryContent } else { questionsContent }
        }
        .sheet(isPresented: $editingSummary) { SummaryEditorView(controller: controller) }
        .sheet(item: $editingAnswer) { AnswerEditorView(controller: controller, answer: $0) }
        .sheet(isPresented: $showingDetails) {
            if let document = controller.summary { GeneratedDetailsView(document: document) }
        }
        .confirmationDialog("Start a fresh summary?", isPresented: $confirmingFreshSummary, titleVisibility: .visible) {
            Button("Start fresh", role: .destructive) { controller.startFreshSummary() }
                .accessibilityIdentifier("meeting.summary.reset.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unfinished progress is discarded. Saved summaries, notes, and the transcript stay available.")
        }
    }

    @ViewBuilder private var summaryContent: some View {
        if let document = controller.summary {
            SummaryReadingView(document: document, text: controller.summaryText)
            citations(document)
            HStack {
                Button("Edit summary") { editingSummary = true }
                    .frame(minHeight: 44).accessibilityIdentifier("meeting.summary.edit")
                    .disabled(controller.busy)
                Spacer()
                Button("Details") { showingDetails = true }.frame(minHeight: 44)
            }
        } else if !controller.busy && !controller.modelRequired {
            MinutesEmptyState(title: "No summary yet", symbol: "sparkles",
                              detail: "Create a summary from this meeting.")
            Button("Summarize meeting") { controller.generateSummary() }
                .buttonStyle(MinutesButtonStyle()).accessibilityIdentifier("meeting.generatedSummary.generate")
                .disabled(controller.editConflict)
        }
        Menu {
            Button(controller.summary == nil ? "Generate or resume summary" : "Generate again") { controller.generateSummary() }
                .accessibilityIdentifier(controller.summary == nil ? "meeting.summary.resume" : "meeting.generatedSummary.generate")
            Button("Start from beginning…", role: .destructive) { confirmingFreshSummary = true }
                .accessibilityIdentifier("meeting.summary.reset")
        } label: { Label("Summary options", systemImage: "ellipsis.circle").frame(minHeight: 44) }
        .accessibilityIdentifier("meeting.summary.options")
        .disabled(controller.busy || controller.editConflict || controller.isSaving)
    }

    private var questionsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if controller.answers.isEmpty && !controller.busy && !controller.modelRequired {
                MinutesEmptyState(title: "Ask this meeting", symbol: "bubble.left",
                                  detail: "Find an answer in the conversation.")
            }
            ForEach(controller.answers) { answer in
                VStack(alignment: .leading, spacing: 16) {
                    Text(answer.question ?? "Saved question").font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(controller.answerDrafts[answer.id] ?? answer.editedText)
                        .font(.body).lineSpacing(5).textSelection(.enabled)
                        .accessibilityIdentifier("meeting.qa.answer.content.\(answer.id.uuidString)")
                    citations(answer)
                    Button("Edit answer") { editingAnswer = answer }
                        .frame(minHeight: 44).disabled(controller.busy)
                        .accessibilityIdentifier("meeting.qa.answer.edit.\(answer.id.uuidString)")
                    if answer.editRevision > 0 {
                        Text("Edited").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("meeting.qa.answer.saved.\(answer.id.uuidString)")
                    }
                }.minutesCard()
            }
        }
    }

    @ViewBuilder private func citations(_ document: StoredGeneratedDocument) -> some View {
        let sources = controller.citations[document.id] ?? []
        if !sources.isEmpty {
            DisclosureGroup("Sources") {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(sources) { citation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("“\(citation.quote)”").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            Button {
                                guard let target = controller.citationNavigationTarget(documentID: document.id, citationID: citation.id) else { return }
                                Task { await playCitation(target) }
                            } label: {
                                Label("View source · \(MinutesStyle.timestamp(samples: citation.startSample))", systemImage: "play.circle")
                                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("meeting.citation.\(citation.sourceID.uuidString)")
                        }
                    }
                    if document.editRevision > 0 {
                        Text("Sources refer to the original generated result.").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.top, 12)
            }
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("meeting.sources.\(document.id.uuidString)")
        }
    }
}

struct MeetingQuestionComposer: View {
    @Bindable var controller: MeetingIntelligenceController
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.busy { Text("Working on this iPhone…").font(.footnote).foregroundStyle(.secondary) }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about this meeting", text: $controller.question, axis: .vertical)
                    .font(.body).lineLimit(1...5).padding(14)
                    .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("meeting.qa.question").disabled(controller.busy)
                    .submitLabel(.send)
                    .onSubmit { if !controller.busy { controller.ask() } }
                Button {
                    if controller.busy { controller.cancel() } else { controller.ask() }
                } label: {
                    Image(systemName: controller.busy ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .frame(width: 48, height: 48)
                        .background(MinutesStyle.accent, in: Circle())
                }
                .buttonStyle(MinutesPressStyle())
                .accessibilityLabel(controller.busy ? "Cancel generation" : "Ask meeting")
                .accessibilityIdentifier(controller.busy ? "meeting.intelligence.cancel" : "meeting.qa.ask")
                .disabled(!controller.busy && controller.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}

private struct SummaryEditorView: View {
    @Bindable var controller: MeetingIntelligenceController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextEditor(text: $controller.summaryText)
                        .font(.body).lineSpacing(5).frame(minHeight: 380)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Generated meeting summary")
                        .accessibilityIdentifier("meeting.generatedSummary.editor")
                        .onChange(of: controller.summaryText) { _, _ in controller.summaryChanged() }
                    if controller.isSaving { ProgressView("Saving…") }
                    if let error = controller.errorMessage { MinutesMessage(text: error, isError: true) }
                    if controller.editConflict {
                        Button("Copy my draft") { UIPasteboard.general.string = controller.summaryText }
                            .buttonStyle(MinutesButtonStyle(kind: .secondary))
                        Button("Reopen saved summary", role: .destructive) { controller.reopenSavedSummary() }
                            .frame(minHeight: 44)
                    }
                    Text("Edits change this copy. Your original notes and transcript are preserved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(MinutesStyle.background)
            .navigationTitle("Edit summary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { if await controller.flushSummaryEdits() { dismiss() } } }
                        .accessibilityIdentifier("meeting.summary.save")
                        .disabled(controller.busy || controller.isSaving || controller.editConflict)
                }
            }
        }
        .interactiveDismissDisabled(controller.hasSummaryEdits || controller.isSaving || controller.editConflict)
    }
}

private struct AnswerEditorView: View {
    @Bindable var controller: MeetingIntelligenceController
    let answer: StoredGeneratedDocument
    @Environment(\.dismiss) private var dismiss
    private var changed: Bool { (controller.answerDrafts[answer.id] ?? answer.editedText) != (controller.answers.first { $0.id == answer.id }?.editedText ?? answer.editedText) }
    private var saving: Bool { controller.savingAnswerIDs.contains(answer.id) }
    private var conflict: Bool { controller.answerEditConflicts.contains(answer.id) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(answer.question ?? "Saved question").font(.title2.weight(.semibold))
                    TextEditor(text: Binding(get: { controller.answerDrafts[answer.id] ?? answer.editedText },
                                            set: { controller.answerDrafts[answer.id] = $0 }))
                        .font(.body).lineSpacing(5).frame(minHeight: 300)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Saved answer")
                        .accessibilityIdentifier("meeting.qa.answer.editor.\(answer.id.uuidString)")
                    if saving { ProgressView("Saving…") }
                    if let error = controller.answerSaveErrors[answer.id] { MinutesMessage(text: error, isError: true) }
                    if conflict {
                        Button("Copy my draft") { UIPasteboard.general.string = controller.answerDrafts[answer.id] ?? answer.editedText }
                            .buttonStyle(MinutesButtonStyle(kind: .secondary))
                        Button("Reopen saved answer", role: .destructive) {
                            Task { await controller.reopenSavedAnswer(documentID: answer.id) }
                        }.accessibilityIdentifier("meeting.qa.answer.reopen.\(answer.id.uuidString)")
                    }
                    Text("Sources refer to the original answer.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(MinutesStyle.background)
            .navigationTitle("Edit answer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await controller.flushAnswerEdits(documentID: answer.id) { dismiss() } }
                    }
                    .accessibilityIdentifier("meeting.qa.answer.save.\(answer.id.uuidString)")
                    .disabled(controller.busy || saving || conflict)
                }
            }
        }.interactiveDismissDisabled(changed || saving || conflict)
    }
}

private struct GeneratedDetailsView: View {
    let document: StoredGeneratedDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Version", value: document.editRevision > 0 ? "Edited copy" : "Original")
                    Text("Review generated content against its sources before sharing.").foregroundStyle(.secondary)
                }
                Section("Technical details") {
                    LabeledContent("Prompt", value: document.promptVersion)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model revision").font(.subheadline).foregroundStyle(.secondary)
                        Text(document.modelRevision).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .minutesList().navigationTitle("Generation details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif
