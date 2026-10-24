import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
#endif

// The immutable StoredManualNote overload is implemented inside
// MeetingLibraryController so its private(set) state remains encapsulated.
// UI scheduling must capture that value before debounce; native UI wiring is
// a separate test-first integration gate.
