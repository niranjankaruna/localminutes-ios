import Foundation

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
    /// The observed span may be shorter than60s during startup/sparse sampling;
    /// no interpolation or unseen processing is claimed.
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
    case notImplemented, invalidConfiguration, invalidFacts, nonMonotonicTime
    case restrictedPayload, oversizedExport
}

/// Worker/control-path sampling only. This recorder is never called by the
/// audio tap and does not infer a locked device, native measurement or endurance
/// pass from synthetic/desktop samples. All buffers/statistics must be bounded.
public final class EnduranceMetricsRecorder: Sendable {
    private let transcription: TranscriptionMetricsRecorder
    private let capacity: Int
    public init(transcription: TranscriptionMetricsRecorder, clock: any MetricsMonotonicClock,
                capacity: Int = 128) throws {
        self.transcription = transcription; self.capacity = capacity
    }
    // TEST-FIRST interfaces only. No clocks, rolling windows, samples or stats
    // are implemented until actual hosted assertion RED for this new layer.
    public func sample(_ facts: EnduranceSystemFacts) throws { throw EnduranceMetricsError.notImplemented }
    public func beginEpoch() {}
    public func snapshot() -> EnduranceMetricsSnapshot {
        .init(schemaVersion: 1, transcription: transcription.snapshot(), epochOriginNanoseconds: nil,
            rollingWindowNanoseconds: 60_000_000_000, rollingCoverageNanoseconds: 0,
            rollingRealTimeFactor: nil, currentSampledBacklogSeconds: nil,
            recentP95SampledBacklogSeconds: nil, wholeMeetingP95SampledBacklogUpperBoundSeconds: nil,
            backlogHistogram: [], peakSampledBacklogSeconds: nil,
            recentBacklogSampleCount: 0, backlogSampleCapacity: capacity, totalSampleCount: 0,
            currentResidentMemoryBytes: nil, peakResidentMemoryBytes: nil,
            memoryAtMinute30: nil, memoryAtMinute120: nil, memoryGrowth30To120Bytes: nil, samples: [])
    }
}

/// Separate bounded privacy envelope; the existing metrics codec stays intact.
/// Reject unknown/private fields at every level, including the embedded schema.
public enum EnduranceMetricsExportCodec {
    public static func encode(_ snapshot: EnduranceMetricsSnapshot) throws -> Data {
        throw EnduranceMetricsError.notImplemented
    }
    public static func decodeValidated(_ data: Data) throws -> EnduranceMetricsSnapshot {
        throw EnduranceMetricsError.notImplemented
    }
}
