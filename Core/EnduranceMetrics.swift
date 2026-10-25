import Foundation
import Synchronization

public enum EnduranceThermalState: String, Codable, Equatable, Sendable {
    case unknown, nominal, fair, serious, critical
}
public enum EnduranceBatteryState: String, Codable, Equatable, Sendable {
    case unknown, unplugged, charging, full
}
public enum EnduranceAudioRoute: String, Codable, Equatable, Sendable {
    case unknown, builtInMicrophone, headsetMicrophone, bluetoothMicrophone, usbMicrophone, unavailable
}
public struct EnduranceSystemFacts: Codable, Equatable, Sendable {
    /// Actual resident footprint, not physical RAM or estimated app budget.
    /// Unsupported/failed OS measurement is nil, never a fabricated zero.
    public let residentMemoryBytes: Int64?
    public let thermal: EnduranceThermalState
    public let batteryLevelPercent: Int?
    public let batteryState: EnduranceBatteryState
    /// Category only. No route/device names, UIDs or account identifiers.
    public let route: EnduranceAudioRoute
    /// Background is an observed scene fact, never an asserted Lock Screen.
    public let visibility: MetricsVisibility
    public init(residentMemoryBytes: Int64? = nil, thermal: EnduranceThermalState = .unknown,
                batteryLevelPercent: Int? = nil, batteryState: EnduranceBatteryState = .unknown,
                route: EnduranceAudioRoute = .unknown, visibility: MetricsVisibility = .unknown) {
        self.residentMemoryBytes = residentMemoryBytes; self.thermal = thermal
        self.batteryLevelPercent = batteryLevelPercent; self.batteryState = batteryState
        self.route = route; self.visibility = visibility
    }
}
public struct EnduranceSystemCheckpoint: Codable, Equatable, Sendable {
    public let monotonicNanoseconds: UInt64
    public let elapsedNanoseconds: UInt64?
    public let capturedSampleCount: Int64
    public let processedSampleCount: Int64
    public let processingWallNanoseconds: UInt64
    public let backlogSeconds: Double
    public let facts: EnduranceSystemFacts
}
public struct EnduranceMemoryObservation: Codable, Equatable, Sendable {
    public let monotonicNanoseconds: UInt64
    public let elapsedNanoseconds: UInt64
    public let residentMemoryBytes: Int64
}
public struct EnduranceBacklogBucket: Codable, Equatable, Sendable {
    public let upperBoundSeconds: Double
    public let sampleCount: UInt64
}
public struct EnduranceMetricsSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    /// Existing typed schema/pins are retained, not relabelled or replaced.
    public let transcription: TranscriptionMetricsSnapshot
    public let epochOriginNanoseconds: UInt64?
    public let rollingWindowNanoseconds: UInt64
    /// Actual sample span bracketing the60s target. Startup/sparse history may
    /// be shorter; ordinary timer jitter may add one observed interval. No
    /// interpolation or unseen processing is claimed.
    public let rollingCoverageNanoseconds: UInt64
    public let rollingRealTimeFactor: Double?
    public let currentSampledBacklogSeconds: Double?
    /// Nearest-rank percentile of the last capacity samples, not whole-session p95.
    public let recentP95SampledBacklogSeconds: Double?
    /// Whole-meeting nearest-rank p95, conservatively rounded to a fixed
    /// histogram upper bound: zero, then powers of two beginning at0.125s.
    /// At most64 buckets cover the full valid Int64 sample-count domain.
    public let wholeMeetingP95SampledBacklogUpperBoundSeconds: Double?
    public let backlogHistogram: [EnduranceBacklogBucket]
    public let peakSampledBacklogSeconds: Double?
    public let recentBacklogSampleCount: Int
    public let backlogSampleCapacity: Int
    public let totalSampleCount: UInt64
    public let currentResidentMemoryBytes: Int64?
    public let peakResidentMemoryBytes: Int64?
    /// First valid sample in [target,target+60s]. Missed target stays unknown;
    /// one late sample must not fabricate both30min and120min observations.
    public let memoryAtMinute30: EnduranceMemoryObservation?
    public let memoryAtMinute120: EnduranceMemoryObservation?
    public let memoryGrowth30To120Bytes: Int64?
    public let samples: [EnduranceSystemCheckpoint]
}
public enum EnduranceMetricsError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidFacts, nonMonotonicTime
    case restrictedPayload, oversizedExport
}

