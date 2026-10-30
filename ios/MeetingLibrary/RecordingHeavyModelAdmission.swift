import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesRecording
#endif

/// App-owned admission shared by the real recording owner and IntelligenceSession.
/// The owner signals its settled resource barrier before joining gate cleanup.
@MainActor
public final class RecordingHeavyModelAdmission: RecordingUsageAdmission {
    @MainActor
    private final class Use: HeavyModelResourceLifecycle {
        let meetingID: UUID
        let token: UUID
        weak var owner: RecordingSessionOwner?
        var lease: HeavyModelUseLease?
        var completion: Task<Void, Error>?
        private(set) var resourcesSettled = false
        private(set) var gateResourcesReleased = false
        private var settledWaiter: CheckedContinuation<Void, Never>?
        private var stopRequest: Task<Void, Never>?

        init(meetingID: UUID, token: UUID, owner: RecordingSessionOwner) {
            self.meetingID = meetingID; self.token = token; self.owner = owner
        }

        func requestCancellation() {
            guard !resourcesSettled, stopRequest == nil, let owner else { return }
            // This request may join the owner's existing cleanup. Gate drain
            // never joins this Task, because owner cleanup itself joins the gate.
            stopRequest = Task { @MainActor [weak self, weak owner] in
                guard let self, !self.resourcesSettled else { return }
                await owner?.stop(sessionID: self.meetingID)
            }
        }

        func drain() async throws {
            if !resourcesSettled {
                // HeavyModelAdmission coalesces its cleanup, so there is one
                // drain waiter. It is independent of the outer owner Stop Task.
                await withCheckedContinuation { settledWaiter = $0 }
            }
        }

        func unloadAndReleaseModel() async throws {
            // RecordingPreparationSource.finish has already joined the actual
            // native unload/model lease barrier before owner calls async finish.
            guard resourcesSettled else { throw HeavyModelAdmissionError.cleanupFailed }
            gateResourcesReleased = true
        }

        func signalResourcesSettled() {
            resourcesSettled = true
            settledWaiter?.resume()
            settledWaiter = nil
        }
    }

    public let usageRegistry: MeetingUsageRegistry
    public let heavyAdmission: HeavyModelAdmission
    private weak var owner: RecordingSessionOwner?
    private var current: Use?

    public init(usageRegistry: MeetingUsageRegistry, heavyAdmission: HeavyModelAdmission) {
        self.usageRegistry = usageRegistry; self.heavyAdmission = heavyAdmission
    }

    public func bind(owner: RecordingSessionOwner) {
        guard current == nil else { return }
        self.owner = owner
    }

    public func acquireRecordingUsage(meetingID: UUID) -> UUID? {
        guard current == nil, let owner,
              let token = usageRegistry.acquireRecordingUsage(meetingID: meetingID) else { return nil }
        let use = Use(meetingID: meetingID, token: token, owner: owner)
        do {
            use.lease = try heavyAdmission.acquire(purpose: .streamingASR, requestID: meetingID, resource: use)
            current = use
            return token
        } catch {
            // No model/preparation/OS work occurred. Roll back only our token.
            usageRegistry.releaseRecordingUsage(meetingID: meetingID, token: token)
            return nil
        }
    }

    public func releaseRecordingUsage(meetingID: UUID, token: UUID) {
        guard let use = current, use.meetingID == meetingID, use.token == token else { return }
        // A synchronous legacy release cannot acknowledge an async native
        // cleanup. Keep both claims and request the exact owner barrier instead.
        use.requestCancellation()
    }

    public func finishRecordingUsage(meetingID: UUID, token: UUID) async throws {
        guard let use = current, use.meetingID == meetingID, use.token == token,
              let lease = use.lease else { throw HeavyModelAdmissionError.staleLease }
        use.signalResourcesSettled()
        let operation: Task<Void, Error>
        if let existing = use.completion { operation = existing }
        else {
            let owned = Task { @MainActor in
                do {
                    do { try await self.heavyAdmission.cancelAndDrain(lease) }
                    catch HeavyModelAdmissionError.staleLease where use.gateResourcesReleased {
                        // An external gate waiter may have completed this exact
                        // resource before this Task ran. Never touch its successor.
                    }
                    guard self.current === use else { throw HeavyModelAdmissionError.staleLease }
                    self.usageRegistry.releaseRecordingUsage(meetingID: meetingID, token: token)
                    self.current = nil
                    use.completion = nil
                } catch {
                    // Only this owned attempt clears its retry slot; old waiters
                    // cannot erase a replacement or release still-owned resources.
                    if self.current === use { use.completion = nil }
                    throw error
                }
            }
            use.completion = owned
            operation = owned
        }
        try await operation.value
    }
}
