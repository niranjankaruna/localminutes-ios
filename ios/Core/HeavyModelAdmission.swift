import Foundation

public enum HeavyModelPurpose: CaseIterable, Equatable, Sendable {
    case streamingASR, summary, questionAnswering, libraryMaintenance
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

/// Retained by app services, never a view/global singleton. Admission remains
/// reserved until one owned cleanup joins work and releases native resources.
@MainActor
public final class HeavyModelAdmission {
    @MainActor
    private final class Use {
        let lease: HeavyModelUseLease
        let resource: any HeavyModelResourceLifecycle
        var phase: HeavyModelAdmissionPhase = .admitted
        var cancellationRequested = false
        var drained = false
        var cleanup: Task<Void, Error>?

        init(lease: HeavyModelUseLease, resource: any HeavyModelResourceLifecycle) {
            self.lease = lease; self.resource = resource
        }
    }

    private var current: Use?

    public init() {}

    public func acquire(purpose: HeavyModelPurpose, requestID: UUID,
                        resource: any HeavyModelResourceLifecycle) throws -> HeavyModelUseLease {
        guard current == nil else { throw HeavyModelAdmissionError.busy }
        let lease = HeavyModelUseLease(purpose: purpose, requestID: requestID, generation: UUID())
        // MainActor-synchronous reservation precedes every caller model load.
        current = Use(lease: lease, resource: resource)
        return lease
    }

    public func validate(_ lease: HeavyModelUseLease) throws {
        guard let current, current.lease == lease else { throw HeavyModelAdmissionError.staleLease }
        // The same generation cannot authorize new work once cleanup closes it.
        guard current.phase == .admitted else { throw HeavyModelAdmissionError.busy }
    }

    public func cancelAndDrain(_ lease: HeavyModelUseLease) async throws {
        guard let use = current, use.lease == lease else { throw HeavyModelAdmissionError.staleLease }
        let operation: Task<Void, Error>
        if let existing = use.cleanup {
            operation = existing
        } else {
            use.phase = .draining
            if !use.cancellationRequested {
                use.cancellationRequested = true
                use.resource.requestCancellation()
            }
            // An unstructured, retained MainActor task owns cleanup. Cancellation
            // of a waiter never cancels it or transfers admission to another use.
            let owned = Task { @MainActor in try await self.finishCleanup(use) }
            use.cleanup = owned
            operation = owned
        }
        do {
            try await operation.value
        } catch {
            // Only the owned operation mutates the claim. A late waiter cannot
            // erase a replacement or a newer explicit cleanup retry.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
    }

    public func snapshot() -> HeavyModelAdmissionSnapshot {
        guard let current else { return .init(phase: .idle, lease: nil) }
        return .init(phase: current.phase, lease: current.lease)
    }

    private func finishCleanup(_ use: Use) async throws {
        guard current === use else { throw HeavyModelAdmissionError.staleLease }
        do {
            if !use.drained {
                try await use.resource.drain()
                use.drained = true
            }
            try await use.resource.unloadAndReleaseModel()
            // No suspension between completion and releasing this exact claim.
            use.cleanup = nil
            current = nil
        } catch {
            // Retain the resource and generation on failure. A later explicit
            // retry resumes after a successful drain, without cancelling twice.
            use.phase = .cleanupBlocked
            use.cleanup = nil
            throw HeavyModelAdmissionError.cleanupFailed
        }
    }
}
