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
    private let storageDirectory: URL?
    private let storageReserveBytes: Int64
    private let availableStorageBytes: @MainActor (URL) throws -> Int64
    private let inputAvailable: @MainActor () -> Bool
    private let thermalState: @MainActor () -> ProcessInfo.ThermalState
    private let inbox = RecordingSignalInbox()
    private var sessionID: UUID?
    private var observers: [any NSObjectProtocol] = []
    private var operation: (id: UUID, task: Task<Void, Never>)?
    private var storagePolling: Task<Void, Never>?

    init(owner: RecordingSessionOwner, center: NotificationCenter = .default,
         storageDirectory: URL? = nil, storageReserveBytes: Int64 = 1_000_000_000,
         availableStorageBytes: @escaping @MainActor (URL) throws -> Int64 = {
             try ModelStoragePolicy.availableBytes(at: $0)
         },
         inputAvailable: @escaping @MainActor () -> Bool = {
             !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty
         },
         thermalState: @escaping @MainActor () -> ProcessInfo.ThermalState = {
             ProcessInfo.processInfo.thermalState
         }) {
        self.owner = owner
        self.center = center
        self.storageDirectory = storageDirectory
        self.storageReserveBytes = max(1_000_000_000, storageReserveBytes)
        self.availableStorageBytes = availableStorageBytes
        self.inputAvailable = inputAvailable
        self.thermalState = thermalState
    }

    func beginEpoch(sessionID: UUID) {
        guard self.sessionID != sessionID else { return }
        if let previous = self.sessionID { endEpoch(sessionID: previous) }
        self.sessionID = sessionID
        inbox.select(sessionID)
        // Apple requires reading thermalState before registering for changes.
        let initialThermalState = thermalState()
        let inbox = self.inbox
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil) { [weak self] notification in
                let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber
                guard value?.uintValue == AVAudioSession.InterruptionType.began.rawValue,
                      inbox.offer(sessionID, kinds: .interruption) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: nil) { [weak self] _ in
                guard inbox.offer(sessionID, kinds: .mediaReset) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil) { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber
                guard let rawReason,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason.uintValue),
                      reason == .oldDeviceUnavailable || reason == .noSuitableRouteForCategory ||
                        reason == .routeConfigurationChange else { return }
                // Copy only bounded primitive input identities while Notification
                // owns its objects. Category-only changes and new-device/ended
                // events do not interrupt or restart a capture epoch.
                let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                    as? AVAudioSessionRouteDescription
                let previousInputs = previous?.inputs.prefix(8).map(\.uid) ?? []
                guard inbox.offer(sessionID, kinds: .routeChange, previousInputs: previousInputs) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: nil) { [weak self] _ in
                guard inbox.offer(sessionID, kinds: .thermal) else { return }
                Task { @MainActor [weak self] in await self?.flush() }
            })
        if initialThermalState == .critical, inbox.offer(sessionID, kinds: .thermal) {
            Task { @MainActor [weak self] in await self?.flush() }
        }
        if storageDirectory != nil {
            storagePolling = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { return }
                    guard let self, self.sessionID == sessionID else { return }
                    await self.pollStorage(sessionID: sessionID)
                }
            }
        }
    }

    func endEpoch(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        inbox.select(nil)
        storagePolling?.cancel()
        storagePolling = nil
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll(keepingCapacity: true)
    }

    /// Coalesces control notifications and joins actual owner teardown. Ended
    /// interruptions never restart capture; the next recording is a user action.
    func flush() async {
        if let operation { await operation.task.value; return }
        let id = UUID()
        let task = Task { @MainActor in
            while let signal = self.inbox.take() {
                guard self.sessionID == signal.sessionID else { continue }
                var interrupted = signal.kinds.contains(.interruption) || signal.kinds.contains(.mediaReset)
                if signal.kinds.contains(.routeChange) {
                    let currentInputs = Set(AVAudioSession.sharedInstance().currentRoute.inputs.prefix(8).map(\.uid))
                    let changedInput = !signal.previousInputs.isEmpty &&
                        !Set(signal.previousInputs).isSubset(of: currentInputs)
                    interrupted = interrupted || !self.inputAvailable() || changedInput
                }
                if signal.kinds.contains(.thermal), self.thermalState() == .critical { interrupted = true }
                if signal.kinds.contains(.storage) { interrupted = true }
                if interrupted {
                    await self.owner.interrupt(sessionID: signal.sessionID, failure: signal.failure)
                }
            }
            // Clear on the draining task before it completes. A notification
            // admitted after its last take must be able to start a new drain.
            if self.operation?.id == id { self.operation = nil }
        }
        operation = (id, task)
        await task.value
    }

    private func pollStorage(sessionID: UUID) async {
        guard self.sessionID == sessionID, let storageDirectory else { return }
        let snapshot = await owner.snapshot()
        guard self.sessionID == sessionID, snapshot.sessionID == sessionID,
              snapshot.phase == .preparing || snapshot.phase == .recording else { return }
        let failure: RecordingFailure?
        do {
            guard storageDirectory.isFileURL else { throw PersistentFilePolicyError.invalidRoot }
            var probe = storageDirectory.standardizedFileURL
            while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
                probe.deleteLastPathComponent()
            }
            failure = try availableStorageBytes(probe) < storageReserveBytes ? .storageFull : nil
        } catch { failure = .writeFailed }
        guard let failure, self.sessionID == sessionID else { return }
        if inbox.offer(sessionID, kinds: .storage, failure: failure) { await flush() }
    }
}

private struct RecordingSignalKinds: OptionSet, Sendable {
    let rawValue: UInt8
    static let interruption = Self(rawValue: 1 << 0)
    static let mediaReset = Self(rawValue: 1 << 1)
    static let routeChange = Self(rawValue: 1 << 2)
    static let thermal = Self(rawValue: 1 << 3)
    static let storage = Self(rawValue: 1 << 4)
}

private struct RecordingSignal: Sendable {
    let sessionID: UUID
    let kinds: RecordingSignalKinds
    let failure: RecordingFailure?
    let previousInputs: [String]
}

/// At most one current epoch and one pending signal. Stale callback admissions
/// cannot overwrite a replacement's pending notification or create a task storm.
private final class RecordingSignalInbox: Sendable {
    private struct State: Sendable {
        var id: UUID?
        var pending = false
        var kinds: RecordingSignalKinds = []
        var failure: RecordingFailure?
        var previousInputs: [String] = []
    }
    private let state = Mutex(State())
    func select(_ id: UUID?) { state.withLock { $0 = .init(id: id) } }
    func offer(_ id: UUID, kinds: RecordingSignalKinds,
               failure: RecordingFailure? = nil, previousInputs: [String] = []) -> Bool {
        state.withLock {
            guard $0.id == id else { return false }
            let shouldWake = !$0.pending
            $0.pending = true
            $0.kinds.formUnion(kinds)
            $0.failure = $0.failure ?? failure
            if !previousInputs.isEmpty { $0.previousInputs = Array(previousInputs.prefix(8)) }
            return shouldWake
        }
    }
    func take() -> RecordingSignal? {
        state.withLock {
            guard $0.pending, let id = $0.id else { return nil }
            let signal = RecordingSignal(sessionID: id, kinds: $0.kinds,
                failure: $0.failure, previousInputs: $0.previousInputs)
            $0.pending = false
            $0.kinds = []
            $0.failure = nil
            $0.previousInputs.removeAll(keepingCapacity: true)
            return signal
        }
    }
}
#endif
