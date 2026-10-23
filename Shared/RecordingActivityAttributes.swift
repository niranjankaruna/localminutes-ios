import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var recordingStartedAt: Date? = nil
        var recordingEndedAt: Date? = nil

        // Test-first interface; timer transitions require actual native RED.
        func updating(status: String, at date: Date) -> Self { self }
    }

    var meetingID: UUID
}