/// Worker/control-path sampling only. This recorder is never called by the
/// audio tap and does not infer a locked device, native measurement or endurance
/// pass from synthetic/desktop samples. All buffers/statistics must be bounded.
public final class EnduranceMetricsRecorder: Sendable {
    private struct State: Sendable {
        var lastTime: UInt64
        var origin: UInt64?
        var samples: [EnduranceSystemCheckpoint] = []
        var rolling: [EnduranceSystemCheckpoint] = []
        var histogram = [UInt64](repeating: 0, count: 64)
        var total: UInt64 = 0
        var peakBacklog: Double?
        var peakMemory: Int64?
        var minute30: EnduranceMemoryObservation?
        var minute120: EnduranceMemoryObservation?
    }
    private let transcription: TranscriptionMetricsRecorder
    private let capacity: Int
    private let clock: any MetricsMonotonicClock
    private let state: Mutex<State>
    public init(transcription: TranscriptionMetricsRecorder, clock: any MetricsMonotonicClock,
                capacity: Int = 128) throws {
        guard (1...128).contains(capacity) else { throw EnduranceMetricsError.invalidConfiguration }
        self.transcription = transcription; self.capacity = capacity
        self.clock = clock
        state = Mutex(State(lastTime: clock.nowNanoseconds()))
    }
    public func sample(_ facts: EnduranceSystemFacts) throws {
        try EnduranceMath.validateFacts(facts)
        try state.withLock { value in
            let now = clock.nowNanoseconds()
            guard now >= value.lastTime else { throw EnduranceMetricsError.nonMonotonicTime }
            let source = transcription.snapshot()
            let origin = transcription.firstAudioQueuedAtNanoseconds
            guard origin.map({ $0 <= now }) ?? true,
                  value.origin == nil || value.origin == origin,
                  source.capturedSampleCount >= 0, source.processedSampleCount >= 0,
                  source.processedSampleCount <= source.capturedSampleCount else {
                throw EnduranceMetricsError.invalidFacts
            }
            if let last = value.samples.last {
                guard source.capturedSampleCount >= last.capturedSampleCount,
                      source.processedSampleCount >= last.processedSampleCount,
                      source.processingWallNanoseconds >= last.processingWallNanoseconds else {
                    throw EnduranceMetricsError.invalidFacts
                }
            }
            let (nextTotal, overflow) = value.total.addingReportingOverflow(1)
            guard !overflow else { throw EnduranceMetricsError.invalidFacts }
            let elapsed = origin.map { now - $0 }
            let backlog = Double(source.capturedSampleCount - source.processedSampleCount) / 16_000
            let sample = EnduranceSystemCheckpoint(monotonicNanoseconds: now, elapsedNanoseconds: elapsed,
                capturedSampleCount: source.capturedSampleCount, processedSampleCount: source.processedSampleCount,
                processingWallNanoseconds: source.processingWallNanoseconds, backlogSeconds: backlog, facts: facts)
            // All validation precedes mutation, including origin establishment.
            value.origin = origin; value.lastTime = now; value.total = nextTotal
            value.histogram[EnduranceMath.bucket(backlog)] += 1
            value.peakBacklog = max(value.peakBacklog ?? 0, backlog)
            if let memory = facts.residentMemoryBytes {
                value.peakMemory = max(value.peakMemory ?? memory, memory)
                if let elapsed {
                    let observation = EnduranceMemoryObservation(monotonicNanoseconds: now,
                        elapsedNanoseconds: elapsed, residentMemoryBytes: memory)
                    if value.minute30 == nil, EnduranceMath.target30.contains(elapsed) { value.minute30 = observation }
                    if value.minute120 == nil, EnduranceMath.target120.contains(elapsed) { value.minute120 = observation }
                }
            }
            if value.samples.count == capacity { value.samples.removeFirst() }
            value.samples.append(sample)
            if value.rolling.count == 128 { value.rolling.removeFirst() }
            value.rolling.append(sample)
            let cutoff = now >= EnduranceMath.window ? now - EnduranceMath.window : 0
            // Retain the nearest observed baseline bracketing the target. The
            // reported coverage is the actual span, never interpolated counters.
            while value.rolling.count > 1, value.rolling[1].monotonicNanoseconds <= cutoff {
                value.rolling.removeFirst()
            }
            if value.rolling.count > 1,
               value.rolling[1].monotonicNanoseconds - value.rolling[0].monotonicNanoseconds > EnduranceMath.window {
                value.rolling.removeFirst()
            }
        }
    }
    public func beginEpoch() {
        state.withLock { value in value = State(lastTime: value.lastTime) }
    }
    public func snapshot() -> EnduranceMetricsSnapshot {
        state.withLock { value in
            let source = transcription.snapshot()
            let histogram = value.histogram.enumerated().compactMap { index, count in
                count == 0 ? nil : EnduranceBacklogBucket(upperBoundSeconds: EnduranceMath.bounds[index], sampleCount: count)
            }
            let first = value.rolling.first, last = value.rolling.last
            let coverage = first.flatMap { first in last.map { $0.monotonicNanoseconds - first.monotonicNanoseconds } } ?? 0
            var factor: Double?
            if coverage >= EnduranceMath.window, let first, let last,
               last.processedSampleCount > first.processedSampleCount,
               last.processingWallNanoseconds >= first.processingWallNanoseconds {
                factor = Double(last.processingWallNanoseconds - first.processingWallNanoseconds)
                    / (Double(last.processedSampleCount - first.processedSampleCount) / 16_000 * 1_000_000_000)
            }
            let growth = value.minute30.flatMap { first in value.minute120.map { $0.residentMemoryBytes - first.residentMemoryBytes } }
            return .init(schemaVersion: 1, transcription: source, epochOriginNanoseconds: value.origin,
                rollingWindowNanoseconds: EnduranceMath.window, rollingCoverageNanoseconds: coverage,
                rollingRealTimeFactor: factor, currentSampledBacklogSeconds: value.samples.last?.backlogSeconds,
                recentP95SampledBacklogSeconds: EnduranceMath.percentile(value.samples.map(\.backlogSeconds)),
                wholeMeetingP95SampledBacklogUpperBoundSeconds: EnduranceMath.histogramPercentile(histogram, total: value.total),
                backlogHistogram: histogram, peakSampledBacklogSeconds: value.peakBacklog,
                recentBacklogSampleCount: value.samples.count, backlogSampleCapacity: capacity, totalSampleCount: value.total,
                currentResidentMemoryBytes: value.samples.last?.facts.residentMemoryBytes, peakResidentMemoryBytes: value.peakMemory,
                memoryAtMinute30: value.minute30, memoryAtMinute120: value.minute120,
                memoryGrowth30To120Bytes: growth, samples: value.samples)
        }
    }
}

