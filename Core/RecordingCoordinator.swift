import Foundation

public enum RecordingPhase: String, Sendable, Equatable {
    case idle, preparing, recording, stopping, completed
    case interrupted, recoverableFailure, failed
}

public enum RecordingFailure: String, Sendable, Equatable {
    case microphoneDenied, modelUnavailable, activityUnavailable
    case captureUnavailable, storageFull, writeFailed
}

public enum RecordingCommand: Sendable, Equatable {
    case prepare(UUID)
    case activate(UUID)
    case cancelPreparation(UUID)
    case stopAndFlush(UUID)
}

public struct RecordingReadiness: Sendable, Equatable {
    public let audioSessionActive: Bool
    public let firstBufferAccepted: Bool
    public let activityActive: Bool

    public init(audioSessionActive: Bool = false, firstBufferAccepted: Bool = false,
                activityActive: Bool = false) {
        self.audioSessionActive = audioSessionActive
        self.firstBufferAccepted = firstBufferAccepted
        self.activityActive = activityActive
    }
}

public struct RecordingSnapshot: Sendable, Equatable {
    public let phase: RecordingPhase
    public let sessionID: UUID?
    public let readiness: RecordingReadiness
    public let failure: RecordingFailure?
    public let cleanupPending: Bool
}

/// App-owned domain authority. The real adapter executes returned commands and
/// acknowledges completion using the same session ID; views never own capture.
/// No I/O or inference runs inside this actor's state transitions.
public actor RecordingCoordinator {
    private var phase: RecordingPhase = .idle
    private var sessionID: UUID?
    private var readiness = RecordingReadiness()
    private var failureReason: RecordingFailure?
    private var activationIssued = false
    private var hasRecorded = false
    private var cleanupPending = false

    public init() {}

    public func snapshot() -> RecordingSnapshot {
        RecordingSnapshot(phase: phase, sessionID: sessionID, readiness: readiness,
                          failure: failureReason, cleanupPending: cleanupPending)
    }

    public func start(sessionID newSessionID: UUID) -> RecordingCommand? {
        guard !cleanupPending else { return nil }
        switch phase {
        case .preparing, .recording, .stopping:
            return nil
        case .idle, .completed, .interrupted, .recoverableFailure, .failed:
            sessionID = newSessionID
            readiness = .init()
            failureReason = nil
            activationIssued = false
            hasRecorded = false
            phase = .preparing
            return .prepare(newSessionID)
        }
    }

    public func preparationSucceeded(for id: UUID) -> RecordingCommand? {
        guard id == sessionID, phase == .preparing, !activationIssued else { return nil }
        activationIssued = true
        return .activate(id)
    }

    /// Initial success needs all three actual adapter acknowledgements. During
    /// recording, loss of activity/capture is reported via fail/interrupt instead.
    public func updateReadiness(_ value: RecordingReadiness, for id: UUID) {
        guard id == sessionID, phase == .preparing, activationIssued else { return }
        readiness = value
        if value.audioSessionActive && value.firstBufferAccepted && value.activityActive {
            hasRecorded = true
            phase = .recording
        }
    }

    public func stop() -> RecordingCommand? {
        guard let id = sessionID, !cleanupPending else { return nil }
        switch phase {
        case .preparing, .recording:
            let command: RecordingCommand = activationIssued ? .stopAndFlush(id) : .cancelPreparation(id)
            phase = .stopping
            cleanupPending = true
            readiness = .init()
            return command
        case .idle, .stopping, .completed, .interrupted, .recoverableFailure, .failed:
            return nil
        }
    }

    /// The adapter acknowledges only after activation/cancellation has settled,
    /// capture has stopped and flush has completed or its failure was recorded.
    public func captureStopped(for id: UUID) {
        guard id == sessionID, cleanupPending else { return }
        cleanupPending = false
        activationIssued = false
        readiness = .init()
        if phase == .stopping {
            phase = hasRecorded ? .completed : .idle
            if !hasRecorded { sessionID = nil }
        }
    }

    public func interrupt(for id: UUID) -> RecordingCommand? {
        guard id == sessionID, phase == .recording, !cleanupPending else { return nil }
        phase = .interrupted
        cleanupPending = true
        readiness = .init()
        return .stopAndFlush(id)
    }

    public func fail(_ failure: RecordingFailure, for id: UUID) -> RecordingCommand? {
        guard id == sessionID else { return nil }
        if cleanupPending {
            failureReason = failureReason ?? failure
            phase = hasRecorded ? .recoverableFailure : .failed
            return nil
        }
        guard phase == .preparing || phase == .recording else { return nil }
        failureReason = failure
        phase = hasRecorded ? .recoverableFailure : .failed
        cleanupPending = true
        readiness = .init()
        return activationIssued ? .stopAndFlush(id) : .cancelPreparation(id)
    }
}
