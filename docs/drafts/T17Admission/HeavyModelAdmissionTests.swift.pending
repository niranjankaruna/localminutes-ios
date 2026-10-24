import Foundation
import XCTest
@testable import LocalMinutesCore

/// Actual gate/state/task ordering with native-work boundaries doubled. This
/// proves no model accuracy, native teardown, memory use or device behavior.
@MainActor
final class HeavyModelAdmissionTests: XCTestCase {
    func testASRSummaryAndQAAreMutuallyExclusiveUntilNativeResourcesAreClosed() async throws {
        for first in HeavyModelPurpose.allCases {
            for second in HeavyModelPurpose.allCases {
                let gate = HeavyModelAdmission()
                let monitor = NativeUseMonitor()
                let a = AdmissionResource(name: "first", monitor: monitor)
                let b = AdmissionResource(name: "second", monitor: monitor)
                let lease = try gate.acquire(purpose: first, requestID: UUID(), resource: a)
                try a.open(after: lease, through: gate)
                do {
                    let competing = try gate.acquire(purpose: second, requestID: UUID(), resource: b)
                    try b.open(after: competing, through: gate)
                    XCTFail("Competing native resource entered while the first remained open")
                } catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .busy) }
                XCTAssertEqual(monitor.active.count, 1)
                XCTAssertEqual(monitor.maximumActive, 1)
                XCTAssertEqual(gate.snapshot().lease, lease)
                try await gate.cancelAndDrain(lease)
                XCTAssertTrue(monitor.active.isEmpty, "Drained means actual boundary resources were closed")
                XCTAssertEqual(gate.snapshot().phase, .idle)
                XCTAssertEqual(monitor.events, ["first.open", "first.cancel", "first.drained", "first.unloaded"])
            }
        }
    }

    func testCancelledWaiterAndConcurrentJoinCannotReleaseBeforeDrainThenUnloadComplete() async throws {
        let gate = HeavyModelAdmission()
        let monitor = NativeUseMonitor()
        let a = AdmissionResource(name: "summary", monitor: monitor)
        a.drainBarrier = AdmissionLatch(); a.unloadBarrier = AdmissionLatch()
        defer { a.drainBarrier?.release(); a.unloadBarrier?.release() }
        let lease = try gate.acquire(purpose: .summary, requestID: UUID(), resource: a)
        try a.open(after: lease, through: gate)
        let cancelledWaiter = Task { try await gate.cancelAndDrain(lease) }
        guard await admissionWait({ a.drainBarrier?.isWaiting == true }) else {
            a.drainBarrier?.release(); a.unloadBarrier?.release()
            cancelledWaiter.cancel()
            _ = try? await cancelledWaiter.value
            return XCTFail("Owned cleanup never entered the real drain boundary")
        }
        let joiningWaiter = Task { try await gate.cancelAndDrain(lease) }
        cancelledWaiter.cancel()
        XCTAssertEqual(gate.snapshot().phase, .draining)
        assertBusy(gate, resource: AdmissionResource(name: "asr", monitor: monitor))
        XCTAssertEqual(monitor.active.count, 1)
        a.drainBarrier?.release()
        guard await admissionWait({ a.unloadBarrier?.isWaiting == true }) else {
            a.unloadBarrier?.release()
            _ = try? await cancelledWaiter.value; _ = try? await joiningWaiter.value
            return XCTFail("Cleanup did not retain admission through native unload")
        }
        XCTAssertEqual(monitor.events, ["summary.open", "summary.cancel", "summary.drained"])
        XCTAssertEqual(monitor.active.count, 1)
        assertBusy(gate, resource: AdmissionResource(name: "asr", monitor: monitor))
        a.unloadBarrier?.release()
        do { try await cancelledWaiter.value; XCTFail("Cancelled waiter must report cancellation after the owned barrier") }
        catch is CancellationError {}
        try await joiningWaiter.value
        XCTAssertEqual(monitor.events, ["summary.open", "summary.cancel", "summary.drained", "summary.unloaded"])
        XCTAssertTrue(monitor.active.isEmpty)
        let replacement = AdmissionResource(name: "replacement", monitor: monitor)
        let next = try gate.acquire(purpose: .streamingASR, requestID: UUID(), resource: replacement)
        try replacement.open(after: next, through: gate)
        XCTAssertEqual(monitor.maximumActive, 1)
        try await gate.cancelAndDrain(next)
    }

    func testStaleLeaseCannotAuthorizeOrCancelReplacementEvenWhenRequestIDIsReused() async throws {
        let gate = HeavyModelAdmission()
        let monitor = NativeUseMonitor()
        let requestID = UUID()
        let a = AdmissionResource(name: "old", monitor: monitor)
        let old = try gate.acquire(purpose: .summary, requestID: requestID, resource: a)
        try a.open(after: old, through: gate)
        try await gate.cancelAndDrain(old)
        let b = AdmissionResource(name: "new", monitor: monitor)
        let replacement = try gate.acquire(purpose: .questionAnswering, requestID: requestID, resource: b)
        try b.open(after: replacement, through: gate)
        XCTAssertNotEqual(old.generation, replacement.generation)
        let events = monitor.events
        XCTAssertThrowsError(try gate.validate(old)) { XCTAssertEqual($0 as? HeavyModelAdmissionError, .staleLease) }
        do { try await gate.cancelAndDrain(old); XCTFail("Late cleanup targeted a replacement") }
        catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .staleLease) }
        XCTAssertEqual(gate.snapshot().lease, replacement)
        XCTAssertEqual(monitor.events, events)
        XCTAssertEqual(monitor.active, Set([b.id]))
        try gate.validate(replacement)
        try await gate.cancelAndDrain(replacement)
        XCTAssertTrue(monitor.active.isEmpty)
    }

    func testCleanupFailureRetainsExclusionAndRetryResumesWithoutRepeatedCancellation() async throws {
        let gate = HeavyModelAdmission()
        let monitor = NativeUseMonitor()
        let a = AdmissionResource(name: "qa", monitor: monitor)
        a.remainingDrainFailures = 1
        let lease = try gate.acquire(purpose: .questionAnswering, requestID: UUID(), resource: a)
        try a.open(after: lease, through: gate)
        do { try await gate.cancelAndDrain(lease); XCTFail("Failed cleanup was acknowledged as complete") }
        catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .cleanupFailed) }
        XCTAssertEqual(gate.snapshot().phase, .cleanupBlocked)
        XCTAssertEqual(gate.snapshot().lease, lease)
        XCTAssertEqual(monitor.active, Set([a.id]))
        assertBusy(gate, resource: AdmissionResource(name: "asr", monitor: monitor))
        XCTAssertFalse(monitor.events.contains("qa.unloaded"), "Never unload a runtime with unjoined work")
        try await gate.cancelAndDrain(lease)
        XCTAssertEqual(monitor.events, ["qa.open", "qa.cancel", "qa.drainFailed", "qa.drained", "qa.unloaded"])
        XCTAssertTrue(monitor.active.isEmpty)
        XCTAssertEqual(gate.snapshot().phase, .idle)
    }

    private func assertBusy(_ gate: HeavyModelAdmission, resource: AdmissionResource,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try gate.acquire(purpose: .streamingASR, requestID: UUID(), resource: resource),
                             file: file, line: line) {
            XCTAssertEqual($0 as? HeavyModelAdmissionError, .busy, file: file, line: line)
        }
    }
}

