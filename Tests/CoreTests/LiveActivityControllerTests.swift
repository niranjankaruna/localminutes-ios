import Foundation
import XCTest
@testable import LocalMinutesCore

// Only ActivityKit backend/handle calls are doubled.
// No recording state, SDK compilation, entitlement or device success is implied.
private enum ActivityTestError: Error { case requestRejected, timedOut }

@MainActor
private final class ActivityTestProbe {
    var events: [LiveActivityResourceEvent] = []
    var finished = false
    var started = false
}

@MainActor
private final class ActivityTestHandle: LiveActivityHandle {
    private(set) var state: LiveActivityResourceState
    private(set) var observer: LiveActivityStateObserver?
    private(set) var updates: [LiveActivityStatus] = []
    private(set) var endings: [LiveActivityStatus] = []
    private(set) var trace: [String] = []
    var blockUpdate = false
    var blockEnd = false
    var updateOutcome: LiveActivityOperationOutcome = .applied
    var endOutcome: LiveActivityOperationOutcome = .applied
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private var endWaiters: [CheckedContinuation<Void, Never>] = []
    var updateIsWaiting: Bool { !updateWaiters.isEmpty }
    var endIsWaiting: Bool { !endWaiters.isEmpty }

    init(state: LiveActivityResourceState = .active) { self.state = state }

    func setStateObserver(_ observer: LiveActivityStateObserver?) {
        self.observer = observer
    }

    func update(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        trace.append("update-begin")
        updates.append(status)
        if blockUpdate {
            await withCheckedContinuation { updateWaiters.append($0) }
        }
        trace.append("update-settled")
        return updateOutcome
    }

    func end(status: LiveActivityStatus) async -> LiveActivityOperationOutcome {
        trace.append("end-begin")
        endings.append(status)
        if blockEnd {
            await withCheckedContinuation { endWaiters.append($0) }
        }
        if endOutcome == .applied { emit(.ended) }
        trace.append("end-settled")
        return endOutcome
    }

    func emit(_ state: LiveActivityResourceState) {
        self.state = state
        observer?(state)
    }

    func releaseUpdate() {
        blockUpdate = false
        let pending = updateWaiters
        updateWaiters.removeAll()
        for continuation in pending { continuation.resume() }
    }

    func releaseEnd() {
        blockEnd = false
        let pending = endWaiters
        endWaiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class ActivityTestBackend: LiveActivityBackend {
    var areActivitiesEnabled = true
    var rejectRequest = false
    private var handles: [ActivityTestHandle]
    private(set) var requests: [UUID] = []
    private(set) var statuses: [LiveActivityStatus] = []

    init(handles: [ActivityTestHandle]) { self.handles = handles }

    func request(sessionID: UUID, status: LiveActivityStatus) throws -> any LiveActivityHandle {
        requests.append(sessionID)
        statuses.append(status)
        guard !rejectRequest, !handles.isEmpty else { throw ActivityTestError.requestRejected }
        return handles.removeFirst()
    }
}

@MainActor
private final class ActivityTestHarness {
    let id = UUID()
    let first: ActivityTestHandle
    let second: ActivityTestHandle
    let backend: ActivityTestBackend
    let probe: ActivityTestProbe
    let controller: LiveActivityController

    init(state: LiveActivityResourceState = .active) {
        let firstHandle = ActivityTestHandle(state: state)
        let secondHandle = ActivityTestHandle()
        let boundary = ActivityTestBackend(handles: [firstHandle, secondHandle])
        let eventProbe = ActivityTestProbe()
        first = firstHandle
        second = secondHandle
        backend = boundary
        probe = eventProbe
        controller = LiveActivityController(backend: boundary) { eventProbe.events.append($0) }
    }

    func releaseAll() {
        first.releaseUpdate()
        first.releaseEnd()
        second.releaseUpdate()
        second.releaseEnd()
    }
}

@MainActor
final class LiveActivityControllerTests: XCTestCase {
    private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !predicate() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    private func complete(
        file: StaticString = #filePath, line: UInt = #line,
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        let completion = ActivityTestProbe()
        let task = Task {
            await operation()
            completion.finished = true
        }
        guard await waitUntil({ completion.finished }) else {
            task.cancel()
            XCTFail("Resource operation exceeded its bounded deadline", file: file, line: line)
            throw ActivityTestError.timedOut
        }
        await task.value
    }

    func testDisabledActivitiesNeverRequestOrReportActive() async {
        let h = ActivityTestHarness()
        h.backend.areActivitiesEnabled = false
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .unavailable)
        XCTAssertTrue(h.backend.requests.isEmpty)
        XCTAssertEqual(h.probe.events, [.unavailable(h.id, .disabled)])
        XCTAssertFalse(h.controller.snapshot().isActive)
        XCTAssertNil(h.controller.snapshot().sessionID)
    }

    func testThrowingRequestNeverReportsActiveOrRetainsAFabricatedHandle() async {
        let h = ActivityTestHarness()
        h.backend.rejectRequest = true
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .unavailable)
        XCTAssertEqual(h.backend.requests, [h.id])
        XCTAssertEqual(h.probe.events, [.unavailable(h.id, .requestFailed)])
        XCTAssertFalse(h.controller.snapshot().isActive)
        XCTAssertNil(h.controller.snapshot().sessionID)
    }

