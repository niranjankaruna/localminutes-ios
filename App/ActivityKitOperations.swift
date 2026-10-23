#if os(iOS)
import ActivityKit

/// Only immutable Sendable values cross from the app owner. Each SDK reference
/// and content value is obtained and used locally in this nonisolated call.
enum ActivityKitOperations {
    nonisolated static func update(
        activityID: String, status: LiveActivityStatus
    ) async -> LiveActivityOperationOutcome {
        guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return .notFound }
        let content = ActivityContent(
            state: RecordingActivityAttributes.ContentState(status: status.rawValue),
            staleDate: nil
        )
        await activity.update(content)
        return .applied
    }

    nonisolated static func end(
        activityID: String, status: LiveActivityStatus
    ) async -> LiveActivityOperationOutcome {
        guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return .notFound }
        let content = ActivityContent(
            state: RecordingActivityAttributes.ContentState(status: status.rawValue),
            staleDate: nil
        )
        await activity.end(content, dismissalPolicy: .immediate)
        return .applied
    }
}
#endif
