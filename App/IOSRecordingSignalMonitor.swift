#if os(iOS)
import AVFoundation
import Foundation
import Synchronization

/// Retained control-path observation. Only primitive epoch/type facts cross the
/// notification callback; audio capture and native inference remain elsewhere.
@MainActor
final class IOSRecordingSignalMonitor {
    private let owner: RecordingSessionOwner
    private let center: NotificationCenter
    private let inbox = RecordingSignalInbox()
    private var sessionID: UUID?
    private var observers: [any NSObjectProtocol] = []
    private var operation: (id: UUID, task: Task<Void, Never>)?

    init(owner: RecordingSessionOwner, center: NotificationCenter = .default) {
        self.owner = owner
        self.center = center
    }

    func beginEpoch(sessionID: UUID) {
        guard self.sessionID != sessionID else { return }
        if let previous = self.sessionID { endEpoch(sessionID: previous) }
        self.sessionID = sessionID
        inbox.select(sessionID)
        let inbox = self.inbox
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil) { [weak self] notification in
                let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber
                guard value?.uintValue == AVAudioSession.InterruptionType.began.rawValue,
                      inbox.offer(sessionID) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil) { [weak self] _ in
                guard inbox.offer(sessionID) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
    }

    func endEpoch(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        inbox.select(nil)
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll(keepingCapacity: true)
    }

    /// Coalesces control notifications and joins actual owner teardown. Ended
    /// interruptions never restart capture; the next recording is a user action.
    func flush() async {
        if let operation { await operation.task.value; return }
        let id = UUID()
        let task = Task { @MainActor in
            while let sessionID = self.inbox.take() {
                await self.owner.interrupt(sessionID: sessionID)
            }
            // Clear on the draining task before it completes. A notification
            // admitted after its last take must be able to start a new drain.
            if self.operation?.id == id { self.operation = nil }
        }
        operation = (id, task)
        await task.value
    }
}

/// At most one current epoch and one pending signal. Stale callback admissions
/// cannot overwrite a replacement's pending notification or create a task storm.
private final class RecordingSignalInbox: Sendable {
    private struct State: Sendable { var id: UUID?; var pending = false }
    private let state = Mutex(State())
    func select(_ id: UUID?) { state.withLock { $0 = .init(id: id) } }
    func offer(_ id: UUID) -> Bool {
        state.withLock {
            guard $0.id == id, !$0.pending else { return false }
            $0.pending = true
            return true
        }
    }
    func take() -> UUID? {
        state.withLock {
            guard $0.pending else { return nil }
            $0.pending = false
            return $0.id
        }
    }
}
#endif
