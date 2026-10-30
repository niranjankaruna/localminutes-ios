import Synchronization

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

/// Bounded planar PCM storage for exactly one serial producer and one serial
/// consumer. The app owns its lifetime and starts both roles after initialization.
/// It must synchronize producer quiescence before finish, and synchronize both
/// roles' quiescence before releasing the queue. Finish must never race enqueue.
///
/// Samples and metadata are published by the producer's release of writeSequence.
/// The consumer releases readSequence only after its copy, allowing slot reuse.
/// Ordinary mutable state is private to one role except pendingLoss, which the
/// consumer reads only after acquiring the quiesced producer's finish publication.
public final class OwnedPCMQueue: @unchecked Sendable {
    /// Total preallocated PCM and per-slot metadata storage must fit this bound.
    /// All size arithmetic must be checked before allocating either pool.
    public static let maximumStorageBytes = 16 * 1_024 * 1_024
    public let configuration: PCMQueueConfiguration

    private let samplesPerSlot: Int
    private let sampleCount: Int
    private let slotMask: UInt64
    private let samplePool: UnsafeMutablePointer<Float>
    private let metadataPool: UnsafeMutablePointer<PCMChunkMetadata>
    private let writeSequence: Atomic<UInt64>
    private let readSequence: Atomic<UInt64>
    private let producerFinished = Atomic<Bool>(false)

    // Producer-only until producerFinished publishes the stable pending loss.
    private var expectedSourceSampleTime: Int64?
    private var pendingLoss: PCMFrameLoss?
    // Consumer-only; returning finished consumes the terminal result once.
    private var consumerDidFinish = false

    public convenience init(configuration: PCMQueueConfiguration) throws {
        try self.init(configuration: configuration, initialSequence: 0)
    }

    /// Test seam for actual wrapping sequence arithmetic, without billions of
    /// operations. Both roles begin empty at the same initial sequence value.
    init(configuration: PCMQueueConfiguration, initialSequence: UInt64) throws {
        guard configuration.capacity > 0,
              (configuration.capacity & (configuration.capacity - 1)) == 0 else {
            throw PCMQueueConfigurationError.invalidCapacity
        }
        guard configuration.maxFramesPerChunk > 0 else {
            throw PCMQueueConfigurationError.invalidFrameLimit
        }
        guard configuration.channelCount > 0 else {
            throw PCMQueueConfigurationError.invalidChannelCount
        }
        guard configuration.sampleRate.isFinite, configuration.sampleRate > 0 else {
            throw PCMQueueConfigurationError.invalidSampleRate
        }

        let (slotSamples, slotOverflow) = configuration.maxFramesPerChunk
            .multipliedReportingOverflow(by: configuration.channelCount)
        let (allSamples, samplesOverflow) = slotSamples
            .multipliedReportingOverflow(by: configuration.capacity)
        let (sampleBytes, bytesOverflow) = allSamples
            .multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
        let (metadataBytes, metadataOverflow) = configuration.capacity
            .multipliedReportingOverflow(by: MemoryLayout<PCMChunkMetadata>.stride)
        let (totalBytes, totalOverflow) = sampleBytes.addingReportingOverflow(metadataBytes)
        guard !slotOverflow, !samplesOverflow, !bytesOverflow,
              !metadataOverflow, !totalOverflow, totalBytes <= Self.maximumStorageBytes else {
            throw PCMQueueConfigurationError.storageLimitExceeded
        }

        self.configuration = configuration
        samplesPerSlot = slotSamples
        sampleCount = allSamples
        slotMask = UInt64(configuration.capacity - 1)
        writeSequence = Atomic<UInt64>(initialSequence)
        readSequence = Atomic<UInt64>(initialSequence)
        samplePool = .allocate(capacity: allSamples)
        metadataPool = .allocate(capacity: configuration.capacity)
        // Initialize and touch both pools before the producer can start. Slot
        // overwrite/copy thereafter uses already initialized trivial values.
        samplePool.initialize(repeating: 0, count: allSamples)
        metadataPool.initialize(
            repeating: PCMChunkMetadata(sourceSampleTime: 0, frameCount: 0),
            count: configuration.capacity
        )
    }