    func testPendingAndTerminalInitialHandlesNeverQualifyReadiness() async throws {
        for state in [LiveActivityResourceState.pending, .ended, .dismissed] {
            let h = ActivityTestHarness(state: state)
            defer { h.releaseAll() }
            XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .unavailable)
            XCTAssertEqual(h.backend.requests, [h.id])
            XCTAssertTrue(h.probe.events.contains(.unavailable(h.id, .notActive)))
            XCTAssertFalse(h.probe.events.contains(.active(h.id)))
            XCTAssertFalse(h.controller.snapshot().isActive)
            try await complete { await h.controller.end(sessionID: h.id, status: .failed) }
            XCTAssertEqual(h.first.endings, [.failed], "A returned resource still needs explicit cleanup")
            XCTAssertNil(h.controller.snapshot().sessionID)
        }
    }

    func testSameIDReusesOneHandleAndCompetingIDCannotReplaceIt() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .recording), .reused)
        XCTAssertEqual(h.controller.start(sessionID: UUID(), status: .preparing), .busy)
        XCTAssertEqual(h.backend.requests, [h.id])
        XCTAssertEqual(h.backend.statuses, [.preparing])
        XCTAssertEqual(h.probe.events, [.active(h.id)])
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id)
        XCTAssertTrue(h.controller.snapshot().isActive)
        try await complete { await h.controller.end(sessionID: h.id, status: .finished) }
    }

    func testMatchingUpdatesAndEndIgnoreStaleIDsAndStaleContentIsNotTermination() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        let unrelated = UUID()
        try await complete { await h.controller.update(sessionID: unrelated, status: .failed) }
        try await complete { await h.controller.end(sessionID: unrelated, status: .failed) }
        XCTAssertTrue(h.first.updates.isEmpty)
        XCTAssertTrue(h.first.endings.isEmpty)
        h.first.emit(.stale)
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id, "Outdated content is still an owned resource")
        XCTAssertFalse(h.controller.snapshot().isEnding)
        XCTAssertFalse(h.probe.events.contains(.lost(h.id)))
        try await complete { await h.controller.update(sessionID: h.id, status: .recording) }
        XCTAssertEqual(h.first.updates, [.recording])
        try await complete { await h.controller.end(sessionID: h.id, status: .finished) }
        try await complete { await h.controller.update(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.first.updates, [.recording])
        XCTAssertEqual(h.first.endings, [.finished])
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
        XCTAssertNil(h.controller.snapshot().sessionID)
    }

    func testDuplicateEndAcknowledgesOnceOnlyAfterRealEndSettles() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.blockEnd = true
        let firstCompletion = ActivityTestProbe()
        let secondCompletion = ActivityTestProbe()
        let first = Task {
            await h.controller.end(sessionID: h.id, status: .stopping)
            firstCompletion.finished = true
        }
        let waiting = await waitUntil { h.first.endIsWaiting }
        XCTAssertTrue(waiting)
        let second = Task {
            await h.controller.end(sessionID: h.id, status: .failed)
            secondCompletion.finished = true
        }
        defer { first.cancel(); second.cancel() }
        XCTAssertTrue(h.controller.snapshot().isEnding)
        XCTAssertFalse(h.controller.snapshot().isActive)
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .recording), .busy)
        XCTAssertEqual(h.controller.start(sessionID: UUID(), status: .preparing), .busy)
        h.first.emit(.ended)
        XCTAssertFalse(h.probe.events.contains(.ended(h.id)),
                       "A state notification cannot substitute for async end completion")
        XCTAssertFalse(h.probe.events.contains(.lost(h.id)), "Expected ending is not unexpected loss")
        XCTAssertFalse(firstCompletion.finished)
        h.first.releaseEnd()
        let returned = await waitUntil { firstCompletion.finished && secondCompletion.finished }
        XCTAssertTrue(returned)
        if returned { await first.value; await second.value }
        XCTAssertEqual(h.first.endings, [.stopping])
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
        XCTAssertNil(h.controller.snapshot().sessionID)
    }

    func testUnexpectedTerminalStateEmitsLossExactlyOnceWithoutCleanupSuccess() async throws {
        for state in [LiveActivityResourceState.ended, .dismissed] {
            let h = ActivityTestHarness()
            defer { h.releaseAll() }
            XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
            h.first.emit(state)
            h.first.emit(state)
            XCTAssertEqual(h.probe.events.filter { $0 == .lost(h.id) }.count, 1)
            XCTAssertFalse(h.probe.events.contains(.ended(h.id)))
            XCTAssertFalse(h.controller.snapshot().isActive)
            try await complete { await h.controller.update(sessionID: h.id, status: .recording) }
            XCTAssertTrue(h.first.updates.isEmpty)
        }
    }

    func testRetiredHandleCallbacksCannotTerminateAReplacementWithTheSameID() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        let oldObserver = try XCTUnwrap(h.first.observer)
        try await complete { await h.controller.end(sessionID: h.id, status: .finished) }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        XCTAssertEqual(h.backend.requests, [h.id, h.id])
        oldObserver(.dismissed)
        oldObserver(.ended)
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id)
        XCTAssertTrue(h.controller.snapshot().isActive)
        XCTAssertFalse(h.probe.events.contains(.lost(h.id)))
        XCTAssertEqual(h.probe.events.filter { $0 == .active(h.id) }.count, 2)
        h.second.emit(.dismissed)
        XCTAssertEqual(h.probe.events.filter { $0 == .lost(h.id) }.count, 1)
        XCTAssertFalse(h.controller.snapshot().isActive)
    }

    func testEndSettlesAdmittedUpdateAndRejectsLaterUpdatesBeforeAcknowledgement() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.blockUpdate = true
        let updateCompletion = ActivityTestProbe()
        let endCompletion = ActivityTestProbe()
        let updating = Task {
            await h.controller.update(sessionID: h.id, status: .recording)
            updateCompletion.finished = true
        }
        let waiting = await waitUntil { h.first.updateIsWaiting }
        XCTAssertTrue(waiting)
        let ending = Task {
            await h.controller.end(sessionID: h.id, status: .finished)
            endCompletion.finished = true
        }
        defer { updating.cancel(); ending.cancel() }
        let closing = await waitUntil { h.controller.snapshot().isEnding }
        XCTAssertTrue(closing)
        XCTAssertTrue(h.first.endings.isEmpty, "Real end must follow the already-admitted async update")
        try await complete { await h.controller.update(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.first.updates, [.recording])
        XCTAssertFalse(h.probe.events.contains(.ended(h.id)))
        h.first.releaseUpdate()
        let returned = await waitUntil { updateCompletion.finished && endCompletion.finished }
        XCTAssertTrue(returned)
        if returned { await updating.value; await ending.value }
        XCTAssertEqual(h.first.updates, [.recording])
        XCTAssertEqual(h.first.endings, [.finished])
        let updateSettled = try XCTUnwrap(h.first.trace.firstIndex(of: "update-settled"))
        let endBegan = try XCTUnwrap(h.first.trace.firstIndex(of: "end-begin"))
        XCTAssertLessThan(updateSettled, endBegan)
        XCTAssertEqual(h.probe.events.filter { $0 == .active(h.id) }.count, 1)
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
    }

    func testMissingEndDoesNotAcknowledgeCleanupAndCanBeRetried() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.endOutcome = .notFound
        try await complete { await h.controller.end(sessionID: h.id, status: .finished) }
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id,
                       "A missing exact SDK ID is not a performed end")
        XCTAssertFalse(h.controller.snapshot().isActive)
        XCTAssertFalse(h.controller.snapshot().isEnding, "The failed attempt has settled")
        XCTAssertEqual(h.probe.events.filter { $0 == .endFailed(h.id) }.count, 1)
        XCTAssertFalse(h.probe.events.contains(.ended(h.id)))
        XCTAssertNotNil(h.first.observer, "Keep terminal-state observation through retry")
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .recording), .busy)
        XCTAssertEqual(h.controller.start(sessionID: UUID(), status: .preparing), .busy)
        try await complete { await h.controller.update(sessionID: h.id, status: .recording) }
        XCTAssertTrue(h.first.updates.isEmpty, "End closes content updates even after a failure")
        h.first.endOutcome = .applied
        try await complete { await h.controller.end(sessionID: h.id, status: .finished) }
        XCTAssertEqual(h.first.endings, [.finished, .finished])
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
        XCTAssertNil(h.controller.snapshot().sessionID)
        XCTAssertNil(h.first.observer)
    }

    func testCoalescedMissingEndsReportOneFailureThenRetryUsesANewAttempt() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.endOutcome = .notFound
        h.first.blockEnd = true
        let one = ActivityTestProbe()
        let two = ActivityTestProbe()
        let first = Task {
            await h.controller.end(sessionID: h.id, status: .finished)
            one.finished = true
        }
        let waiting = await waitUntil { h.first.endIsWaiting }
        XCTAssertTrue(waiting)
        let second = Task {
            two.started = true
            await h.controller.end(sessionID: h.id, status: .failed)
            two.finished = true
        }
        defer { first.cancel(); second.cancel() }
        let duplicateEntered = await waitUntil { two.started }
        XCTAssertTrue(duplicateEntered)
        h.first.releaseEnd()
        let returned = await waitUntil { one.finished && two.finished }
        XCTAssertTrue(returned)
        if returned { await first.value; await second.value }
        XCTAssertEqual(h.first.endings, [.finished])
        XCTAssertEqual(h.probe.events.filter { $0 == .endFailed(h.id) }.count, 1)
        XCTAssertFalse(h.probe.events.contains(.ended(h.id)))
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id)
        h.first.endOutcome = .applied
        try await complete { await h.controller.end(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.first.endings, [.finished, .failed])
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
    }

    func testMissingUpdateRevokesReadinessOnceAndCannotBecomeAnEndSuccess() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.updateOutcome = .notFound
        try await complete { await h.controller.update(sessionID: h.id, status: .recording) }
        XCTAssertFalse(h.controller.snapshot().isActive)
        XCTAssertEqual(h.probe.events.filter { $0 == .updateFailed(h.id) }.count, 1)
        XCTAssertEqual(h.probe.events.filter { $0 == .lost(h.id) }.count, 1)
        h.first.emit(.dismissed)
        try await complete { await h.controller.update(sessionID: h.id, status: .recording) }
        XCTAssertEqual(h.first.updates, [.recording])
        XCTAssertEqual(h.probe.events.filter { $0 == .lost(h.id) }.count, 1)
        h.first.endOutcome = .notFound
        try await complete { await h.controller.end(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.probe.events.filter { $0 == .endFailed(h.id) }.count, 1)
        XCTAssertFalse(h.probe.events.contains(.ended(h.id)))
        XCTAssertEqual(h.controller.snapshot().sessionID, h.id)
        h.first.endOutcome = .applied
        try await complete { await h.controller.end(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
    }

    func testQueuedUpdateCannotReuseResourceAfterEarlierLookupFails() async throws {
        let h = ActivityTestHarness()
        defer { h.releaseAll() }
        XCTAssertEqual(h.controller.start(sessionID: h.id, status: .preparing), .active)
        h.first.blockUpdate = true
        h.first.updateOutcome = .notFound
        let one = ActivityTestProbe()
        let two = ActivityTestProbe()
        let first = Task {
            await h.controller.update(sessionID: h.id, status: .recording)
            one.finished = true
        }
        let waiting = await waitUntil { h.first.updateIsWaiting }
        XCTAssertTrue(waiting)
        let second = Task {
            two.started = true
            await h.controller.update(sessionID: h.id, status: .stopping)
            two.finished = true
        }
        defer { first.cancel(); second.cancel() }
        let queued = await waitUntil { two.started }
        XCTAssertTrue(queued)
        h.first.releaseUpdate()
        let returned = await waitUntil { one.finished && two.finished }
        XCTAssertTrue(returned)
        if returned { await first.value; await second.value }
        XCTAssertEqual(h.first.updates, [.recording])
        XCTAssertEqual(h.probe.events.filter { $0 == .updateFailed(h.id) }.count, 1)
        XCTAssertEqual(h.probe.events.filter { $0 == .lost(h.id) }.count, 1)
        try await complete { await h.controller.end(sessionID: h.id, status: .failed) }
        XCTAssertEqual(h.probe.events.filter { $0 == .ended(h.id) }.count, 1)
    }
}
