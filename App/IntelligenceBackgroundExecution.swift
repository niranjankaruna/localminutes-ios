#if os(iOS)
import BackgroundTasks
import Foundation
import UIKit

enum IntelligenceBackgroundError: Error { case busy, expired }

@MainActor
protocol IntelligenceBackgroundActivity: AnyObject, Sendable {
    func waitUntilReady() async throws
    func report(_ progress: IntelligenceProgress)
    func cancelPendingStart()
    func finish(success: Bool)
}

@MainActor
protocol IntelligenceBackgroundProviding: AnyObject, Sendable {
    func start(request: IntelligenceRequest,
               expiration: @escaping @MainActor @Sendable () -> Void) -> any IntelligenceBackgroundActivity
}

/// Owned by services, independent of scene activation. Only explicit Cancel,
/// resource pressure, or the exact system task's expiration stops the work.
@MainActor
final class IntelligenceBackgroundExecution {
    @MainActor private final class Use {
        let id: UUID
        var expired = false
        var cancelWork: (() -> Void)?
        init(id: UUID) { self.id = id }
    }
    private let provider: any IntelligenceBackgroundProviding
    private var current: Use?

    init(provider: any IntelligenceBackgroundProviding) { self.provider = provider }

    func run<Value: Sendable>(_ request: IntelligenceRequest,
        operation: @escaping @MainActor @Sendable (@escaping IntelligenceProgressReporter) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard current == nil else { throw IntelligenceBackgroundError.busy }
        let use = Use(id: request.id)
        current = use
        let activity = provider.start(request: request) { [weak self, weak use] in
            guard let self, let use, self.current === use else { return }
            use.expired = true
            use.cancelWork?()
        }
        let work = Task { @MainActor in
            try await activity.waitUntilReady()
            try Task.checkCancellation()
            guard !use.expired else { throw IntelligenceBackgroundError.expired }
            return try await operation { [weak self, weak use] progress in
                Task { @MainActor in
                    guard let self, let use, self.current === use, !use.expired else { return }
                    activity.report(progress)
                }
            }
        }
        use.cancelWork = { work.cancel(); activity.cancelPendingStart() }
        if use.expired { use.cancelWork?() }
        return try await withTaskCancellationHandler {
            do {
                let result = try await work.value
                // The operation includes native drain, unload, and persistence.
                activity.finish(success: true)
                use.cancelWork = nil; current = nil
                return result
            } catch {
                activity.finish(success: false)
                use.cancelWork = nil; current = nil
                if use.expired { throw IntelligenceBackgroundError.expired }
                throw error
            }
        } onCancel: {
            Task { @MainActor in
                guard self.current === use else { return }
                use.cancelWork?()
            }
        }
    }
}

@MainActor
final class SystemIntelligenceBackgroundProvider: IntelligenceBackgroundProviding {
    func start(request: IntelligenceRequest,
               expiration: @escaping @MainActor @Sendable () -> Void) -> any IntelligenceBackgroundActivity {
        if #available(iOS 26.0, *), UIApplication.shared.applicationState == .active,
           let bundleID = Bundle.main.bundleIdentifier {
            // The OS registration must be unique even if a caller retries the
            // same application request object after an earlier failure.
            return ContinuedIntelligenceActivity(identifier: bundleID + ".intelligence." + UUID().uuidString,
                operation: request.operation, expiration: expiration)
        }
        return LimitedIntelligenceActivity(expiration: expiration)
    }
}

/// UIKit supplies only a finite allowance on older iOS, and bridges the time
/// between foreground submission and the continued-processing launch handler.
@MainActor
private final class IntelligenceBackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init(expiration: @escaping @MainActor @Sendable () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "LocalMinutes intelligence") { [weak self] in
            Task { @MainActor in
                expiration()
                self?.end()
            }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@MainActor
private final class LimitedIntelligenceActivity: IntelligenceBackgroundActivity {
    private var assertion: IntelligenceBackgroundAssertion?
    private var expired = false
    init(expiration: @escaping @MainActor @Sendable () -> Void) {
        assertion = IntelligenceBackgroundAssertion { [weak self] in
            self?.expired = true
            expiration()
        }
    }
    func waitUntilReady() async throws {
        try Task.checkCancellation()
        if expired { throw IntelligenceBackgroundError.expired }
    }
    func report(_ progress: IntelligenceProgress) {}
    func cancelPendingStart() {}
    func finish(success: Bool) { assertion?.end(); assertion = nil }
}

@available(iOS 26.0, *)
@MainActor
private final class ContinuedIntelligenceActivity: IntelligenceBackgroundActivity {
    private let identifier: String
    private let title: String
    private let expiration: @MainActor @Sendable () -> Void
    private var assertion: IntelligenceBackgroundAssertion?
    private var task: BGContinuedProcessingTask?
    private var waiter: CheckedContinuation<Void, Error>?
    private var launchTimeout: Task<Void, Never>?
    private var pending = true
    private var finished = false
    private var expired = false
    private var saving = false

