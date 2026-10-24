import Foundation

/// Monotonic uptime nanoseconds only; never Date, Unix time or a wall-clock
/// subtraction inferred from audio sample positions.
public protocol MetricsMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public enum MetricsVisibility: String, Codable, Equatable, Sendable {
    case unknown, foreground, background
}

public enum MetricsErrorCategory: String, Codable, Equatable, Sendable {
    case captureUnavailable, queueOverflow, invalidTimestamp, conversionFailed, writeFailed, inferenceFailed
}

public enum MetricsValidationError: Error, Equatable, Sendable {
    case notImplemented, invalidConfiguration, invalidSampleRange, nonMonotonicTime
    case invalidIdentity, restrictedPayload, oversizedExport
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

/// Future worker/control-path instrumentation only. No audio-tap lock, task,
/// allocation, SQL or JSON serialization belongs behind a capture callback.
/// This is a compiling no-op stub until actual compatible behavioral RED.
public final class TranscriptionMetricsRecorder: Sendable {
    private let identity: MetricsBuildIdentity
    public init(identity: MetricsBuildIdentity, sampleRate: Int = 16_000,
                capacity: Int = 128, clock: any MetricsMonotonicClock) throws {
        self.identity = identity
    }
    public func audioQueued(startSample: Int64, frameCount: Int, queueDepth: Int) throws {}
    public func processed(startSample: Int64, frameCount: Int, workStartedAtNanoseconds: UInt64) throws {}
    public func partialPublished(endSample: Int64) throws {}
    public func finalPublished(endSample: Int64) throws {}
    public func visibilityChanged(_ value: MetricsVisibility) throws {}
    public func recordError(_ value: MetricsErrorCategory) {}
    public func checkpoint() throws {}
    public func snapshot() -> TranscriptionMetricsSnapshot {
        .init(schemaVersion: 1, identity: identity, capturedSampleCount: 0, processedSampleCount: 0,
            processingWallNanoseconds: 0, realTimeFactor: nil, peakQueueDepth: 0,
            partialLatency: .init(sampleCount: 0, p50Nanoseconds: nil, p95Nanoseconds: nil, maxNanoseconds: nil),
            finalLatency: .init(sampleCount: 0, p50Nanoseconds: nil, p95Nanoseconds: nil, maxNanoseconds: nil),
            checkpoints: [], errors: [])
    }
}

/// Strict typed schema only, <=64 KiB UTF-8. Unknown/nested text, audio, path,
/// credential or asserted-lock fields are rejected rather than copied through.
public enum MetricsExportCodec {
    public static func encode(_ snapshot: TranscriptionMetricsSnapshot) throws -> Data {
        throw MetricsValidationError.notImplemented
    }
    public static func decodeValidated(_ data: Data) throws -> TranscriptionMetricsSnapshot {
        throw MetricsValidationError.notImplemented
    }
}