/// Separate bounded privacy envelope; the existing metrics codec stays intact.
/// Reject unknown/private fields at every level, including the embedded schema.
public enum EnduranceMetricsExportCodec {
    public static func encode(_ snapshot: EnduranceMetricsSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try encoder.encode(snapshot) } catch { throw EnduranceMetricsError.restrictedPayload }
        guard data.count <= maximumBytes else { throw EnduranceMetricsError.oversizedExport }
        return data
    }
    public static func decodeValidated(_ data: Data) throws -> EnduranceMetricsSnapshot {
        guard data.count <= maximumBytes else { throw EnduranceMetricsError.oversizedExport }
        do {
            let object = try keys(JSONSerialization.jsonObject(with: data), allowed: [
                "schemaVersion", "transcription", "epochOriginNanoseconds", "rollingWindowNanoseconds",
                "rollingCoverageNanoseconds", "rollingRealTimeFactor", "currentSampledBacklogSeconds",
                "recentP95SampledBacklogSeconds", "wholeMeetingP95SampledBacklogUpperBoundSeconds", "backlogHistogram",
                "peakSampledBacklogSeconds", "recentBacklogSampleCount", "backlogSampleCapacity", "totalSampleCount",
                "currentResidentMemoryBytes", "peakResidentMemoryBytes", "memoryAtMinute30", "memoryAtMinute120",
                "memoryGrowth30To120Bytes", "samples"
            ])
            let embedded = try JSONSerialization.data(withJSONObject: object["transcription"] ?? NSNull())
            _ = try MetricsExportCodec.decodeValidated(embedded)
            guard let samples = object["samples"] as? [Any], samples.count <= 128,
                  let histogram = object["backlogHistogram"] as? [Any], histogram.count <= 64 else {
                throw EnduranceMetricsError.restrictedPayload
            }
            for sample in samples {
                let sample = try keys(sample, allowed: ["monotonicNanoseconds", "elapsedNanoseconds", "capturedSampleCount",
                    "processedSampleCount", "processingWallNanoseconds", "backlogSeconds", "facts"])
                _ = try keys(sample["facts"] ?? NSNull(), allowed: ["residentMemoryBytes", "thermal", "batteryLevelPercent",
                    "batteryState", "route", "visibility"])
            }
            for item in histogram { _ = try keys(item, allowed: ["upperBoundSeconds", "sampleCount"]) }
            for name in ["memoryAtMinute30", "memoryAtMinute120"] {
                if let value = object[name], !(value is NSNull) {
                    _ = try keys(value, allowed: ["monotonicNanoseconds", "elapsedNanoseconds", "residentMemoryBytes"])
                }
            }
            let result = try JSONDecoder().decode(EnduranceMetricsSnapshot.self, from: data)
            try validate(result)
            return result
        } catch let error as EnduranceMetricsError { throw error }
        catch { throw EnduranceMetricsError.restrictedPayload }
    }

    private static let maximumBytes = 131_072
    private static func keys(_ raw: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any], Set(value.keys).isSubset(of: allowed) else {
            throw EnduranceMetricsError.restrictedPayload
        }
        return value
    }
    private static func validate(_ value: EnduranceMetricsSnapshot) throws {
        do { _ = try MetricsExportCodec.encode(value.transcription) }
        catch { throw EnduranceMetricsError.restrictedPayload }
        guard value.schemaVersion == 1, value.rollingWindowNanoseconds == EnduranceMath.window,
              value.rollingCoverageNanoseconds <= 2 * EnduranceMath.window,
              (1...128).contains(value.backlogSampleCapacity), value.samples.count <= value.backlogSampleCapacity,
              value.recentBacklogSampleCount == value.samples.count, value.totalSampleCount >= UInt64(value.samples.count),
              value.backlogHistogram.count <= 64,
              EnduranceMath.same(value.currentSampledBacklogSeconds, value.samples.last?.backlogSeconds),
              EnduranceMath.same(value.recentP95SampledBacklogSeconds, EnduranceMath.percentile(value.samples.map(\.backlogSeconds))),
              value.currentResidentMemoryBytes == value.samples.last?.facts.residentMemoryBytes else {
            throw EnduranceMetricsError.restrictedPayload
        }
        var previous: EnduranceSystemCheckpoint?
        for sample in value.samples {
            do { try EnduranceMath.validateFacts(sample.facts) } catch { throw EnduranceMetricsError.restrictedPayload }
            guard sample.capturedSampleCount >= 0, sample.processedSampleCount >= 0,
                  sample.processedSampleCount <= sample.capturedSampleCount,
                  sample.backlogSeconds.isFinite, sample.backlogSeconds >= 0,
                  EnduranceMath.same(sample.backlogSeconds, Double(sample.capturedSampleCount - sample.processedSampleCount) / 16_000),
                  sample.capturedSampleCount <= value.transcription.capturedSampleCount,
                  sample.processedSampleCount <= value.transcription.processedSampleCount,
                  sample.processingWallNanoseconds <= value.transcription.processingWallNanoseconds else {
                throw EnduranceMetricsError.restrictedPayload
            }
            if let elapsed = sample.elapsedNanoseconds {
                guard let origin = value.epochOriginNanoseconds, sample.monotonicNanoseconds >= origin,
                      elapsed == sample.monotonicNanoseconds - origin else { throw EnduranceMetricsError.restrictedPayload }
            }
            if let previous {
                guard sample.monotonicNanoseconds >= previous.monotonicNanoseconds,
                      sample.capturedSampleCount >= previous.capturedSampleCount,
                      sample.processedSampleCount >= previous.processedSampleCount,
                      sample.processingWallNanoseconds >= previous.processingWallNanoseconds else {
                    throw EnduranceMetricsError.restrictedPayload
                }
            }
            previous = sample
        }
        var total: UInt64 = 0
        var previousBound: Double = -1
        for bucket in value.backlogHistogram {
            let (sum, overflow) = total.addingReportingOverflow(bucket.sampleCount)
            guard !overflow, bucket.sampleCount > 0, EnduranceMath.bounds.contains(bucket.upperBoundSeconds),
                  bucket.upperBoundSeconds > previousBound else { throw EnduranceMetricsError.restrictedPayload }
            total = sum; previousBound = bucket.upperBoundSeconds
        }
        guard total == value.totalSampleCount,
              EnduranceMath.same(value.wholeMeetingP95SampledBacklogUpperBoundSeconds,
                  EnduranceMath.histogramPercentile(value.backlogHistogram, total: total)) else {
            throw EnduranceMetricsError.restrictedPayload
        }
        for number in [value.rollingRealTimeFactor, value.peakSampledBacklogSeconds] {
            if let number, !number.isFinite || number < 0 { throw EnduranceMetricsError.restrictedPayload }
        }
        if value.rollingRealTimeFactor != nil, value.rollingCoverageNanoseconds < EnduranceMath.window {
            throw EnduranceMetricsError.restrictedPayload
        }
        if let peak = value.peakSampledBacklogSeconds {
            guard value.totalSampleCount > 0, peak >= (value.samples.map(\.backlogSeconds).max() ?? 0) else {
                throw EnduranceMetricsError.restrictedPayload
            }
        } else if value.totalSampleCount != 0 { throw EnduranceMetricsError.restrictedPayload }
        if let memory = value.peakResidentMemoryBytes {
            guard memory > 0, memory >= (value.samples.compactMap(\.facts.residentMemoryBytes).max() ?? 0) else {
                throw EnduranceMetricsError.restrictedPayload
            }
        } else if value.samples.contains(where: { $0.facts.residentMemoryBytes != nil }) {
            throw EnduranceMetricsError.restrictedPayload
        }
        for (observation, target) in [(value.memoryAtMinute30, EnduranceMath.target30),
                                      (value.memoryAtMinute120, EnduranceMath.target120)] {
            if let observation {
                guard let origin = value.epochOriginNanoseconds, observation.monotonicNanoseconds >= origin,
                      observation.elapsedNanoseconds == observation.monotonicNanoseconds - origin,
                      target.contains(observation.elapsedNanoseconds), observation.residentMemoryBytes > 0,
                      observation.residentMemoryBytes <= (value.peakResidentMemoryBytes ?? 0) else {
                    throw EnduranceMetricsError.restrictedPayload
                }
            }
        }
        let growth = value.memoryAtMinute30.flatMap { first in value.memoryAtMinute120.map { $0.residentMemoryBytes - first.residentMemoryBytes } }
        guard growth == value.memoryGrowth30To120Bytes else { throw EnduranceMetricsError.restrictedPayload }
    }
}

