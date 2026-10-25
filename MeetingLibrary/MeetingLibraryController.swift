import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum MeetingLibraryError: Error, Equatable { case noSelection }
enum MeetingLibraryReadOperation: Equatable, Sendable { case history, detail }

/// Observable screen state backed by the one real meeting database.
@MainActor @Observable
public final class MeetingLibraryController {
    public private(set) var meetings: [MeetingRecord] = []
    public private(set) var contentStatuses: [UUID: MeetingContentStatus] = [:]
    public private(set) var selected: MeetingRecord?
    public private(set) var transcript: [StoredTranscriptSegment] = []
    public private(set) var note: StoredManualNote?
    public private(set) var matches: [StoredTranscriptSegment] = []
    public private(set) var errorMessage: String?
    public private(set) var hasMoreMeetings = false
    public private(set) var isLoadingHistory = false
    public private(set) var isLoadingDetail = false
    public private(set) var hasMoreTranscriptMatches = false
    @ObservationIgnored private let store: SQLiteMeetingStore
    @ObservationIgnored private var selectionRequest = UUID()
    @ObservationIgnored private let afterRenameRead: (@MainActor @Sendable (UUID) async -> Void)?
    @ObservationIgnored private let afterRead: (@MainActor @Sendable (MeetingLibraryReadOperation) async -> Void)?

    public init(store: SQLiteMeetingStore) {
        self.store = store
        afterRenameRead = nil
        afterRead = nil
    }

    /// Test scheduling only: real SQLite mutation/read still occur. Public
    /// production construction always supplies nil.
    init(store: SQLiteMeetingStore,
         afterRenameRead: @escaping @MainActor @Sendable (UUID) async -> Void) {
        self.store = store
        self.afterRenameRead = afterRenameRead
        afterRead = nil
    }

    /// Scheduling boundary only: SQLite reads still execute before observation.
    init(store: SQLiteMeetingStore,
         afterRead: @escaping @MainActor @Sendable (MeetingLibraryReadOperation) async -> Void) {
        self.store = store; self.afterRead = afterRead; afterRenameRead = nil
    }

    // Test-first seams: hosted behavioral failures precede paging/search work.
    public func loadMoreMeetings() async {}
    public func searchHistory(_ query: String) async {}
    public func loadMoreTranscriptMatches() async {}

    public func refresh() async {
        do {
            let history = try await store.history()
            if let afterRead { await afterRead(.history) }
            var statuses: [UUID: MeetingContentStatus] = [:]
            for meeting in history {
                statuses[meeting.id] = await store.contentStatus(meetingID: meeting.id)
            }
            contentStatuses = statuses
            meetings = history
            errorMessage = nil
        } catch {
            contentStatuses = [:]
            errorMessage = "Meetings could not be loaded."
        }
    }

    public func open(id: UUID) async {
        let request = UUID()
        selectionRequest = request
        selected = nil; transcript = []; note = nil; matches = []
        do {
            let meeting = try await store.meeting(id: id)
            let rows = try await store.transcript(meetingID: id)
            let manual = try await store.manualNote(meetingID: id)
            if let afterRead { await afterRead(.detail) }
            guard selectionRequest == request else { return }
            selected = meeting; transcript = rows; note = manual
            errorMessage = meeting == nil ? "This meeting is no longer available." : nil
        } catch {
            guard selectionRequest == request else { return }
            errorMessage = "This meeting could not be opened."
        }
    }

    public func rename(_ title: String) async {
        guard let id = selected?.id else { return }
        let request = selectionRequest
        do {
            try await store.renameMeeting(id: id, title: title)
            guard request == selectionRequest, selected?.id == id else { return }
            let loaded = try await store.meeting(id: id)
            if let afterRenameRead { await afterRenameRead(id) }
            guard request == selectionRequest, selected?.id == id else { return }
            selected = loaded
            let history = try await store.history()
            guard request == selectionRequest, selected?.id == id else { return }
            meetings = history
            errorMessage = nil
        } catch {
            guard request == selectionRequest, selected?.id == id else { return }
            errorMessage = "The meeting name could not be saved."
        }
    }

    public func saveNotes(_ text: String) async {
        guard let id = selected?.id else { return }
        let next = (note?.editRevision ?? 0).addingReportingOverflow(1)
        guard !next.overflow else { errorMessage = "The note could not be saved."; return }
        let edit = StoredManualNote(meetingID: id, text: text, editRevision: next.partialValue, modifiedAt: Date())
        // Reserve the revision before suspension, preserving the order in which
        // edits arrive. SQLite rejects any delayed older edit independently.
        note = edit
        do {
            try await store.saveManualNote(edit)
            if selected?.id == id, note?.editRevision == edit.editRevision { errorMessage = nil }
        } catch {
            if selected?.id == id, note?.editRevision == edit.editRevision {
                errorMessage = "The latest note has not been saved."
            }
        }
    }

    /// Binds the meeting and reserves its revision before any debounce or
    /// navigation suspension. Reservation alone does not perform a SQLite write.
    public func reserveManualNoteEdit(_ text: String) -> StoredManualNote? {
        guard let id = selected?.id, text != (note?.text ?? ""),
              note == nil || note?.meetingID == id else { return nil }
        let next = (note?.editRevision ?? 0).addingReportingOverflow(1)
        guard !next.overflow else {
            errorMessage = "The note could not be saved."
            return nil
        }
        // Canonicalize through the same epoch used by persisted SQLite REAL.
        // Date's reference-epoch value otherwise retains finer binary precision
        // than its 1970 representation and can change on a strict round trip.
        let timestamp = Date(timeIntervalSince1970: Date().timeIntervalSince1970)
        let edit = StoredManualNote(meetingID: id, text: text,
            editRevision: next.partialValue, modifiedAt: timestamp)
        note = edit
        return edit
    }

    /// The editor binds the identity and revision before debounce/navigation.
    /// A late save still commits to its original meeting, while a storage error
    /// is returned to that operation without rewriting another screen's state.
    public func saveNotes(_ edit: StoredManualNote) async throws {
        let request = selectionRequest
        try await store.saveManualNote(edit)
        guard request == selectionRequest, selected?.id == edit.meetingID,
              note == nil || (note?.editRevision ?? -1) <= edit.editRevision else { return }
        note = edit
        errorMessage = nil
    }

    public func search(_ query: String) async {
        guard let id = selected?.id else { matches = []; return }
        let request = selectionRequest
        do {
            let rows = try await store.searchTranscript(meetingID: id, query: query)
            guard request == selectionRequest else { return }
            matches = rows; errorMessage = nil
        } catch { errorMessage = "The transcript could not be searched." }
    }

    public func deleteSelected() async {
        guard let id = selected?.id else { return }
        do {
            try await store.deleteMeeting(id: id)
            if selected?.id == id {
                selectionRequest = UUID()
                selected = nil; transcript = []; note = nil; matches = []
            }
            await refresh()
        } catch { errorMessage = "The meeting could not be deleted." }
    }

    public func export(markdown: Bool) throws -> String {
        guard let selected else { throw MeetingLibraryError.noSelection }
        let document = MeetingExportDocument(meeting: selected, manualNote: note, transcript: transcript)
        if markdown { return try MeetingTextExporter.markdown(document) }
        return try MeetingTextExporter.plainText(document)
    }
}