@MainActor
private final class NativeUseMonitor {
    var active: Set<UUID> = []
    var maximumActive = 0
    var events: [String] = []
}

@MainActor
private final class AdmissionResource: HeavyModelResourceLifecycle {
    let id = UUID()
    let name: String
    let monitor: NativeUseMonitor
    var drainBarrier: AdmissionLatch?
    var unloadBarrier: AdmissionLatch?
    var remainingDrainFailures = 0
    init(name: String, monitor: NativeUseMonitor) { self.name = name; self.monitor = monitor }
    func open(after lease: HeavyModelUseLease, through gate: HeavyModelAdmission) throws {
        try gate.validate(lease)
        monitor.active.insert(id)
        monitor.maximumActive = max(monitor.maximumActive, monitor.active.count)
        monitor.events.append(name + ".open")
    }
    func requestCancellation() { monitor.events.append(name + ".cancel") }
    func drain() async throws {
        await drainBarrier?.wait()
        if remainingDrainFailures > 0 {
            remainingDrainFailures -= 1
            monitor.events.append(name + ".drainFailed")
            throw AdmissionBoundaryError.drainFailed
        }
        monitor.events.append(name + ".drained")
    }
    func unloadAndReleaseModel() async throws {
        await unloadBarrier?.wait()
        monitor.active.remove(id)
        monitor.events.append(name + ".unloaded")
    }
}

private enum AdmissionBoundaryError: Error { case drainFailed }

@MainActor
private final class AdmissionLatch {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var isWaiting: Bool { !waiters.isEmpty }
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
private func admissionWait(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !condition() {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
