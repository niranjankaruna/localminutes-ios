import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var recordingStartedAt: Date? = nil
        var recordingEndedAt: Date? = nil

        func updating(status: String, at date: Date) -> Self {
            var next = self
            next.status = status
            if status == "recording", next.recordingStartedAt == nil,
               next.recordingEndedAt == nil {
                next.recordingStartedAt = date
            }
            if ["finished", "failed", "interrupted"].contains(status),
               let start = next.recordingStartedAt, next.recordingEndedAt == nil {
                next.recordingEndedAt = max(start, date)
            }
            return next
        }
    }

    var meetingID: UUID
}
