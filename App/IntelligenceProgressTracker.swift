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
    private var completedWorkSamples = 0
    private var estimateDeadline: ContinuousClock.Instant?
    private var lastEstimateUpdate: ContinuousClock.Instant?
    private var recalibratingEstimate = false

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

    var explanation: String? {
        guard stage != .saving else { return "Saving the completed result on this iPhone." }
        return currentWork?.explanation
    }

    var phaseTitle: String { stage == .saving ? detail : currentWork?.title ?? detail }
    var counterText: String? { stage == .saving ? nil : currentWork?.counterText }

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
                    completedWorkSamples += 1
                    updateSummaryEstimate(completedFraction: work.completedFraction, at: now)
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
            elapsedSeconds: elapsed, remainingSeconds: remaining, finished: finishedAt != nil,
            reestimating: currentWork != nil && (recalibratingEstimate
                || estimateDeadline.map { Self.seconds(now.duration(to: $0)) <= 5 } == true))
    }

    /// Calibrate from several complete operations, never a handful of tokens
    /// divided by a tiny weighted progress slice. A deadline provides a steady
    /// countdown between samples. Small corrections cannot make it count up.
    private func updateSummaryEstimate(completedFraction: Double, at now: ContinuousClock.Instant) {
        guard completedWorkSamples >= 3, measuredWorkSeconds >= 15, measuredWorkFraction > 0,
              completedFraction < 0.999 else { return }
        let remaining = (1 - completedFraction) * measuredWorkSeconds / measuredWorkFraction + 3
        guard remaining.isFinite, remaining > 5, remaining < 86_400 else { return }
        if let deadline = estimateDeadline, let updated = lastEstimateUpdate {
            let previousRemaining = Self.seconds(now.duration(to: deadline))
            // A major slowdown or an expired estimate needs new evidence, not
            // a jump from minutes to hours or a countdown stuck at one second.
            if previousRemaining <= 5 || remaining > max(previousRemaining * 1.5, previousRemaining + 60) {
                estimateDeadline = nil; lastEstimateUpdate = nil
                completedWorkSamples = 0
                measuredWorkSeconds = 0; measuredWorkFraction = 0
                recalibratingEstimate = true
                return
            }
            let elapsed = max(0, Self.seconds(updated.duration(to: now)))
            let correction = min(elapsed * 0.25, max(-elapsed * 0.25, (remaining - previousRemaining) * 0.2))
            estimateDeadline = deadline.advanced(by: .seconds(correction))
        } else {
            estimateDeadline = now.advanced(by: .seconds(remaining))
        }
        lastEstimateUpdate = now
        recalibratingEstimate = false
    }

    private func estimate(at now: ContinuousClock.Instant) -> Int64? {
        if currentWork != nil {
            guard finishedAt == nil, stage != .saving, let lastWorkReportAt,
                  Self.seconds(lastWorkReportAt.duration(to: now)) <= 15 else { return nil }
            guard let deadline = estimateDeadline else { return nil }
            let seconds = Self.seconds(now.duration(to: deadline))
            guard seconds > 5 else { return nil }
            return Int64(seconds.rounded(.up))
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
    var reestimating = false

    var elapsedText: String { MinutesStyle.duration(seconds: elapsedSeconds) }
    var remainingText: String {
        remainingSeconds.map { "About \(MinutesStyle.duration(seconds: $0))" }
            ?? (reestimating ? "Re-estimating…" : "Estimating…")
    }
    var notificationSubtitle: String {
        if finished {
            return "\(percentage)% · \(elapsedText) elapsed · \(percentage == 100 ? "Complete" : "Stopped")"
        }
        let remaining = remainingSeconds.map { "~\(MinutesStyle.duration(seconds: $0)) left" }
            ?? (reestimating ? "Re-estimating…" : "Estimating…")
        return "\(percentage)% · \(elapsedText) elapsed · \(remaining)"
    }
}
#endif
