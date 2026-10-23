#if os(iOS)
import ActivityKit
import Foundation

/// Actual local ActivityKit boundary. The app-owned resource controller decides
/// readiness from the returned handle; a successful request alone is not proof.
@MainActor
public final class IOSLiveActivityBackend: LiveActivityBackend {
    private let authorization = ActivityAuthorizationInfo()

    public init() {}

    public var areActivitiesEnabled: Bool {
        authorization.areActivitiesEnabled
    }

    public func request(
        sessionID: UUID, status: LiveActivityStatus
    ) throws -> any LiveActivityHandle {
        let activity = try Activity<RecordingActivityAttributes>.request(
            attributes: RecordingActivityAttributes(meetingID: sessionID),
            content: ActivityContent(
                state: RecordingActivityAttributes.ContentState(status: status.rawValue),
                staleDate: nil
            ),
            pushType: nil
        )
        return IOSLiveActivityHandle(activity: activity)
    }
}

/// All wrapper access and observer delivery stay on MainActor. The observation
/// task retains the SDK activity, but keeps only a weak reference to this owner.
@MainActor
private final class IOSLiveActivityHandle: LiveActivityHandle {
    private let activity: Activity<RecordingActivityAttributes>
    private var observer: LiveActivityStateObserver?
    private var observation: Task<Void, Never>?

    init(activity: Activity<RecordingActivityAttributes>) {
        self.activity = activity
    }

    deinit { observation?.cancel() }

    var state: LiveActivityResourceState {
        Self.map(activity.activityState)
    }

    func setStateObserver(_ observer: LiveActivityStateObserver?) {
        observation?.cancel()
        observation = nil
        self.observer = observer
        guard observer != nil else { return }
        let activity = self.activity
        observation = Task { @MainActor [weak self] in
            for await nativeState in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                // Optional chaining retains the owner only for this synchronous
                // delivery, never across the next async iterator suspension.
                self?.deliver(nativeState)
            }
        }
    }

    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        await ActivityKitOperations.update(activityID: activity.id, status: status)
    }

    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        let outcome = await ActivityKitOperations.end(activityID: activity.id, status: status)
        if outcome == .applied { setStateObserver(nil) }
        return outcome
    }

    private func deliver(_ nativeState: ActivityState) {
        observer?(Self.map(nativeState))
    }

    private static func map(_ state: ActivityState) -> LiveActivityResourceState {
        switch state {
        case .active: .active
        case .stale: .stale
        case .ended: .ended
        case .dismissed: .dismissed
        // SDK pending is iOS 26+. Unknown or not-started states must never
        // qualify readiness, and must not require that case on iOS 18.
        default: .pending
        }
    }
}
#endif
