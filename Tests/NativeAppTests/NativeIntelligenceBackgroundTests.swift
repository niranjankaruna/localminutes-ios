#if os(iOS)
import Foundation
import UIKit
import XCTest
@testable import LocalMinutes

/// Real application orchestration with only the OS execution allowance replaced.
/// These tests establish ownership, not physical locked-device execution time.
@MainActor
final class NativeIntelligenceBackgroundTests: XCTestCase {
    func testImmediateCheckpointFailureDrainsTheLastPhaseBeforeFreezingProgress() async throws {
        let provider = BackgroundTestProvider()
        let runner = IntelligenceBackgroundExecution(provider: provider)
        let tracker = IntelligenceProgressTracker(operation: .summary)
        do {
            let _: Int = try await runner.run(request(), progress: tracker) { report in
                report(.summaryWork(.init(phase: .indexing, completedFraction: 0, operationFraction: 0.25)))
                report(.summaryWork(.init(phase: .checkpointing, completedFraction: 0.25, operationFraction: 0)))
                throw SummaryCheckpointError.invalidInput
            }
            XCTFail("Checkpoint rejection must fail the operation")
        } catch { XCTAssertEqual(error as? SummaryCheckpointError, .invalidInput) }
        XCTAssertEqual(tracker.detail, "Saving reading progress")
        XCTAssertEqual(tracker.succeeded, false)
        XCTAssertEqual(provider.activities.first?.reports.last,
            .summaryWork(.init(phase: .checkpointing, completedFraction: 0.25, operationFraction: 0)))
    }

