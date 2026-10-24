import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesMeetingLibrary
#endif

public enum MeetingReplayModelPolicy: Sendable {
    case capturedPinRequired
}
