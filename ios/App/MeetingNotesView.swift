#if os(iOS)
import Foundation
import Observation
import SwiftUI
import UIKit

/// Reserves each edit's meeting identity before debounce. Navigation cannot
/// redirect a delayed save to whichever meeting is opened next.
@MainActor @Observable
final class MeetingNotesDraft {
    let controller: MeetingLibraryController
    private(set) var text: String
    private(set) var error: String?
    private var writesInFlight = 0
    var saving: Bool { writesInFlight > 0 }
    private var edit: StoredManualNote?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    init(controller: MeetingLibraryController) {
        self.controller = controller
        text = controller.note?.text ?? ""
        #if DEBUG
        if AppScreenshotFixture.scene == .meetingNotesSaveFailure {
            text += " My unsaved notes."
            edit = controller.reserveManualNoteEdit(text)
            error = "Your latest notes have not been saved. Try saving again."
        }
        #endif
    }
    var hasChanges: Bool { edit != nil }

    func update(_ value: String) {
        text = value
        guard let next = controller.reserveManualNoteEdit(value) else { return }
        edit = next
        debounce?.cancel()
        debounce = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            _ = await persist(next)
        }
    }
    func flush() async -> Bool {
        debounce?.cancel()
        while let edit {
            guard await persist(edit) else { return false }
        }
        return error == nil
    }
    func leave() {
        debounce?.cancel()
        guard let edit else { return }
        Task { _ = await persist(edit) }
    }
    private func persist(_ value: StoredManualNote) async -> Bool {
        writesInFlight += 1
        defer { writesInFlight -= 1 }
        do {
            try await controller.saveNotes(value)
            if edit == value { edit = nil; error = nil }
            return true
        } catch {
            if edit == value { self.error = "Your latest notes have not been saved. Try saving again." }
            return false
        }
    }
}

struct MeetingNotesEditor: View {
    @Bindable var draft: MeetingNotesDraft
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Avoid Swift 6.2's method-reference crash: https://github.com/swiftlang/swift/issues/82491.
            TextEditor(text: Binding(get: { draft.text }, set: { draft.update($0) }))
                .focused($focused)
                .font(.body).lineSpacing(5)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300)
                .padding(12)
                .background(MinutesStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("Add your notes…").foregroundStyle(.secondary)
                            .padding(20).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Original meeting notes")
                .accessibilityIdentifier("meeting.notes.editor")
            if let error = draft.error {
                MinutesMessage(text: error, isError: true)
                    .accessibilityIdentifier("meeting.notes.error")
                Button("Save notes") { Task { _ = await draft.flush() } }
                    .buttonStyle(MinutesButtonStyle())
                Button("Copy notes") { UIPasteboard.general.string = draft.text }
                    .buttonStyle(MinutesButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("meeting.notes.copy")
            }
            if draft.saving { Text("Saving…").font(.footnote).foregroundStyle(.secondary) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onDisappear { draft.leave() }
    }
}

struct MeetingNotesEditView: View {
    @State private var draft: MeetingNotesDraft
    @Environment(\.dismiss) private var dismiss
    init(controller: MeetingLibraryController) {
        _draft = State(initialValue: MeetingNotesDraft(controller: controller))
    }
    var body: some View {
        NavigationStack {
            ScrollView { MeetingNotesEditor(draft: draft).padding(MinutesStyle.pageInset) }
                .scrollDismissesKeyboard(.interactively)
                .background(MinutesStyle.background)
                .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { Task { if await draft.flush() { dismiss() } } }
                            .accessibilityIdentifier("meeting.notes.done")
                            .disabled(draft.saving)
                    }
                }
        }
        .minutesSheet()
        .interactiveDismissDisabled(draft.hasChanges || draft.saving)
    }
}

@MainActor
struct ActiveMeetingNotesView: View {
    let id: UUID
    @State private var controller: MeetingLibraryController
    @State private var draft: MeetingNotesDraft?
    init(services: LocalMinutesServices, id: UUID) {
        self.id = id
        _controller = State(initialValue: MeetingLibraryController(store: services.store))
    }
    var body: some View {
        Group {
            if let draft { MeetingNotesEditor(draft: draft) }
            else if let error = controller.errorMessage {
                VStack(spacing: 16) {
                    MinutesMessage(text: error, isError: true)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(MinutesButtonStyle(kind: .secondary))
                }
            }
            else { ProgressView("Loading notes…") }
        }
        .task(id: id) { await load() }
    }
    private func load() async {
        await controller.open(id: id)
        if controller.selected?.id == id { draft = MeetingNotesDraft(controller: controller) }
    }
}
#endif
