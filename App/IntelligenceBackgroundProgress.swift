#if os(iOS)
import Foundation

/// Fixed stage weights keep the system's fraction monotonic when the section
/// count becomes known. Native counters advance inside each unfinished section;
/// only a validated map advances the completed-section count.
struct IntelligenceBackgroundProgress {
    let totalUnitCount: Int64 = 1_000_000
    private(set) var completedUnitCount: Int64 = 0
    private(set) var detail = IntelligenceProgress.preparing.message
    private var loading = false
    private var generating = false
    private var responding = false
    private var saving = false
    private var completedSections = 0
    private var totalSections = 1
    private var recoveryBase: Double = 0
    private var combining = false
    private var combinedSteps = 0
    private var totalCombineSteps = 1
    private var planningPass = 0
    private var plannedSources = 0

    @discardableResult
    mutating func report(_ value: IntelligenceProgress) -> Bool {
        guard !saving else { return false }
        let units: Int64
        switch value {
        case .preparing:
            guard !loading, !generating else { return false }
            units = 0
        case .loadingModel(let completed, let total):
            guard !generating, total > 0, completed >= 0, completed <= total else { return false }
            loading = true
            units = Int64(Double(completed) / Double(total) * 50_000)
        case .planningSummary(let completed, let total, let pass):
            guard !generating, total > 0, (1...2).contains(pass), pass >= planningPass,
                  completed >= 0, completed <= total,
                  pass > planningPass || completed >= plannedSources else { return false }
            loading = true; planningPass = pass; plannedSources = completed
            units = 50_000 + Int64(pass - 1) * 25_000 + Int64(Double(completed) / Double(total) * 25_000)
        case .summaryChunks(let completed, let total):
            guard total > 0, completed >= 0, completed <= total,
                  !generating || (total == totalSections && completed > completedSections) else { return false }
            generating = true; responding = false
            recoveryBase = 0
            completedSections = completed; totalSections = total
            units = sectionUnits(fraction: 0)
        case .answering:
            guard !generating else { return false }
            generating = true
            units = 100_000
        case .generating(let progress):
            guard generating, (combining ? combinedSteps < totalCombineSteps : completedSections < totalSections) else { return false }
            let fraction: Double
            switch progress {
            case .promptTokens(let completed, let total):
                guard !responding, total > 0, completed >= 0, completed <= total else { return false }
                fraction = Double(completed) / Double(total) * 0.4
            case .responseTokens(let completed, let limit):
                guard limit > 0, completed >= 0, completed <= limit else { return false }
                responding = true
                // Reserve validation/checkpoint work even at the output limit.
                fraction = 0.4 + Double(completed) / Double(limit) * 0.59
            }
            units = combining ? combinationUnits(fraction: fraction)
                : sectionUnits(fraction: recoveryBase + fraction * (1 - recoveryBase))
        case .generationStarted:
            guard generating else { return false }
            if responding, !combining {
                let completed = Double(completedUnitCount - 100_000) / 800_000 * Double(totalSections)
                recoveryBase = min(0.999, max(recoveryBase, completed - Double(completedSections)))
            }
            responding = false
            units = completedUnitCount
        case .consolidatingSummary(let completed, let total):
            guard generating, completedSections == totalSections, total > 0,
                  completed >= 0, completed <= total,
                  !combining || (total == totalCombineSteps && completed >= combinedSteps) else { return false }
            combining = true; responding = false
            combinedSteps = completed; totalCombineSteps = total
            units = combinationUnits(fraction: 0)
        case .saving:
            saving = true
            units = 950_000
        }
        guard units >= completedUnitCount else { return false }
        completedUnitCount = units
        detail = value.message
        return true
    }

    private func sectionUnits(fraction: Double) -> Int64 {
        100_000 + Int64((Double(completedSections) + fraction) / Double(totalSections) * 800_000)
    }

    private func combinationUnits(fraction: Double) -> Int64 {
        900_000 + Int64((Double(combinedSteps) + fraction) / Double(totalCombineSteps) * 49_999)
    }
}
#endif
