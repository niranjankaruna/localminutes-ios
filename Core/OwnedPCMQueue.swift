/// One fixed-format capture epoch. Validation belongs to queue initialization,
/// before any callback starts or sample/metadata storage is allocated.
public struct PCMQueueConfiguration: Sendable, Equatable {
    public let capacity: Int
    public let maxFramesPerChunk: Int
    public let channelCount: Int
    public let sampleRate: Double

    public init(capacity: Int, maxFramesPerChunk: Int, channelCount: Int, sampleRate: Double) {
        self.capacity = capacity
        self.maxFramesPerChunk = maxFramesPerChunk
        self.channelCount = channelCount
        self.sampleRate = sampleRate
    }
}

public enum PCMQueueConfigurationError: Error, Sendable, Equatable {
    case invalidCapacity
    case invalidFrameLimit
    case invalidChannelCount
    case invalidSampleRate
    case storageLimitExceeded
}

/// An exact contiguous interval of valid frames lost to queue capacity.
/// Full enqueue results describe that attempt; a chunk or finish result carries
/// the combined interval since the preceding accepted chunk.
public struct PCMFrameLoss: Sendable, Equatable {
    public let startSampleTime: Int64
    public let endSampleTimeExclusive: Int64
    public let frameCount: UInt64
    public let bufferCount: UInt64

    public init(
        startSampleTime: Int64,
        endSampleTimeExclusive: Int64,
        frameCount: UInt64,
        bufferCount: UInt64
    ) {
        self.startSampleTime = startSampleTime
        self.endSampleTimeExclusive = endSampleTimeExclusive
        self.frameCount = frameCount
        self.bufferCount = bufferCount
    }
}

public struct PCMChunkMetadata: Sendable, Equatable {
    public let sourceSampleTime: Int64
    public let frameCount: Int
    public let precedingLoss: PCMFrameLoss?

    public init(sourceSampleTime: Int64, frameCount: Int, precedingLoss: PCMFrameLoss? = nil) {
        self.sourceSampleTime = sourceSampleTime
        self.frameCount = frameCount
        self.precedingLoss = precedingLoss
    }
}

public enum PCMEnqueueResult: Sendable, Equatable {
    case accepted
    case full(loss: PCMFrameLoss)
    case invalidBuffer
    case closed
}

public enum PCMDequeueResult: Sendable, Equatable {
    case chunk(PCMChunkMetadata)
    case empty
    case tooSmall(requiredFrames: Int)
    case finished(trailingLoss: PCMFrameLoss?)
    case closed
}

/// Test-first interface only. No queue algorithm, validation or pool allocation
/// exists until the accompanying tests have a recorded native behavioral RED.
///
/// The contract has exactly one serial producer and one serial consumer. The
/// app owns its lifetime, starts roles only after initialization, calls finish
/// after producer quiescence, and releases it only after the consumer quiesces.
/// Sendable conformance alone is not evidence that this contract is implemented.
public final class OwnedPCMQueue: @unchecked Sendable {
    /// Total preallocated PCM and per-slot metadata storage must fit this bound.
    /// All size arithmetic must be checked before allocating either pool.
    public static let maximumStorageBytes = 16 * 1_024 * 1_024
    public let configuration: PCMQueueConfiguration

    public init(configuration: PCMQueueConfiguration) throws {
        self.configuration = configuration
    }

    /// Test seam for actual wrapping sequence arithmetic, without billions of
    /// operations. Both roles begin empty at the same initial sequence value.
    init(configuration: PCMQueueConfiguration, initialSequence: UInt64) throws {
        self.configuration = configuration
    }

    /// Accepts AVAudioPCMBuffer.floatChannelData's planar Float32 pointer shape.
    /// The caller supplies at least channelCount valid readable channel pointers
    /// and frameCount readable samples per channel for this call's duration.
    /// Accepted samples must be copied into owned preallocated storage.
    ///
    /// The first valid sample time is arbitrary. Later valid attempts must start
    /// at the preceding valid attempt's exclusive end, including full attempts.
    /// Nil data, wrong channel count, invalid length, discontinuous time or
    /// source-time addition overflow return invalidBuffer without advancing time
    /// or adding capacity loss. Closed takes precedence after finish.
    ///
    /// The adapter must turn a discontinuity, reset or route change into an
    /// explicit gap or clean interruption/new epoch. It must not ignore repeated
    /// invalidBuffer results and silently discard the rest of the recording.
    public func enqueue(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>?,
        channelCount: Int,
        frameCount: Int,
        sourceSampleTime: Int64
    ) -> PCMEnqueueResult {
        .invalidBuffer
    }

    /// The single consumer supplies configuration.channelCount writable planar
    /// channels with at least frameCapacity samples each. Only published frames
    /// may be copied. Insufficient capacity writes nothing and consumes neither
    /// the front chunk nor its preceding loss. Drain returns finished exactly
    /// once after finish and the last chunk, then closed.
    public func dequeue(
        into channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCapacity: Int
    ) -> PCMDequeueResult {
        .empty
    }

    /// Idempotent. Call only after no enqueue is in flight and the producer has
    /// quiesced; a serial owner may then call it while the consumer still drains.
    /// It closes future enqueues and publishes any final capacity loss once.
    public func finish() {}
}