    deinit {
        // The caller's lifetime contract guarantees neither role is in flight.
        samplePool.deinitialize(count: sampleCount)
        samplePool.deallocate()
        metadataPool.deinitialize(count: configuration.capacity)
        metadataPool.deallocate()
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
        guard !producerFinished.load(ordering: .acquiring) else { return .closed }
        guard let channelData,
              channelCount == configuration.channelCount,
              frameCount > 0,
              frameCount <= configuration.maxFramesPerChunk,
              let sourceFrames = Int64(exactly: frameCount) else {
            return .invalidBuffer
        }
        let (sourceEnd, timeOverflow) = sourceSampleTime.addingReportingOverflow(sourceFrames)
        guard !timeOverflow else { return .invalidBuffer }
        if let expectedSourceSampleTime, sourceSampleTime != expectedSourceSampleTime {
            return .invalidBuffer
        }

        let write = writeSequence.load(ordering: .relaxed)
        let read = readSequence.load(ordering: .acquiring)
        if (write &- read) >= UInt64(configuration.capacity) {
            let lost = PCMFrameLoss(
                startSampleTime: sourceSampleTime,
                endSampleTimeExclusive: sourceEnd,
                frameCount: UInt64(frameCount),
                bufferCount: 1
            )
            if let previous = pendingLoss {
                // Positive contiguous frames and the checked Int64 source end
                // bound the entire interval to UInt64.max frames. Each lost
                // buffer contains at least one frame, so neither count wraps.
                pendingLoss = PCMFrameLoss(
                    startSampleTime: previous.startSampleTime,
                    endSampleTimeExclusive: sourceEnd,
                    frameCount: previous.frameCount + lost.frameCount,
                    bufferCount: previous.bufferCount + 1
                )
            } else {
                pendingLoss = lost
            }
            expectedSourceSampleTime = sourceEnd
            return .full(loss: lost)
        }

        let slot = Int(write & slotMask)
        let slotOffset = slot * samplesPerSlot
        var channel = 0
        while channel < configuration.channelCount {
            samplePool.advanced(by: slotOffset + channel * configuration.maxFramesPerChunk)
                .update(from: channelData[channel], count: frameCount)
            channel += 1
        }
        metadataPool[slot] = PCMChunkMetadata(
            sourceSampleTime: sourceSampleTime,
            frameCount: frameCount,
            precedingLoss: pendingLoss
        )
        pendingLoss = nil
        expectedSourceSampleTime = sourceEnd
        writeSequence.store(write &+ 1, ordering: .releasing)
        return .accepted
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
        guard !consumerDidFinish else { return .closed }
        let read = readSequence.load(ordering: .relaxed)
        var write = writeSequence.load(ordering: .acquiring)
        if read == write {
            guard producerFinished.load(ordering: .acquiring) else { return .empty }
            // The first write load may precede the final producer publication.
            // Acquiring finish makes all prior publications visible; reload
            // afterward so a stale empty observation cannot skip the last chunk.
            write = writeSequence.load(ordering: .acquiring)
            if read == write {
                consumerDidFinish = true
                return .finished(trailingLoss: pendingLoss)
            }
        }

        let slot = Int(read & slotMask)
        let metadata = metadataPool[slot]
        guard frameCapacity >= metadata.frameCount else {
            return .tooSmall(requiredFrames: metadata.frameCount)
        }
        let slotOffset = slot * samplesPerSlot
        var channel = 0
        while channel < configuration.channelCount {
            channelData[channel].update(
                from: samplePool.advanced(
                    by: slotOffset + channel * configuration.maxFramesPerChunk
                ),
                count: metadata.frameCount
            )
            channel += 1
        }
        readSequence.store(read &+ 1, ordering: .releasing)
        return .chunk(metadata)
    }

    /// Idempotent. Call only after no enqueue is in flight and the producer has
    /// quiesced; a serial owner may then call it while the consumer still drains.
    /// It closes future enqueues and publishes any final capacity loss once.
    public func finish() {
        producerFinished.store(true, ordering: .releasing)
    }
}
