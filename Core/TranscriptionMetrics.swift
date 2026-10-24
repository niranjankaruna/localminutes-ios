import Foundation
import Synchronization

/// Monotonic uptime nanoseconds only; never Date, Unix time or a wall-clock
/// subtraction inferred from audio sample positions.
public protocol MetricsMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public enum MetricsVisibility: String, Codable, Equatable, Sendable {
    case unknown, foreground, background
}

public enum MetricsErrorCategory: String, Codable, Equatable, Hashable, Sendable {
    case captureUnavailable, queueOverflow, invalidTimestamp, conversionFailed, writeFailed, inferenceFailed
}

public enum MetricsValidationError: Error, Equatable, Sendable {
    case notImplemented, invalidConfiguration, invalidSampleRange, nonMonotonicTime
    case invalidIdentity, restrictedPayload, oversizedExport, pendingOverflow
}

public struct MetricsBuildIdentity: Codable, Equatable, Sendable {
    public let sourceCommit: String
    public let modelRevision: String
    public let runtimeVersion: String
    public let buildNumber: Int
    public init(sourceCommit: String, modelRevision: String, runtimeVersion: String, buildNumber: Int) {
        self.sourceCommit = sourceCommit; self.modelRevision = modelRevision
        self.runtimeVersion = runtimeVersion; self.buildNumber = buildNumber
    }
}

public struct MetricsLatencySummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let p50Nanoseconds: UInt64?
    public let p95Nanoseconds: UInt64?
    public let maxNanoseconds: UInt64?
}

public struct MetricsCheckpoint: Codable, Equatable, Sendable {
    public let monotonicNanoseconds: UInt64
    public let visibility: MetricsVisibility
    public let capturedSampleCount: Int64
    public let processedSampleCount: Int64
    public let queueDepth: Int
}

public struct MetricsErrorCount: Codable, Equatable, Sendable {
    public let category: MetricsErrorCategory
    public let count: UInt64
}

public struct TranscriptionMetricsSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let identity: MetricsBuildIdentity
    public let capturedSampleCount: Int64
    public let processedSampleCount: Int64
    public let processingWallNanoseconds: UInt64
    public let realTimeFactor: Double?
    public let peakQueueDepth: Int
    public let partialLatency: MetricsLatencySummary
    public let finalLatency: MetricsLatencySummary
    public let checkpoints: [MetricsCheckpoint]
    public let errors: [MetricsErrorCount]
}

/// Worker/control-path instrumentation only. No audio-tap lock, task,
/// allocation, SQL or JSON serialization belongs behind a capture callback.
public final class TranscriptionMetricsRecorder: Sendable {
    private struct Input: Sendable {
        let start: Int64
        let end: Int64
        let queuedAt: UInt64
    }
    private struct State: Sendable {
        var captured: Int64 = 0
        var processed: Int64 = 0
        var work: UInt64 = 0
        var peakQueue = 0
        var queueDepth = 0
        var lastTime: UInt64?
        var visibility = MetricsVisibility.unknown
        var pending: [Input] = []
        var completed: [Input] = []
        var partial: [UInt64] = []
        var final: [UInt64] = []
        var checkpoints: [MetricsCheckpoint] = []
        var errors: [MetricsErrorCategory: UInt64] = [:]

        init(capacity: Int) {
            pending.reserveCapacity(129)
            completed.reserveCapacity(capacity)
            partial.reserveCapacity(capacity)
            final.reserveCapacity(capacity)
            checkpoints.reserveCapacity(capacity)
        }
    }
    private let identity: MetricsBuildIdentity
    private let capacity: Int
    private let clock: any MetricsMonotonicClock
    private let state: Mutex<State>

