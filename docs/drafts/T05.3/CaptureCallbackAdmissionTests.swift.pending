import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesCore

// Synthetic callback control only. No microphone, recording or device evidence.
private final class AdmissionPayload: @unchecked Sendable {
    // Accessed only inside an admitted claim, or after closed/quiescent acquire.
    var value = 0
}

private struct AdmissionEpoch: Sendable {
    let gate = CaptureCallbackAdmission()
    let payload = AdmissionPayload()
}

// Each worker owns its own result box; the test reads it after group completion.
private final class AdmissionEntryObservations: @unchecked Sendable {
    var entries: [CaptureCallbackEntryResult] = []
    var leaves: [Bool?] = []
    var timedOut = false
}

private final class AdmissionCloseObservations: @unchecked Sendable {
    var values: [Int] = []
    var lateEntries: [CaptureCallbackEntryResult] = []
    var prematureQuiescence = false
    var timedOut = false
}

private final class AdmissionReuseObservations: @unchecked Sendable {
    var admitted = 0
    var overlapping = 0
    var unexpectedClosed = 0
    var failedLeave = false
    var timedOut = false
}

private final class AdmissionAtomicSignals: Sendable {
    let sawConcurrentClosedClaim = Atomic<Bool>(false)
}

final class CaptureCallbackAdmissionTests: XCTestCase {
    func testInitialGateIsOpenAndNotClosedQuiescent() {
        let gate = CaptureCallbackAdmission()
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .admitted)
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertTrue(gate.leave())
        XCTAssertFalse(gate.isClosedAndQuiescent)
    }

    func testSequentialCallbacksCanReuseTheOpenEpoch() {
        let gate = CaptureCallbackAdmission()
        for _ in 0..<8 {
            XCTAssertEqual(gate.enter(), .admitted)
            XCTAssertTrue(gate.leave())
            XCTAssertFalse(gate.isClosedAndQuiescent)
        }
    }

    func testOverlappingEntryCannotReleaseOrReplaceTheOriginalClaim() {
        let gate = CaptureCallbackAdmission()
        XCTAssertEqual(gate.enter(), .admitted)
        XCTAssertEqual(gate.enter(), .overlapping)
        XCTAssertEqual(gate.enter(), .overlapping)
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertTrue(gate.leave())
        XCTAssertFalse(gate.leave(), "There is no current admitted claim to release")
        XCTAssertEqual(gate.enter(), .admitted)
        XCTAssertTrue(gate.leave())
    }

    func testClosingIdleGateIsIdempotentAndCannotReopen() {
        let gate = CaptureCallbackAdmission()
        gate.close()
        gate.close()
        XCTAssertTrue(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .closed)
        XCTAssertFalse(gate.leave())
        XCTAssertTrue(gate.isClosedAndQuiescent)
        gate.close()
        XCTAssertEqual(gate.enter(), .closed)
    }

    func testClosingAdmittedGateRejectsLateEntryUntilTheAdmittedWorkLeaves() {
        let gate = CaptureCallbackAdmission()
        XCTAssertEqual(gate.enter(), .admitted)
        gate.close()
        gate.close()
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .closed, "Closed takes precedence over overlapping")
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertTrue(gate.leave())
        XCTAssertTrue(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .closed)
        XCTAssertFalse(gate.leave())
        XCTAssertTrue(gate.isClosedAndQuiescent)
    }

    func testInvalidAndDoubleLeaveDoNotChangeAnIdleGate() {
        let gate = CaptureCallbackAdmission()
        XCTAssertFalse(gate.leave())
        XCTAssertFalse(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .admitted)
        XCTAssertTrue(gate.leave())
        XCTAssertFalse(gate.leave())
        XCTAssertEqual(gate.enter(), .admitted)
        XCTAssertTrue(gate.leave())
        gate.close()
        XCTAssertFalse(gate.leave())
        XCTAssertTrue(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .closed)
    }

    func testRetainedOldEpochCallbackRejectsAfterReplacement() {
        let oldGate = CaptureCallbackAdmission()
        let oldPayload = AdmissionPayload()
        let oldCallback: @Sendable () -> CaptureCallbackEntryResult = {
            let result = oldGate.enter()
            if result == .admitted {
                oldPayload.value += 1
                _ = oldGate.leave()
            }
            return result
        }
        XCTAssertEqual(oldCallback(), .admitted)
        XCTAssertEqual(oldPayload.value, 1)
        oldGate.close()

        let replacement = CaptureCallbackAdmission()
        XCTAssertEqual(replacement.enter(), .admitted)
        XCTAssertEqual(oldCallback(), .closed)
        XCTAssertEqual(oldPayload.value, 1, "A retained old closure must not perform late work")
        XCTAssertTrue(oldGate.isClosedAndQuiescent)
        XCTAssertTrue(replacement.leave())
        XCTAssertEqual(replacement.enter(), .admitted)
        XCTAssertTrue(replacement.leave())
    }

    func testConcurrentCloseWaitsForAdmittedWorkAndPublishesItToTheStopper() {
        let roundCount = 256
        let epochs = (0..<roundCount).map { _ in AdmissionEpoch() }
        let entryObservations = AdmissionEntryObservations()
        let closeObservations = AdmissionCloseObservations()
        let entryStart = DispatchSemaphore(value: 0)
        let closeStart = DispatchSemaphore(value: 0)
        let entryDone = DispatchSemaphore(value: 0)
        let closeDone = DispatchSemaphore(value: 0)
        let admissionAttempted = DispatchSemaphore(value: 0)
        let releaseWork = DispatchSemaphore(value: 0)
        let signals = AdmissionAtomicSignals()
        let group = DispatchGroup()
        let deadline = DispatchTime.now() + .seconds(2)
        let entryQueue = DispatchQueue(label: "LocalMinutes.tests.admission.callback")
        let closeQueue = DispatchQueue(label: "LocalMinutes.tests.admission.stopper")

        entryQueue.async(group: group) {
            entryObservations.entries.reserveCapacity(roundCount)
            entryObservations.leaves.reserveCapacity(roundCount)
            for index in 0..<roundCount {
                guard entryStart.wait(timeout: deadline) == .success else {
                    entryObservations.timedOut = true
                    return
                }
                let epoch = epochs[index]
                let result = epoch.gate.enter()
                entryObservations.entries.append(result)
                if index % 2 == 0 {
                    // Test scheduling only: force an admitted callback to remain
                    // in flight while the other thread closes its epoch.
                    admissionAttempted.signal()
                    guard releaseWork.wait(timeout: deadline) == .success else {
                        if result == .admitted { _ = epoch.gate.leave() }
                        entryObservations.timedOut = true
                        entryDone.signal()
                        return
                    }
                }
                if result == .admitted {
                    epoch.payload.value = index + 1
                    entryObservations.leaves.append(epoch.gate.leave())
                } else {
                    // An unsuccessful entrant must never release another claim.
                    entryObservations.leaves.append(nil)
                }
                entryDone.signal()
            }
        }

        closeQueue.async(group: group) {
            closeObservations.values.reserveCapacity(roundCount)
            closeObservations.lateEntries.reserveCapacity(roundCount)
            for index in 0..<roundCount {
                guard closeStart.wait(timeout: deadline) == .success else {
                    closeObservations.timedOut = true
                    return
                }
                let epoch = epochs[index]
                if index % 2 == 0 {
                    guard admissionAttempted.wait(timeout: deadline) == .success else {
                        closeObservations.timedOut = true
                        closeDone.signal()
                        return
                    }
                }
                epoch.gate.close()
                closeObservations.lateEntries.append(epoch.gate.enter())
                if index % 2 == 0 {
                    if epoch.gate.isClosedAndQuiescent {
                        closeObservations.prematureQuiescence = true
                    } else {
                        signals.sawConcurrentClosedClaim.store(true, ordering: .releasing)
                    }
                    releaseWork.signal()
                }
                while !epoch.gate.isClosedAndQuiescent {
                    if DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds {
                        closeObservations.timedOut = true
                        closeDone.signal()
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.000_01)
                }
                // This read has no callback-to-stopper semaphore handoff.
                // The gate's quiescent acquire must observe the leave release.
                closeObservations.values.append(epoch.payload.value)
                closeDone.signal()
            }
        }

        var completedRounds = 0
        var schedulingTimedOut = false
        for _ in 0..<roundCount {
            entryStart.signal()
            closeStart.signal()
            guard entryDone.wait(timeout: deadline) == .success,
                  closeDone.wait(timeout: deadline) == .success else {
                schedulingTimedOut = true
                break
            }
            completedRounds += 1
        }
        guard group.wait(timeout: deadline + .milliseconds(250)) == .success else {
            XCTFail("Callback admission workers exceeded the single bounded deadline")
            return
        }
        XCTAssertFalse(schedulingTimedOut)
        XCTAssertFalse(entryObservations.timedOut)
        XCTAssertFalse(closeObservations.timedOut)
        XCTAssertFalse(closeObservations.prematureQuiescence)
        XCTAssertTrue(signals.sawConcurrentClosedClaim.load(ordering: .acquiring))
        XCTAssertEqual(completedRounds, roundCount)
        XCTAssertEqual(entryObservations.entries.count, roundCount)
        XCTAssertEqual(entryObservations.leaves.count, roundCount)
        XCTAssertEqual(closeObservations.values.count, roundCount)
        XCTAssertTrue(closeObservations.lateEntries.allSatisfy { $0 == .closed })

        var mismatches = 0
        let observedCount = min(
            entryObservations.entries.count,
            min(entryObservations.leaves.count, closeObservations.values.count)
        )
        for index in 0..<observedCount {
            switch entryObservations.entries[index] {
            case .admitted:
                if entryObservations.leaves[index] != true ||
                        closeObservations.values[index] != index + 1 {
                    mismatches += 1
                }
            case .closed:
                if index % 2 == 0 || entryObservations.leaves[index] != nil ||
                        closeObservations.values[index] != 0 {
                    mismatches += 1
                }
            case .overlapping:
                mismatches += 1
            }
            if !epochs[index].gate.isClosedAndQuiescent { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0, "Close must reject late callbacks and publish every admitted exit")
    }

    func testSequentialAdmissionsOnDifferentThreadsPublishThePreviousCallbacksWork() {
        let gate = CaptureCallbackAdmission()
        let payload = AdmissionPayload()
        let observations = [AdmissionReuseObservations(), AdmissionReuseObservations()]
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let deadline = DispatchTime.now() + .seconds(2)
        let attemptsPerWorker = 4_000
        for worker in 0..<2 {
            let queue = DispatchQueue(label: "LocalMinutes.tests.admission.reuse.\(worker)")
            queue.async(group: group) {
                let observation = observations[worker]
                guard start.wait(timeout: deadline) == .success else {
                    observation.timedOut = true
                    return
                }
                for attempt in 0..<attemptsPerWorker {
                    if attempt % 64 == 0 &&
                            DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds {
                        observation.timedOut = true
                        return
                    }
                    switch gate.enter() {
                    case .admitted:
                        // Only the gate hands this ordinary value between the
                        // two callback threads: entry acquire, then leave release.
                        payload.value += 1
                        observation.admitted += 1
                        if !gate.leave() { observation.failedLeave = true }
                    case .overlapping:
                        observation.overlapping += 1
                    case .closed:
                        observation.unexpectedClosed += 1
                    }
                }
            }
        }
        start.signal()
        start.signal()
        guard group.wait(timeout: deadline + .milliseconds(250)) == .success else {
            XCTFail("Callback reuse workers exceeded the single bounded deadline")
            return
        }
        let admitted = observations.reduce(0) { $0 + $1.admitted }
        let overlapping = observations.reduce(0) { $0 + $1.overlapping }
        let unexpectedClosed = observations.reduce(0) { $0 + $1.unexpectedClosed }
        XCTAssertTrue(observations.allSatisfy { !$0.timedOut && !$0.failedLeave })
        XCTAssertEqual(unexpectedClosed, 0)
        XCTAssertGreaterThan(admitted, 0)
        XCTAssertEqual(admitted + overlapping, attemptsPerWorker * 2)
        XCTAssertEqual(payload.value, admitted)
        gate.close()
        XCTAssertTrue(gate.isClosedAndQuiescent)
        XCTAssertEqual(gate.enter(), .closed)
        XCTAssertFalse(gate.leave())
    }
}
