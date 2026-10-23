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

// Compiling domain interface only. T03 behavior is intentionally absent until hosted RED.
public actor RecordingCoordinator {
    public init() {}

    public func snapshot() -> RecordingSnapshot {
        RecordingSnapshot(phase: .idle, sessionID: nil, readiness: .init(),
                          failure: nil, cleanupPending: false)
    }

    public func start(sessionID: UUID) -> RecordingCommand? { nil }
    public func preparationSucceeded(for sessionID: UUID) -> RecordingCommand? { nil }
    public func updateReadiness(_ readiness: RecordingReadiness, for sessionID: UUID) {}
    public func stop() -> RecordingCommand? { nil }
    public func captureStopped(for sessionID: UUID) {}
    public func interrupt(for sessionID: UUID) -> RecordingCommand? { nil }
    public func fail(_ failure: RecordingFailure, for sessionID: UUID) -> RecordingCommand? { nil }
}