    public init(identity: MetricsBuildIdentity, sampleRate: Int = 16_000,
                capacity: Int = 128, clock: any MetricsMonotonicClock) throws {
        guard sampleRate == 16_000, (1...128).contains(capacity) else {
            throw MetricsValidationError.invalidConfiguration
        }
        self.identity = identity
        self.capacity = capacity
        self.clock = clock
        state = Mutex(State(capacity: capacity))
    }

    public func nowNanoseconds() -> UInt64 { clock.nowNanoseconds() }

    public func audioQueued(startSample: Int64, frameCount: Int, queueDepth: Int) throws {
        try state.withLock { value in
            let end = try checkedEnd(start: startSample, count: frameCount)
            guard startSample == value.captured, (0...128).contains(queueDepth) else {
                throw MetricsValidationError.invalidSampleRange
            }
            // At most128 queued chunks plus one native operation in flight.
            guard value.pending.count < 129 else { throw MetricsValidationError.pendingOverflow }
            let now = try checkedTime(value)
            value.pending.append(Input(start: startSample, end: end, queuedAt: now))
            value.captured = end
            value.queueDepth = queueDepth
            value.peakQueue = max(value.peakQueue, queueDepth)
            value.lastTime = now
        }
    }

    public func processed(startSample: Int64, frameCount: Int, workStartedAtNanoseconds: UInt64) throws {
        try state.withLock { value in
            let end = try checkedEnd(start: startSample, count: frameCount)
            guard startSample == value.processed, let input = value.pending.first,
                  input.start == startSample, input.end == end, end <= value.captured else {
                throw MetricsValidationError.invalidSampleRange
            }
            let now = try checkedTime(value)
            guard workStartedAtNanoseconds >= input.queuedAt, workStartedAtNanoseconds <= now else {
                throw MetricsValidationError.nonMonotonicTime
            }
            let (work, overflow) = value.work.addingReportingOverflow(now - workStartedAtNanoseconds)
            guard !overflow else { throw MetricsValidationError.nonMonotonicTime }
            value.pending.removeFirst()
            append(input, to: &value.completed)
            value.processed = end
            value.work = work
            value.queueDepth = value.pending.count
            value.lastTime = now
        }
    }

    /// Final decoder lookahead consumes wall time but never manufactures source
    /// audio samples. Include its cost without advancing the processed cursor.
    public func finalizationCompleted(workStartedAtNanoseconds: UInt64) throws {
        try state.withLock { value in
            let now = try checkedTime(value)
            guard workStartedAtNanoseconds <= now else { throw MetricsValidationError.nonMonotonicTime }
            let (work, overflow) = value.work.addingReportingOverflow(now - workStartedAtNanoseconds)
            guard !overflow else { throw MetricsValidationError.nonMonotonicTime }
            value.work = work
            value.lastTime = now
        }
    }

    public func partialPublished(endSample: Int64) throws { try published(end: endSample, isFinal: false) }
    public func finalPublished(endSample: Int64) throws { try published(end: endSample, isFinal: true) }

    private func published(end: Int64, isFinal: Bool) throws {
        try state.withLock { value in
            guard end > 0, end <= value.processed,
                  let input = value.completed.last(where: { end > $0.start && end <= $0.end }) else {
                throw MetricsValidationError.invalidSampleRange
            }
            let now = try checkedTime(value)
            guard now >= input.queuedAt else { throw MetricsValidationError.nonMonotonicTime }
            if isFinal { append(now - input.queuedAt, to: &value.final) }
            else { append(now - input.queuedAt, to: &value.partial) }
            value.lastTime = now
        }
    }

    public func visibilityChanged(_ visibility: MetricsVisibility) throws {
        try state.withLock { value in
            let now = try checkedTime(value)
            value.visibility = visibility
            value.lastTime = now
        }
    }

    public func recordError(_ category: MetricsErrorCategory) {
        state.withLock { value in
            let count = value.errors[category, default: 0]
            value.errors[category] = count == .max ? .max : count + 1
        }
    }