    init(identifier: String, operation: IntelligenceOperation,
         expiration: @escaping @MainActor @Sendable () -> Void) {
        self.identifier = identifier; self.expiration = expiration
        switch operation {
        case .summary: title = "Summarizing meeting"
        case .question: title = "Answering meeting question"
        }
        assertion = IntelligenceBackgroundAssertion { [weak self] in self?.expire() }
        let scheduler = BGTaskScheduler.shared
        // Concrete unique identifiers avoid wildcard-handler matching ambiguity;
        // the permitted identifier in Info.plist supplies the wildcard prefix.
        guard scheduler.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false); return
                }
                self.receive(continued)
            }
        }) else { pending = false; return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
            title: title, subtitle: "Preparing on this iPhone")
        request.strategy = .fail
        // Local inference is CPU-only: no background GPU entitlement is needed.
        do { try scheduler.submit(request) }
        catch { pending = false }
        if pending {
            launchTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.pending, !self.finished else { return }
                // Some OS versions can accept a request without calling its
                // handler. Keep foreground generation usable with UIKit fallback.
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: self.identifier)
                self.pending = false
                self.waiter?.resume(); self.waiter = nil
            }
        }
    }

    func waitUntilReady() async throws {
        try Task.checkCancellation()
        guard !finished, !expired else { throw CancellationError() }
        if pending {
            try await withCheckedThrowingContinuation { waiter = $0 }
        }
        try Task.checkCancellation()
    }

    private func receive(_ task: BGContinuedProcessingTask) {
        guard pending, !finished, !expired else { task.setTaskCompleted(success: false); return }
        self.task = task; pending = false
        launchTimeout?.cancel(); launchTimeout = nil
        task.progress.totalUnitCount = 1
        task.progress.completedUnitCount = 0
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        assertion?.end(); assertion = nil
        waiter?.resume(); waiter = nil
    }

    private func expire() {
        guard !finished, !expired else { return }
        expired = true
        expiration()
        cancelPendingStart()
    }

    func cancelPendingStart() {
        guard pending else { return }
        pending = false
        launchTimeout?.cancel(); launchTimeout = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        waiter?.resume(throwing: CancellationError()); waiter = nil
    }

    func report(_ value: IntelligenceProgress) {
        guard let task, !finished, !expired else { return }
        let detail: String
        switch value {
        case .preparing:
            guard task.progress.completedUnitCount == 0, !saving else { return }
            detail = "Preparing on this iPhone"
        case .summaryChunks(let completed, let total):
            guard !saving, total >= 0, total <= Int.max - 2, completed >= 0, completed <= total,
                  Int64(completed) + 1 >= task.progress.completedUnitCount else { return }
            task.progress.totalUnitCount = Int64(total) + 2
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(completed) + 1)
            detail = "Summarized \(completed) of \(total) sections"
        case .answering:
            guard !saving else { return }
            task.progress.totalUnitCount = 3; task.progress.completedUnitCount = 1
            detail = "Reading meeting evidence"
        case .saving:
            saving = true
            task.progress.completedUnitCount = max(0, task.progress.totalUnitCount - 1)
            detail = "Saving on this iPhone"
        }
        task.updateTitle(title, subtitle: detail)
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        cancelPendingStart()
        launchTimeout?.cancel(); launchTimeout = nil
        if let task {
            task.expirationHandler = nil
            if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
            task.setTaskCompleted(success: success && !expired)
            self.task = nil
        }
        assertion?.end(); assertion = nil
    }
}
#endif
