#if os(iOS)
import Foundation
import UIKit
import XCTest
@testable import LocalMinutes

/// Real application orchestration with only the OS execution allowance replaced.
/// These tests establish ownership, not physical locked-device execution time.
@MainActor
final class NativeIntelligenceBackgroundTests: XCTestCase {
    func testAllowanceStaysOwnedThroughWorkAndProgressUntilCompletion() async throws {
        let provider = BackgroundTestProvider()
        let runner = IntelligenceBackgroundExecution(provider: provider)
        let gate = BackgroundTestWork()
        let task = Task { try await runner.run(request()) { report in try await gate.perform(report) } }
        try await eventually { gate.started && provider.activities.first?.reports.isEmpty == false }
        let activity = try XCTUnwrap(provider.activities.first)
        XCTAssertTrue(activity.finished.isEmpty)
        gate.release()
        let result = try await task.value
        XCTAssertEqual(result, 42)
        XCTAssertEqual(activity.finished, [true])
    }

    func testExpirationCancelsOnlyOwnedWorkAndWaitsForDrainBeforeFinishingAllowance() async throws {
        let provider = BackgroundTestProvider()
        let runner = IntelligenceBackgroundExecution(provider: provider)
        let gate = BackgroundTestWork()
        let task = Task { try await runner.run(request()) { report in try await gate.perform(report) } }
        try await eventually { gate.started }
        let activity = try XCTUnwrap(provider.activities.first)
        provider.expirations[0]()
        XCTAssertTrue(activity.finished.isEmpty, "Expiration cannot pretend native work has already drained")
        gate.release()
        do { _ = try await task.value; XCTFail("Expired work returned a result") }
        catch IntelligenceBackgroundError.expired { }
        XCTAssertEqual(activity.finished, [false])
    }

    func testExplicitCancellationDuringSystemAdmissionDoesNotStartGeneration() async throws {
        let provider = BackgroundTestProvider(ready: false)
        let runner = IntelligenceBackgroundExecution(provider: provider)
        let gate = BackgroundTestWork()
        let task = Task { try await runner.run(request()) { report in try await gate.perform(report) } }
        try await eventually { provider.activities.first?.waiting == true }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled admission returned a result") }
        catch is CancellationError { }
        XCTAssertFalse(gate.started)
        XCTAssertEqual(provider.activities.first?.finished, [false])
    }

    func testOldExpirationCannotCancelAReplacementRequest() async throws {
        let provider = BackgroundTestProvider()
        let runner = IntelligenceBackgroundExecution(provider: provider)
        _ = try await runner.run(request()) { _ in 1 }
        let gate = BackgroundTestWork()
        let next = Task { try await runner.run(request()) { report in try await gate.perform(report) } }
        try await eventually { gate.started }
        provider.expirations[0]()
        gate.release()
        let result = try await next.value
        XCTAssertEqual(result, 42)
        XCTAssertEqual(provider.activities.map(\.finished), [[true], [true]])
    }

    func testBackgroundSceneHandlingKeepsControllerGenerationAliveUntilExplicitCancel() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("background-intelligence-\(UUID().uuidString)", isDirectory: true)
        let provider = BackgroundTestProvider(ready: false)
        let services = try LocalMinutesServices(rootURL: root, backgroundProvider: provider)
        let controller = MeetingIntelligenceController(services: services, meetingID: UUID())
        do {
            controller.generateSummary()
            try await eventually { provider.activities.first?.waiting == true }
            controller.leaveMeeting(cancelGeneration: false)
            for _ in 0..<8 { await Task.yield() }
            XCTAssertTrue(controller.isRunning)
            XCTAssertTrue(provider.activities[0].finished.isEmpty)
            controller.cancel()
            try await eventually { !controller.isRunning }
            XCTAssertEqual(provider.activities[0].finished, [false])
            try await services.store.close()
        } catch {
            controller.cancel()
            try? await services.store.close()
            try? removeRoot(root, parent: parent)
            throw error
        }
        try removeRoot(root, parent: parent)
    }

    func testAppDeclaresBackgroundProcessingAndTheMatchingIdentifierPrefix() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String], ["audio", "processing"])
        let bundle = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String],
                       [bundle + ".intelligence.*"])
    }

    private func request() -> IntelligenceRequest { .init(meetingID: UUID(), operation: .summary) }
    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            if ContinuousClock.now >= deadline { XCTFail("Background operation did not reach its expected state"); throw BackgroundTestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func removeRoot(_ root: URL, parent: URL) throws {
        guard root.deletingLastPathComponent() == parent,
              root.lastPathComponent.hasPrefix("background-intelligence-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root else { throw BackgroundTestError.unsafeRoot }
        try FileManager.default.removeItem(at: root)
    }
}

private enum BackgroundTestError: Error { case timeout, unsafeRoot }

@MainActor private final class BackgroundTestWork {
    var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func perform(_ report: IntelligenceProgressReporter) async throws -> Int {
        started = true
        report(.summaryChunks(completed: 0, total: 2))
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        report(.summaryChunks(completed: 2, total: 2))
        report(.saving)
        return 42
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private final class BackgroundTestProvider: IntelligenceBackgroundProviding {
    let ready: Bool
    var activities: [BackgroundTestActivity] = []
    var expirations: [@MainActor @Sendable () -> Void] = []
    init(ready: Bool = true) { self.ready = ready }
    func start(request: IntelligenceRequest,
               expiration: @escaping @MainActor @Sendable () -> Void) -> any IntelligenceBackgroundActivity {
        let activity = BackgroundTestActivity(ready: ready)
        activities.append(activity); expirations.append(expiration)
        return activity
    }
}

@MainActor private final class BackgroundTestActivity: IntelligenceBackgroundActivity {
    let ready: Bool
    var waiting = false
    var finished: [Bool] = []
    var reports: [IntelligenceProgress] = []
    private var continuation: CheckedContinuation<Void, Error>?
    init(ready: Bool) { self.ready = ready }
    func waitUntilReady() async throws {
        try Task.checkCancellation()
        if !ready {
            waiting = true
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        try Task.checkCancellation()
    }
    func report(_ progress: IntelligenceProgress) { reports.append(progress) }
    func cancelPendingStart() { continuation?.resume(throwing: CancellationError()); continuation = nil }
    func finish(success: Bool) { finished.append(success) }
}
#endif