    public func checkpoint() throws {
        try state.withLock { value in
            let now = try checkedTime(value)
            append(MetricsCheckpoint(monotonicNanoseconds: now, visibility: value.visibility,
                capturedSampleCount: value.captured, processedSampleCount: value.processed,
                queueDepth: value.queueDepth), to: &value.checkpoints)
            value.lastTime = now
        }
    }

    public func snapshot() -> TranscriptionMetricsSnapshot {
        state.withLock { value in
            .init(schemaVersion: 1, identity: identity, capturedSampleCount: value.captured,
                processedSampleCount: value.processed, processingWallNanoseconds: value.work,
                realTimeFactor: value.processed == 0 ? nil :
                    Double(value.work) / (Double(value.processed) / 16_000 * 1_000_000_000),
                peakQueueDepth: value.peakQueue, partialLatency: summary(value.partial),
                finalLatency: summary(value.final), checkpoints: value.checkpoints,
                errors: value.errors.keys.sorted(by: { $0.rawValue < $1.rawValue }).map {
                    MetricsErrorCount(category: $0, count: value.errors[$0]!)
                })
        }
    }

    private func checkedTime(_ value: State) throws -> UInt64 {
        let now = clock.nowNanoseconds()
        guard value.lastTime.map({ now >= $0 }) ?? true else { throw MetricsValidationError.nonMonotonicTime }
        return now
    }

    private func checkedEnd(start: Int64, count: Int) throws -> Int64 {
        guard start >= 0, count > 0, count <= 65_536 else { throw MetricsValidationError.invalidSampleRange }
        let (end, overflow) = start.addingReportingOverflow(Int64(count))
        guard !overflow else { throw MetricsValidationError.invalidSampleRange }
        return end
    }

    private func append<Value>(_ item: Value, to values: inout [Value]) {
        if values.count == capacity { values.removeFirst() }
        values.append(item)
    }

    private func summary(_ samples: [UInt64]) -> MetricsLatencySummary {
        let sorted = samples.sorted()
        guard let max = sorted.last else {
            return .init(sampleCount: 0, p50Nanoseconds: nil, p95Nanoseconds: nil, maxNanoseconds: nil)
        }
        let middle = sorted[(sorted.count + 1) / 2 - 1]
        let upper = sorted[(sorted.count * 95 + 99) / 100 - 1]
        return .init(sampleCount: sorted.count, p50Nanoseconds: middle, p95Nanoseconds: upper, maxNanoseconds: max)
    }
}

/// Strict typed schema only, <=64 KiB UTF-8. Unknown/nested text, audio, path,
/// credential or asserted-lock fields are rejected rather than copied through.
public enum MetricsExportCodec {
    private static let maximumBytes = 65_536

    public static func encode(_ snapshot: TranscriptionMetricsSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do { data = try encoder.encode(snapshot) }
        catch { throw MetricsValidationError.restrictedPayload }
        guard data.count <= maximumBytes else { throw MetricsValidationError.oversizedExport }
        return data
    }

    public static func decodeValidated(_ data: Data) throws -> TranscriptionMetricsSnapshot {
        guard data.count <= maximumBytes else { throw MetricsValidationError.oversizedExport }
        do {
            let raw = try JSONSerialization.jsonObject(with: data)
            let object = try keys(raw, allowed: ["schemaVersion", "identity", "capturedSampleCount",
                "processedSampleCount", "processingWallNanoseconds", "realTimeFactor", "peakQueueDepth",
                "partialLatency", "finalLatency", "checkpoints", "errors"])
            _ = try keys(object["identity"] ?? NSNull(), allowed: ["sourceCommit", "modelRevision", "runtimeVersion", "buildNumber"])
            for name in ["partialLatency", "finalLatency"] {
                _ = try keys(object[name] ?? NSNull(), allowed: ["sampleCount", "p50Nanoseconds", "p95Nanoseconds", "maxNanoseconds"])
            }
            guard let checkpoints = object["checkpoints"] as? [Any], checkpoints.count <= 128,
                  let errors = object["errors"] as? [Any], errors.count <= 6 else {
                throw MetricsValidationError.restrictedPayload
            }
            for item in checkpoints {
                _ = try keys(item, allowed: ["monotonicNanoseconds", "visibility", "capturedSampleCount", "processedSampleCount", "queueDepth"])
            }
            for item in errors { _ = try keys(item, allowed: ["category", "count"]) }
            let result = try JSONDecoder().decode(TranscriptionMetricsSnapshot.self, from: data)
            try validate(result)
            return result
        } catch let error as MetricsValidationError { throw error }
        catch { throw MetricsValidationError.restrictedPayload }
    }

