import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum MeetingLibraryError: Error, Equatable { case noSelection }

/// Observable screen state backed by the one real meeting database.
@MainActor @Observable
public final class MeetingLibraryController {
    public private(set) var meetings: [MeetingRecord] = []
    public private(set) var selected: MeetingRecord?
    public private(set) var transcript: [StoredTranscriptSegment] = []
    public private(set) var note: StoredManualNote?
    public private(set) var matches: [StoredTranscriptSegment] = []
    public private(set) var errorMessage: String?
    @ObservationIgnored private let store: SQLiteMeetingStore
    @ObservationIgnored private var selectionRequest = UUID()

    public init(store: SQLiteMeetingStore) { self.store = store }

    public func refresh() async {
        do { meetings = try await store.history(); errorMessage = nil }
        catch { errorMessage = "Meetings could not be loaded." }
    }

    public func open(id: UUID) async {
        let request = UUID()
        selectionRequest = request
        selected = nil; transcript = []; note = nil; matches = []
        do {
            let meeting = try await store.meeting(id: id)
            let rows = try await store.transcript(meetingID: id)
            let manual = try await store.manualNote(meetingID: id)
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
        do {
            try await store.renameMeeting(id: id, title: title)
            if selected?.id == id { selected = try await store.meeting(id: id) }
            await refresh()
        } catch { errorMessage = "The meeting name could not be saved." }
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
