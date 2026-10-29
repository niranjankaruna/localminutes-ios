#if os(iOS)
import Foundation
import Observation

/// One app-owned clock and work projection feed both the detail screen and the
/// system task. ContinuousClock includes time spent with the phone locked and
/// cannot jump when the wall clock changes. Rendering never advances work.
@MainActor @Observable
final class IntelligenceProgressTracker {
    private struct Sample {
        let time: ContinuousClock.Instant
        let fraction: Double
    }
    private enum Stage { case waiting, loading, mapping, reading, writing, saving }

    let operation: IntelligenceOperation
    private let startedAt: ContinuousClock.Instant
    private(set) var progress = IntelligenceBackgroundProgress()
    private(set) var succeeded: Bool?
    private var finishedAt: ContinuousClock.Instant?
    private var stage = Stage.waiting
    private var samples: [Sample] = []
    private var consolidating = false
    private var workStartedAt: ContinuousClock.Instant?
    private var currentWork: SummaryWorkProgress?
    private var measuredWorkSeconds: Double = 0
    private var measuredWorkFraction: Double = 0
    private var lastWorkReportAt: ContinuousClock.Instant?

    init(operation: IntelligenceOperation, startedAt: ContinuousClock.Instant = .now) {
        self.operation = operation; self.startedAt = startedAt
    }

    var title: String {
        switch operation { case .summary: "Summary"; case .question: "Answer" }
    }
    var runningTitle: String {
        switch operation { case .summary: "Summarizing"; case .question: "Finding an answer" }
    }
    var detail: String {
        if stage == .saving {
            switch operation { case .summary: return "Saving the summary…"; case .question: return "Saving the answer…" }
        }
        if consolidating { return IntelligenceProgress.consolidatingSummary(completed: 0, total: 1).message }
        return stage == .waiting ? "Waiting for iOS to start generation…" : progress.detail
    }

    @discardableResult
    func report(_ value: IntelligenceProgress, at now: ContinuousClock.Instant = .now) -> Bool {
        guard finishedAt == nil, progress.report(value) else { return false }
        let next: Stage
        switch value {
        case .preparing, .loadingModel, .planningSummary: next = .loading
        case .summaryChunks, .answering, .generationStarted: next = .mapping
        case .consolidatingSummary: consolidating = true; next = .mapping
        case .summaryWork(let work):
            consolidating = false
            // Learn from complete inference calls, including prompt processing,
            // output, validation and repairs. Restored index checkpoints have
            // no timed operation and cannot create an implausibly fast rate.
            if let previous = currentWork, previous.operationFraction > 0,
               let began = workStartedAt,
               work.completedFraction + 0.000001 >= previous.completedFraction + previous.operationFraction {
                let duration = Self.seconds(began.duration(to: now))
                if duration >= 1 {
                    measuredWorkSeconds = measuredWorkSeconds * 0.8 + duration
                    // A successful check also retires its unused repair budget.
                    measuredWorkFraction = measuredWorkFraction * 0.8
                        + work.completedFraction - previous.completedFraction
                }
            }
            currentWork = work
            workStartedAt = work.operationFraction > 0 ? now : nil
            lastWorkReportAt = now
            samples = []
            next = .mapping
        case .generating(.promptTokens): next = .reading
        case .generating(.responseTokens): next = .writing
        case .saving: consolidating = false; next = .saving
        }
        let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
        // Reset after phase changes, recovered checkpoints, or a long pause.
        // Fast file verification must not predict slow response generation.
        if next != stage || samples.last.map({ Self.seconds($0.time.duration(to: now)) > 15 }) == true {
            samples = []
        }
        stage = next
        if currentWork != nil { lastWorkReportAt = now }
        if next == .reading || next == .writing {
            if let last = samples.last {
                if fraction > last.fraction, Self.seconds(last.time.duration(to: now)) >= 1 {
                    samples.append(.init(time: now, fraction: fraction))
                }
            } else { samples = [.init(time: now, fraction: fraction)] }
            while samples.count > 2, let first = samples.first,
                  Self.seconds(first.time.duration(to: now)) > 30 { samples.removeFirst() }
        }
        return true
    }

    func finish(success: Bool, at now: ContinuousClock.Instant = .now) {
        guard finishedAt == nil else { return }
        finishedAt = max(startedAt, now)
        succeeded = success
        samples = []
    }

    func display(at now: ContinuousClock.Instant = .now) -> IntelligenceProgressDisplay {
        let fraction = succeeded == true ? 1 : Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
        let elapsed = max(0, startedAt.duration(to: finishedAt ?? max(startedAt, now)).components.seconds)
        let remaining = estimate(at: now)
        return .init(fraction: fraction, percentage: succeeded == true ? 100 : min(99, Int(fraction * 100)),
            elapsedSeconds: elapsed, remainingSeconds: remaining, finished: finishedAt != nil)
    }

    private func estimate(at now: ContinuousClock.Instant) -> Int64? {
        if currentWork != nil {
            guard finishedAt == nil, stage != .saving, let lastWorkReportAt,
                  Self.seconds(lastWorkReportAt.duration(to: now)) <= 15 else { return nil }
            if measuredWorkFraction > 0 {
                let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                let remainingWork = max(0.01, (0.98 - fraction) / 0.88)
                let seconds = remainingWork * measuredWorkSeconds / measuredWorkFraction
                guard seconds.isFinite, seconds < 86_400 else { return nil }
                // A token ceiling is not a known completion length. Do not
                // count down between reports or reach zero before the save.
                return Int64(max(1, seconds.rounded(.up)))
            }
            // Never extrapolate fast prompt ingestion over future writing.
            guard stage == .writing else { return nil }
        }
        guard finishedAt == nil, samples.count >= 2, let first = samples.first, let last = samples.last else { return nil }
        let measuredSeconds = Self.seconds(first.time.duration(to: last.time))
        let measuredWork = last.fraction - first.fraction
        let age = max(0, Self.seconds(last.time.duration(to: now)))
        guard measuredSeconds >= 3, measuredWork >= 0.001, age <= 15 else { return nil }
        let seconds = (1 - last.fraction) * measuredSeconds / measuredWork - (currentWork == nil ? age : 0)
        guard seconds.isFinite, seconds < 86_400 else { return nil }
        // Finishing/saving can still take time; never promise zero before commit.
        return Int64(max(1, seconds.rounded(.up)))
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

struct IntelligenceProgressDisplay {
    let fraction: Double
    let percentage: Int
    let elapsedSeconds: Int64
    let remainingSeconds: Int64?
    let finished: Bool

    var elapsedText: String { MinutesStyle.duration(seconds: elapsedSeconds) }
    var remainingText: String {
        remainingSeconds.map { "About \(MinutesStyle.duration(seconds: $0))" } ?? "Estimating…"
    }
    var notificationSubtitle: String {
        if finished {
            return "\(percentage)% · \(elapsedText) elapsed · \(percentage == 100 ? "Complete" : "Stopped")"
        }
        let remaining = remainingSeconds.map { "~\(MinutesStyle.duration(seconds: $0)) left" } ?? "Estimating…"
        return "\(percentage)% · \(elapsedText) elapsed · \(remaining)"
    }
}
#endif