private enum EnduranceMath {
    static let window: UInt64 = 60_000_000_000
    static let target30: ClosedRange<UInt64> = 1_800_000_000_000...1_860_000_000_000
    static let target120: ClosedRange<UInt64> = 7_200_000_000_000...7_260_000_000_000
    static let bounds = [0.0] + (0..<63).map { pow(2.0, Double($0 - 3)) }
    static func validateFacts(_ facts: EnduranceSystemFacts) throws {
        guard facts.residentMemoryBytes.map({ $0 > 0 }) ?? true,
              facts.batteryLevelPercent.map({ (0...100).contains($0) }) ?? true else {
            throw EnduranceMetricsError.invalidFacts
        }
    }
    static func bucket(_ backlog: Double) -> Int {
        bounds.firstIndex(where: { $0 >= backlog }) ?? bounds.count - 1
    }
    static func percentile(_ samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.sorted()[(samples.count * 95 + 99) / 100 - 1]
    }
    static func histogramPercentile(_ buckets: [EnduranceBacklogBucket], total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        let rank = (total / 100) * 95 + ((total % 100) * 95 + 99) / 100
        var sum: UInt64 = 0
        for bucket in buckets {
            let (next, overflow) = sum.addingReportingOverflow(bucket.sampleCount)
            guard !overflow else { return nil }
            sum = next
            if sum >= rank { return bucket.upperBoundSeconds }
        }
        return nil
    }
    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (.some(let a), .some(let b)): a.isFinite && b.isFinite && abs(a - b) <= max(1, abs(b)) * 1e-9
        default: false
        }
    }
}
