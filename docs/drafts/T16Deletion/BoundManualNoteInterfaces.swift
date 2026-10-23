import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

extension MeetingLibraryController {
    /// No-op test-first overload. The UI captures the immutable meeting UUID,
    /// revision and text when the edit occurs, before any debounce suspension.
    public func saveNotes(_ edit: StoredManualNote) async throws {}
}
