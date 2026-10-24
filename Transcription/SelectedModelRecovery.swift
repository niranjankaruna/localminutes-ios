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

extension MeetingTranscriptionReplayCoordinator {
    /// TEST-FIRST policy seam only. The original legacy API is preserved, while
    /// newly captured selected-model meetings must eventually require their pin.
    /// The parameter is deliberately ignored until the selected recovery RED.
    public convenience init(store: SQLiteMeetingStore, models: ModelInstallationManager,
                            recordingsRoot: URL, usage: MeetingUsageRegistry,
                            admission: HeavyModelAdmission, modelPolicy: MeetingReplayModelPolicy) {
        self.init(store: store, models: models, recordingsRoot: recordingsRoot, usage: usage, admission: admission)
    }
}
