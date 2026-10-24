import Foundation

public enum HeavyModelPurpose: CaseIterable, Equatable, Sendable {
    case streamingASR, summary, questionAnswering
}

public struct HeavyModelUseLease: Equatable, Sendable {
    public let purpose: HeavyModelPurpose
    public let requestID: UUID
    public let generation: UUID
    fileprivate init(purpose: HeavyModelPurpose, requestID: UUID, generation: UUID) {
        self.purpose = purpose; self.requestID = requestID; self.generation = generation
    }
}

public enum HeavyModelAdmissionPhase: Equatable, Sendable { case idle, admitted, draining, cleanupBlocked }

public struct HeavyModelAdmissionSnapshot: Equatable, Sendable {
    public let phase: HeavyModelAdmissionPhase
    public let lease: HeavyModelUseLease?
    public init(phase: HeavyModelAdmissionPhase, lease: HeavyModelUseLease?) {
        self.phase = phase; self.lease = lease
    }
}

public enum HeavyModelAdmissionError: Error, Equatable, Sendable { case busy, staleLease, cleanupFailed }

/// Resource-control boundary, not an inference implementation. Implementations
/// must close work admission synchronously, await all workers, then unload the
/// actual native runtime and release its separate ModelInstallationManager lease.
@MainActor
public protocol HeavyModelResourceLifecycle: AnyObject {
    func requestCancellation()
    func drain() async throws
    func unloadAndReleaseModel() async throws
}

/// INACTIVE TEST-FIRST STUB. Retained by app services, never a view/global
/// singleton. These no-op methods intentionally do not enforce the contract.
@MainActor
public final class HeavyModelAdmission {
    public init() {}

    public func acquire(purpose: HeavyModelPurpose, requestID: UUID,
                        resource: any HeavyModelResourceLifecycle) throws -> HeavyModelUseLease {
        .init(purpose: purpose, requestID: requestID, generation: UUID())
    }

    public func validate(_ lease: HeavyModelUseLease) throws {}

    public func cancelAndDrain(_ lease: HeavyModelUseLease) async throws {
        try Task.checkCancellation()
    }

    public func snapshot() -> HeavyModelAdmissionSnapshot { .init(phase: .idle, lease: nil) }
}