    private static func keys(_ object: Any, allowed: Set<String>) throws -> [String: Any] {
        guard let object = object as? [String: Any], Set(object.keys).isSubset(of: allowed) else {
            throw MetricsValidationError.restrictedPayload
        }
        return object
    }

    private static func validate(_ value: TranscriptionMetricsSnapshot) throws {
        let identity = value.identity
        let parts = identity.runtimeVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard hexRevision(identity.sourceCommit), hexRevision(identity.modelRevision),
              identity.buildNumber > 0, identity.buildNumber <= Int(UInt32.max),
              identity.runtimeVersion.utf8.count <= 32, (1...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }) else {
            throw MetricsValidationError.invalidIdentity
        }
        guard value.schemaVersion == 1, value.capturedSampleCount >= 0,
              value.processedSampleCount >= 0, value.processedSampleCount <= value.capturedSampleCount,
              (0...128).contains(value.peakQueueDepth), value.checkpoints.count <= 128,
              value.errors.count <= 6 else { throw MetricsValidationError.restrictedPayload }
        if value.processedSampleCount == 0 {
            guard value.realTimeFactor == nil else { throw MetricsValidationError.restrictedPayload }
        } else {
            let expected = Double(value.processingWallNanoseconds) /
                (Double(value.processedSampleCount) / 16_000 * 1_000_000_000)
            guard let factor = value.realTimeFactor, factor.isFinite, factor >= 0,
                  abs(factor - expected) <= max(1, expected) * 1e-9 else {
                throw MetricsValidationError.restrictedPayload
            }
        }
        try validate(value.partialLatency)
        try validate(value.finalLatency)
        var previousTime: UInt64 = 0
        var captured: Int64 = 0
        var processed: Int64 = 0
        for point in value.checkpoints {
            guard point.monotonicNanoseconds >= previousTime,
                  point.capturedSampleCount >= captured, point.capturedSampleCount <= value.capturedSampleCount,
                  point.processedSampleCount >= processed, point.processedSampleCount <= value.processedSampleCount,
                  point.processedSampleCount <= point.capturedSampleCount,
                  (0...128).contains(point.queueDepth) else { throw MetricsValidationError.restrictedPayload }
            previousTime = point.monotonicNanoseconds
            captured = point.capturedSampleCount
            processed = point.processedSampleCount
        }
        guard Set(value.errors.map(\.category)).count == value.errors.count,
              value.errors.allSatisfy({ $0.count > 0 }) else { throw MetricsValidationError.restrictedPayload }
    }

    private static func validate(_ value: MetricsLatencySummary) throws {
        guard (0...128).contains(value.sampleCount) else { throw MetricsValidationError.restrictedPayload }
        if value.sampleCount == 0 {
            guard value.p50Nanoseconds == nil, value.p95Nanoseconds == nil, value.maxNanoseconds == nil else {
                throw MetricsValidationError.restrictedPayload
            }
        } else {
            guard let middle = value.p50Nanoseconds, let upper = value.p95Nanoseconds,
                  let maximum = value.maxNanoseconds, middle <= upper, upper <= maximum else {
                throw MetricsValidationError.restrictedPayload
            }
        }
    }

    private static func hexRevision(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
