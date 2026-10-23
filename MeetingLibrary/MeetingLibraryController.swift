import Foundation
import Observation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

public enum MeetingLibraryError: Error, Equatable { case noSelection }

/// Test-first observable screen model backed by the one real meeting database.
@MainActor @Observable
public final class MeetingLibraryController {
    public private(set) var meetings: [MeetingRecord] = []
    public private(set) var selected: MeetingRecord?
    public private(set) var transcript: [StoredTranscriptSegment] = []
    public private(set) var note: StoredManualNote?
    public private(set) var matches: [StoredTranscriptSegment] = []
    public private(set) var errorMessage: String?

    public init(store: SQLiteMeetingStore) {}
    public func refresh() async {}
    public func open(id: UUID) async {}
    public func rename(_ title: String) async {}
    public func saveNotes(_ text: String) async {}
    public func search(_ query: String) async {}
    public func deleteSelected() async {}
    public func export(markdown: Bool) throws -> String { throw MeetingLibraryError.noSelection }
}
