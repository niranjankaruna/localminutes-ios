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
    @ObservationIgnored private var historyRequest = UUID()
    @ObservationIgnored private var historyQuery = ""
    @ObservationIgnored private var historyCursor: MeetingHistoryCursor?
    @ObservationIgnored private var searchRequest = UUID()
    @ObservationIgnored private var transcriptQuery = ""
    @ObservationIgnored private var transcriptCursor: Int?
    @ObservationIgnored private var matchPageRequest: UUID?
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

    public func loadMoreMeetings() async {
        guard !isLoadingHistory, hasMoreMeetings, let historyCursor else { return }
        await loadHistory(query: historyQuery, after: historyCursor, replacing: false)
    }

    public func searchHistory(_ query: String) async {
        await loadHistory(query: query, after: nil, replacing: true)
    }

    public func loadMoreTranscriptMatches() async {
        guard let id = selected?.id, hasMoreTranscriptMatches, let transcriptCursor,
              matchPageRequest == nil else { return }
        let pageRequest = UUID(), selection = selectionRequest, search = searchRequest
        matchPageRequest = pageRequest
        defer { if matchPageRequest == pageRequest { matchPageRequest = nil } }
        do {
            let page = try await store.searchTranscriptPage(meetingID: id, query: transcriptQuery,
                                                            afterSequence: transcriptCursor)
            guard selectionRequest == selection, searchRequest == search else { return }
            matches.append(contentsOf: page.matches)
            self.transcriptCursor = page.nextSequence
            hasMoreTranscriptMatches = page.nextSequence != nil
            errorMessage = nil
        } catch {
            guard selectionRequest == selection, searchRequest == search else { return }
            errorMessage = "More transcript matches could not be loaded."
        }
    }

    public func refresh() async {
        await loadHistory(query: historyQuery, after: nil, replacing: true)
    }

    private func loadHistory(query: String, after cursor: MeetingHistoryCursor?, replacing: Bool) async {
        if replacing {
            historyRequest = UUID()
            historyQuery = query
            historyCursor = nil
            hasMoreMeetings = false
        }
        let request = historyRequest
        isLoadingHistory = true
        defer { if historyRequest == request { isLoadingHistory = false } }
        do {
            let page = try await store.historyPage(query: query, after: cursor)
            if let afterRead { await afterRead(.history) }
            var statuses: [UUID: MeetingContentStatus] = [:]
            for meeting in page.meetings {
                statuses[meeting.id] = await store.contentStatus(meetingID: meeting.id)
            }
            guard historyRequest == request else { return }
            if replacing { contentStatuses = statuses; meetings = page.meetings }
            else {
                contentStatuses.merge(statuses) { _, new in new }
                meetings.append(contentsOf: page.meetings)
            }
            historyCursor = page.nextCursor
            hasMoreMeetings = page.nextCursor != nil
            errorMessage = nil
        } catch {
            guard historyRequest == request else { return }
            if replacing { contentStatuses = [:] }
            errorMessage = "Meetings could not be loaded."
        }
    }

    public func open(id: UUID) async {
        let request = UUID()
        selectionRequest = request
        searchRequest = UUID(); transcriptQuery = ""; transcriptCursor = nil; matchPageRequest = nil
        hasMoreTranscriptMatches = false
        isLoadingDetail = true
        defer { if selectionRequest == request { isLoadingDetail = false } }
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
            let historyEpoch = historyRequest
            let page = try await store.historyPage(query: historyQuery)
            guard request == selectionRequest, selected?.id == id else { return }
            if historyEpoch == historyRequest {
                meetings = page.meetings
                historyCursor = page.nextCursor
                hasMoreMeetings = page.nextCursor != nil
            }
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
        guard let id = selected?.id else {
            matches = []; hasMoreTranscriptMatches = false; transcriptCursor = nil; return
        }
        let request = selectionRequest
        let search = UUID()
        searchRequest = search; transcriptQuery = query; transcriptCursor = nil; matchPageRequest = nil
        hasMoreTranscriptMatches = false
        do {
            let page = try await store.searchTranscriptPage(meetingID: id, query: query)
            guard request == selectionRequest, searchRequest == search else { return }
            matches = page.matches; transcriptCursor = page.nextSequence
            hasMoreTranscriptMatches = page.nextSequence != nil
            errorMessage = nil
        } catch {
            guard request == selectionRequest, searchRequest == search else { return }
            errorMessage = "The transcript could not be searched."
        }
    }

    public func deleteSelected() async {
        guard let id = selected?.id else { return }
        do {
            try await store.deleteMeeting(id: id)
            if selected?.id == id {
                selectionRequest = UUID()
                selected = nil; transcript = []; note = nil; matches = []
                isLoadingDetail = false; searchRequest = UUID(); transcriptCursor = nil
                hasMoreTranscriptMatches = false; matchPageRequest = nil
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