    func testAllowanceStaysOwnedThroughWorkAndProgressUntilCompletion() async throws {
        let provider = BackgroundTestProvider()
        let runner = IntelligenceBackgroundExecution(provider: provider)
        let progress = IntelligenceProgressTracker(operation: .summary)
        let gate = BackgroundTestWork()
        let task = Task { try await runner.run(request(), progress: progress) { report in try await gate.perform(report) } }
        try await eventually { gate.started && provider.activities.first?.reports.isEmpty == false }
        let activity = try XCTUnwrap(provider.activities.first)
        XCTAssertTrue(activity.finished.isEmpty)
        XCTAssertTrue(provider.trackers.first === progress, "Screen and system activity must share one tracker")
        XCTAssertLessThan(progress.display().percentage, 100)
        gate.release()
        let result = try await task.value
        XCTAssertEqual(result, 42)
        XCTAssertEqual(activity.finished, [true])
        XCTAssertEqual(progress.display().percentage, 100)
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

    func testNativeCountersAdvanceSystemProgressInsideTheFirstUnfinishedSection() {
        var progress = IntelligenceBackgroundProgress()
        progress.report(.loadingModel(completedBytes: 128, totalBytes: 256))
        let loading = progress.completedUnitCount
        progress.report(.loadingModel(completedBytes: 256, totalBytes: 256))
        progress.report(.summaryChunks(completed: 0, total: 2))
        let planned = progress.completedUnitCount
        progress.report(.generating(.promptTokens(completed: 128, total: 512)))
        let reading = progress.completedUnitCount
        progress.report(.generating(.promptTokens(completed: 512, total: 512)))
        let read = progress.completedUnitCount
        progress.report(.generating(.responseTokens(completed: 1, limit: 1_024)))
        let writing = progress.completedUnitCount
        progress.report(.generating(.responseTokens(completed: 512, limit: 1_024)))
        let written = progress.completedUnitCount
        progress.report(.summaryChunks(completed: 1, total: 2))
        let checkpointed = progress.completedUnitCount
        XCTAssertEqual([loading, planned, reading, read, writing, written, checkpointed],
                       [loading, planned, reading, read, writing, written, checkpointed].sorted())
        XCTAssertGreaterThan(reading, planned)
        XCTAssertGreaterThan(written, writing)
        XCTAssertGreaterThan(checkpointed, written, "Native work must leave room for validation and checkpointing")
        progress.report(.generating(.promptTokens(completed: 128, total: 512)))
        XCTAssertGreaterThan(progress.completedUnitCount, checkpointed, "The next section must keep advancing")
        progress.report(.summaryChunks(completed: 2, total: 2))
        progress.report(.saving)
        XCTAssertLessThan(progress.completedUnitCount, progress.totalUnitCount, "Only committed success may finish the system task")
        let saving = progress.completedUnitCount
        XCTAssertFalse(progress.report(.generating(.responseTokens(completed: 900, limit: 1_024))))
        XCTAssertFalse(progress.report(.preparing))
        XCTAssertEqual(progress.completedUnitCount, saving)
        XCTAssertEqual(progress.detail, IntelligenceProgress.saving.message)
    }

    func testQuestionCountersAdvanceAndInvalidOrRegressingReportsAreIgnored() {
        var progress = IntelligenceBackgroundProgress()
        progress.report(.answering)
        progress.report(.generating(.promptTokens(completed: 128, total: 512)))
        let reading = progress.completedUnitCount
        progress.report(.generating(.responseTokens(completed: 12, limit: 192)))
        let writing = progress.completedUnitCount
        XCTAssertGreaterThan(writing, reading)
        for invalid in [IntelligenceProgress.generating(.responseTokens(completed: 0, limit: 192)),
                        .generating(.responseTokens(completed: 193, limit: 192)),
                        .generating(.promptTokens(completed: -1, total: 512)),
                        .generating(.promptTokens(completed: 512, total: 512)),
                        .summaryChunks(completed: 0, total: 0), .loadingModel(completedBytes: 0, totalBytes: 0)] {
            XCTAssertFalse(progress.report(invalid))
            XCTAssertEqual(progress.completedUnitCount, writing)
        }
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
        let meetingID = UUID()
        var controller: MeetingIntelligenceController? = services.intelligenceController(for: meetingID)
        weak var retained = controller
        do {
            controller?.generateSummary()
            try await eventually { provider.activities.first?.waiting == true }
            controller?.leaveMeeting()
            controller = nil
            for _ in 0..<8 { await Task.yield() }
            XCTAssertEqual(retained?.isRunning, true)
            XCTAssertTrue(provider.activities[0].finished.isEmpty)
            let reopened = services.intelligenceController(for: meetingID)
            XCTAssertTrue(reopened === retained, "Reopening after lock must rejoin the running controller")
            XCTAssertTrue(reopened.isRunning)
            XCTAssertTrue(services.intelligenceController(for: UUID()) !== reopened)
            reopened.cancel()
            try await eventually { !reopened.isRunning }
            XCTAssertEqual(provider.activities[0].finished, [false])
            try await services.store.close()
        } catch {
            retained?.cancel()
            try? await services.store.close()
            try? removeRoot(root, parent: parent)
            throw error
        }
        try removeRoot(root, parent: parent)
    }

    func testExpiredSummaryRemainsResumableWithAnExplanationInsteadOfReturningToTheInitialState() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("background-intelligence-\(UUID().uuidString)", isDirectory: true)
        let provider = BackgroundTestProvider(ready: false)
        let services = try LocalMinutesServices(rootURL: root, backgroundProvider: provider)
        let controller = MeetingIntelligenceController(services: services, meetingID: UUID())
        do {
            controller.generateSummary()
            try await eventually { provider.activities.first?.waiting == true }
            controller.leaveMeeting(cancelGeneration: false)
            provider.expirations[0]()
            try await eventually { !controller.isRunning }
            XCTAssertTrue(controller.summaryPaused)
            XCTAssertTrue(controller.message?.contains("Resume summary") == true)
            XCTAssertNil(controller.errorMessage)
            XCTAssertEqual(provider.activities[0].finished, [false])
            // A retry is a fresh system allowance for the same meeting, and an
            // old expiration cannot cancel it or reset the resumed presentation.
            controller.generateSummary()
            try await eventually { provider.activities.count == 2 && provider.activities[1].waiting }
            XCTAssertFalse(controller.summaryPaused)
            provider.expirations[0]()
            XCTAssertTrue(controller.isRunning)
            controller.cancel()
            try await eventually { !controller.isRunning }
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
    var trackers: [IntelligenceProgressTracker] = []
    var expirations: [@MainActor @Sendable () -> Void] = []
    init(ready: Bool = true) { self.ready = ready }
    func start(request: IntelligenceRequest, progress: IntelligenceProgressTracker,
               expiration: @escaping @MainActor @Sendable () -> Void) -> any IntelligenceBackgroundActivity {
        let activity = BackgroundTestActivity(ready: ready)
        trackers.append(progress)
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
