import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import LocalMinutesCore

// These are synthetic planar PCM fixtures, not microphone or device evidence.
// Each buffer has one serial owner while the stress workers are running.
private final class PlanarPCMBuffer: @unchecked Sendable {
    let channelCount: Int
    let frameCapacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private let channelTable: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    init(channelCount: Int, frameCapacity: Int, fill: Float = -999) {
        self.channelCount = channelCount
        self.frameCapacity = frameCapacity
        samples = .allocate(capacity: channelCount * frameCapacity)
        channelTable = .allocate(capacity: channelCount)
        samples.initialize(repeating: fill, count: channelCount * frameCapacity)
        for channel in 0..<channelCount {
            channelTable.advanced(by: channel).initialize(
                to: samples.advanced(by: channel * frameCapacity)
            )
        }
    }

    deinit {
        channelTable.deinitialize(count: channelCount)
        channelTable.deallocate()
        samples.deinitialize(count: channelCount * frameCapacity)
        samples.deallocate()
    }

    var channelData: UnsafePointer<UnsafeMutablePointer<Float>> {
        UnsafePointer(channelTable)
    }

    subscript(channel: Int, frame: Int) -> Float {
        get { channelTable[channel][frame] }
        set { channelTable[channel][frame] = newValue }
    }

    func fill(token: Int, frameCount: Int) {
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                self[channel, frame] = pcmSample(token: token, channel: channel, frame: frame)
            }
        }
    }

    func overwrite(with value: Float) {
        for index in 0..<(channelCount * frameCapacity) {
            samples[index] = value
        }
    }
}

private func pcmSample(token: Int, channel: Int, frame: Int) -> Float {
    // The stress test stays below 2^24, so every encoded integer is exact in Float32.
    Float(token * 64 + channel * 16 + frame)
}

private struct ProducerAttempt: Sendable {
    let token: Int
    let sourceSampleTime: Int64
    let frameCount: Int
    let result: PCMEnqueueResult
}

// Each result box is written by only its own worker and read after group.wait.
private final class ProducerObservations: @unchecked Sendable {
    var attempts: [ProducerAttempt] = []
    var synchronizationFailed = false
}

private final class ConsumerObservations: @unchecked Sendable {
    var chunks: [PCMChunkMetadata] = []
    var payloadTokens: [Int] = []
    var payloadValid = true
    var sawFinished = false
    var trailingLoss: PCMFrameLoss?
    var closedAfterFinished = false
    var error: String?
}

private final class StressSignals: Sendable {
    let warmupPublished = Atomic<Bool>(false)
    let firstChunkConsumed = Atomic<Bool>(false)
    let producerFinished = Atomic<Bool>(false)
}

final class OwnedPCMQueueTests: XCTestCase {
    private func configuration(
        capacity: Int = 4,
        maxFrames: Int = 5,
        channels: Int = 2,
        sampleRate: Double = 48_000
    ) -> PCMQueueConfiguration {
        PCMQueueConfiguration(
            capacity: capacity,
            maxFramesPerChunk: maxFrames,
            channelCount: channels,
            sampleRate: sampleRate
        )
    }

    @discardableResult
    private func enqueue(
        _ queue: OwnedPCMQueue,
        source: PlanarPCMBuffer,
        time: Int64,
        frames: Int,
        token: Int
    ) -> PCMEnqueueResult {
        source.fill(token: token, frameCount: frames)
        return queue.enqueue(
            channelData: source.channelData,
            channelCount: source.channelCount,
            frameCount: frames,
            sourceSampleTime: time
        )
    }

    private func assertChunk(
        _ queue: OwnedPCMQueue,
        into destination: PlanarPCMBuffer,
        time: Int64,
        frames: Int,
        token: Int,
        loss: PCMFrameLoss? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = queue.dequeue(
            into: destination.channelData,
            frameCapacity: destination.frameCapacity
        )
        guard case .chunk(let metadata) = result else {
            XCTFail("Expected owned PCM chunk, got \(result)", file: file, line: line)
            return
        }
        XCTAssertEqual(
            metadata,
            PCMChunkMetadata(sourceSampleTime: time, frameCount: frames, precedingLoss: loss),
            file: file,
            line: line
        )
        for channel in 0..<destination.channelCount {
            for frame in 0..<frames {
                XCTAssertEqual(
                    destination[channel, frame],
                    pcmSample(token: token, channel: channel, frame: frame),
                    "Channel \(channel), frame \(frame) must match its accepted source",
                    file: file,
                    line: line
                )
            }
        }
    }

    func testConfigurationIsPreservedAndEmptyQueueFinishesExactlyOnce() throws {
        let config = configuration()
        let queue = try OwnedPCMQueue(configuration: config)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(queue.configuration, config)
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .empty
        )

        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .closed
        )
    }

    func testCapacityMustBeAPositivePowerOfTwo() {
        for capacity in [0, -1, 3, 6, Int.max] {
            XCTAssertThrowsError(try OwnedPCMQueue(configuration: configuration(capacity: capacity))) {
                XCTAssertEqual($0 as? PCMQueueConfigurationError, .invalidCapacity)
            }
        }
    }

    func testFrameAndChannelLimitsMustBePositive() {
        for frames in [0, -1] {
            XCTAssertThrowsError(try OwnedPCMQueue(configuration: configuration(maxFrames: frames))) {
                XCTAssertEqual($0 as? PCMQueueConfigurationError, .invalidFrameLimit)
            }
        }
        for channels in [0, -1] {
            XCTAssertThrowsError(try OwnedPCMQueue(configuration: configuration(channels: channels))) {
                XCTAssertEqual($0 as? PCMQueueConfigurationError, .invalidChannelCount)
            }
        }
    }

    func testSampleRateMustBeFiniteAndPositive() {
        for rate in [0, -48_000, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try OwnedPCMQueue(configuration: configuration(sampleRate: rate))) {
                XCTAssertEqual($0 as? PCMQueueConfigurationError, .invalidSampleRate)
            }
        }
    }

    func testStorageLimitAndArithmeticOverflowAreRejectedBeforeAllocation() {
        XCTAssertEqual(OwnedPCMQueue.maximumStorageBytes, 16 * 1_024 * 1_024)
        let tooManySamples = OwnedPCMQueue.maximumStorageBytes / MemoryLayout<Float>.stride + 1
        let invalid = [
            configuration(capacity: 1, maxFrames: tooManySamples, channels: 1),
            configuration(capacity: 1, maxFrames: Int.max, channels: 2),
            configuration(capacity: 1 << (Int.bitWidth - 2), maxFrames: 8, channels: 2),
            configuration(capacity: 1, maxFrames: 2, channels: Int.max)
        ]
        for config in invalid {
            XCTAssertThrowsError(try OwnedPCMQueue(configuration: config)) {
                XCTAssertEqual($0 as? PCMQueueConfigurationError, .storageLimitExceeded)
            }
        }
    }

    func testStorageLimitIncludesBoundedPerSlotMetadata() {
        // PCM alone is 8 MiB. Two million slot timing/frame/loss records cannot
        // fit in the remaining 8 MiB; bounding only the sample bytes is unsafe.
        let config = configuration(capacity: 1 << 21, maxFrames: 1, channels: 1)
        XCTAssertThrowsError(try OwnedPCMQueue(configuration: config)) {
            XCTAssertEqual($0 as? PCMQueueConfigurationError, .storageLimitExceeded)
        }
    }

    func testFIFOIncludesVariableLengthsAndBothPlanarChannels() throws {
        let queue = try OwnedPCMQueue(configuration: configuration())
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 2, token: 1), .accepted)
        XCTAssertEqual(enqueue(queue, source: source, time: 2, frames: 5, token: 2), .accepted)
        XCTAssertEqual(enqueue(queue, source: source, time: 7, frames: 1, token: 3), .accepted)

        assertChunk(queue, into: destination, time: 0, frames: 2, token: 1)
        assertChunk(queue, into: destination, time: 2, frames: 5, token: 2)
        assertChunk(queue, into: destination, time: 7, frames: 1, token: 3)
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .empty)
    }

    func testAcceptedPCMIsOwnedAndSurvivesSourceMutation() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 50, frames: 5, token: 7), .accepted)
        source.overwrite(with: -321)
        assertChunk(queue, into: destination, time: 50, frames: 5, token: 7)
    }

    func testMonoConfigurationCopiesItsSingleChannelAtItsConfiguredSampleRate() throws {
        let config = configuration(capacity: 1, maxFrames: 4, channels: 1, sampleRate: 16_000)
        let queue = try OwnedPCMQueue(configuration: config)
        let source = PlanarPCMBuffer(channelCount: 1, frameCapacity: 4)
        let destination = PlanarPCMBuffer(channelCount: 1, frameCapacity: 4)
        XCTAssertEqual(queue.configuration, config)
        XCTAssertEqual(enqueue(queue, source: source, time: 800, frames: 4, token: 6), .accepted)
        assertChunk(queue, into: destination, time: 800, frames: 4, token: 6)
    }

    func testDequeueCopiesOnlyPublishedFrames() throws {
        let queue = try OwnedPCMQueue(configuration: configuration())
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5, fill: -777)
        XCTAssertEqual(enqueue(queue, source: source, time: 10, frames: 2, token: 4), .accepted)
        assertChunk(queue, into: destination, time: 10, frames: 2, token: 4)
        for channel in 0..<2 {
            for frame in 2..<5 {
                XCTAssertEqual(destination[channel, frame], -777)
            }
        }
    }

    func testAllConfiguredSlotsAreUsableAndFreedSlotsCanBeReused() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 2))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 2, token: 1), .accepted)
        XCTAssertEqual(enqueue(queue, source: source, time: 2, frames: 3, token: 2), .accepted)
        let dropped = PCMFrameLoss(
            startSampleTime: 5, endSampleTimeExclusive: 6, frameCount: 1, bufferCount: 1
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 5, frames: 1, token: 3),
            .full(loss: dropped)
        )
        assertChunk(queue, into: destination, time: 0, frames: 2, token: 1)
        XCTAssertEqual(enqueue(queue, source: source, time: 6, frames: 2, token: 4), .accepted)
        assertChunk(queue, into: destination, time: 2, frames: 3, token: 2)
        assertChunk(queue, into: destination, time: 6, frames: 2, token: 4, loss: dropped)
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .empty)
    }

    func testNilInvalidLengthsAndWrongChannelCountDoNotPublishOrAdvanceTime() throws {
        let queue = try OwnedPCMQueue(configuration: configuration())
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 6)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(
            queue.enqueue(channelData: nil, channelCount: 2, frameCount: 2, sourceSampleTime: 100),
            .invalidBuffer
        )
        for frames in [-1, 0, 6, Int.max] {
            XCTAssertEqual(
                queue.enqueue(
                    channelData: source.channelData, channelCount: 2,
                    frameCount: frames, sourceSampleTime: 100
                ),
                .invalidBuffer
            )
        }
        for channels in [-1, 0, 1, 3] {
            XCTAssertEqual(
                queue.enqueue(
                    channelData: source.channelData, channelCount: channels,
                    frameCount: 2, sourceSampleTime: 100
                ),
                .invalidBuffer
            )
        }
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .empty)
        XCTAssertEqual(enqueue(queue, source: source, time: 100, frames: 2, token: 9), .accepted)
        assertChunk(queue, into: destination, time: 100, frames: 2, token: 9)
    }

    func testFirstSampleTimeMayBeArbitraryIncludingNegativeValues() throws {
        for firstTime in [Int64.min, Int64(-1_000), Int64(123_456)] {
            let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
            let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
            let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
            XCTAssertEqual(
                enqueue(queue, source: source, time: firstTime, frames: 2, token: 1),
                .accepted
            )
            assertChunk(queue, into: destination, time: firstTime, frames: 2, token: 1)
            XCTAssertEqual(
                enqueue(queue, source: source, time: firstTime + 2, frames: 1, token: 2),
                .accepted
            )
            assertChunk(queue, into: destination, time: firstTime + 2, frames: 1, token: 2)
        }
    }

    func testOutOfOrderAndDiscontinuousInputIsRejectedWithoutAdvancingTimeline() throws {
        let queue = try OwnedPCMQueue(configuration: configuration())
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 100, frames: 2, token: 1), .accepted)
        for time in [Int64(99), 100, 101, 103, 1_000] {
            XCTAssertEqual(
                enqueue(queue, source: source, time: time, frames: 2, token: 8),
                .invalidBuffer
            )
        }
        XCTAssertEqual(enqueue(queue, source: source, time: 102, frames: 3, token: 2), .accepted)
        assertChunk(queue, into: destination, time: 100, frames: 2, token: 1)
        assertChunk(queue, into: destination, time: 102, frames: 3, token: 2)
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
    }

    func testSourceTimeAdditionOverflowIsInvalidBeforeCopyOrLossAccounting() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(
            enqueue(queue, source: source, time: Int64.max - 1, frames: 2, token: 1),
            .invalidBuffer
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: Int64.max - 2, frames: 2, token: 2),
            .accepted
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: Int64.max, frames: 1, token: 3),
            .invalidBuffer
        )
        assertChunk(queue, into: destination, time: Int64.max - 2, frames: 2, token: 2)
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
    }

    func testFullAttemptsAdvanceTimeAndInvalidAttemptsDoNotChangePendingLoss() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 20, frames: 2, token: 1), .accepted)
        let lost = PCMFrameLoss(
            startSampleTime: 22, endSampleTimeExclusive: 25, frameCount: 3, bufferCount: 1
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 22, frames: 3, token: 2),
            .full(loss: lost)
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 22, frames: 3, token: 3),
            .invalidBuffer
        )
        XCTAssertEqual(
            queue.enqueue(channelData: nil, channelCount: 2, frameCount: 2, sourceSampleTime: 25),
            .invalidBuffer
        )
        assertChunk(queue, into: destination, time: 20, frames: 2, token: 1)
        XCTAssertEqual(enqueue(queue, source: source, time: 25, frames: 2, token: 4), .accepted)
        assertChunk(queue, into: destination, time: 25, frames: 2, token: 4, loss: lost)
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
    }

    func testConsecutiveFullBuffersAreReportedOnceBeforeNextAcceptedChunk() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 2, token: 1), .accepted)
        XCTAssertEqual(
            enqueue(queue, source: source, time: 2, frames: 3, token: 2),
            .full(loss: PCMFrameLoss(
                startSampleTime: 2, endSampleTimeExclusive: 5, frameCount: 3, bufferCount: 1
            ))
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 5, frames: 1, token: 3),
            .full(loss: PCMFrameLoss(
                startSampleTime: 5, endSampleTimeExclusive: 6, frameCount: 1, bufferCount: 1
            ))
        )
        assertChunk(queue, into: destination, time: 0, frames: 2, token: 1)
        XCTAssertEqual(enqueue(queue, source: source, time: 6, frames: 4, token: 4), .accepted)
        let combined = PCMFrameLoss(
            startSampleTime: 2, endSampleTimeExclusive: 6, frameCount: 4, bufferCount: 2
        )
        assertChunk(queue, into: destination, time: 6, frames: 4, token: 4, loss: combined)
        XCTAssertEqual(enqueue(queue, source: source, time: 10, frames: 1, token: 5), .accepted)
        assertChunk(queue, into: destination, time: 10, frames: 1, token: 5)
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
    }

    func testFinishDrainsQueuedFIFOAndReportsTrailingLossExactlyOnce() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 2))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 2, token: 1), .accepted)
        XCTAssertEqual(enqueue(queue, source: source, time: 2, frames: 1, token: 2), .accepted)
        XCTAssertEqual(
            enqueue(queue, source: source, time: 3, frames: 4, token: 3),
            .full(loss: PCMFrameLoss(
                startSampleTime: 3, endSampleTimeExclusive: 7, frameCount: 4, bufferCount: 1
            ))
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 7, frames: 2, token: 4),
            .full(loss: PCMFrameLoss(
                startSampleTime: 7, endSampleTimeExclusive: 9, frameCount: 2, bufferCount: 1
            ))
        )

        // The producer has quiesced before finish; the consumer may still drain.
        queue.finish()
        queue.finish()
        assertChunk(queue, into: destination, time: 0, frames: 2, token: 1)
        assertChunk(queue, into: destination, time: 2, frames: 1, token: 2)
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: PCMFrameLoss(
                startSampleTime: 3, endSampleTimeExclusive: 9, frameCount: 6, bufferCount: 2
            ))
        )
        queue.finish()
        for _ in 0..<3 {
            XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .closed)
        }
    }

    func testLateWritesAreClosedAndCannotChangeDrainingDataOrTrailingLoss() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 2, token: 1), .accepted)
        let lost = PCMFrameLoss(
            startSampleTime: 2, endSampleTimeExclusive: 3, frameCount: 1, bufferCount: 1
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 2, frames: 1, token: 2),
            .full(loss: lost)
        )
        queue.finish()
        XCTAssertEqual(enqueue(queue, source: source, time: 3, frames: 1, token: 9), .closed)
        XCTAssertEqual(
            queue.enqueue(channelData: nil, channelCount: 0, frameCount: 0, sourceSampleTime: 0),
            .closed
        )
        assertChunk(queue, into: destination, time: 0, frames: 2, token: 1)
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: lost)
        )
        XCTAssertEqual(enqueue(queue, source: source, time: 3, frames: 1, token: 10), .closed)
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .closed)
    }

    func testInsufficientDestinationDoesNotWriteOrConsumeChunkAndItsLoss() throws {
        let queue = try OwnedPCMQueue(configuration: configuration(capacity: 1))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5, fill: -123)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 1, token: 1), .accepted)
        let lost = PCMFrameLoss(
            startSampleTime: 1, endSampleTimeExclusive: 3, frameCount: 2, bufferCount: 1
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 1, frames: 2, token: 2),
            .full(loss: lost)
        )
        assertChunk(queue, into: destination, time: 0, frames: 1, token: 1)
        destination.overwrite(with: -123)
        XCTAssertEqual(enqueue(queue, source: source, time: 3, frames: 4, token: 3), .accepted)

        for capacity in [-1, 0, 3] {
            XCTAssertEqual(
                queue.dequeue(into: destination.channelData, frameCapacity: capacity),
                .tooSmall(requiredFrames: 4)
            )
            for channel in 0..<2 {
                for frame in 0..<5 {
                    XCTAssertEqual(destination[channel, frame], -123)
                }
            }
        }
        queue.finish()
        assertChunk(queue, into: destination, time: 3, frames: 4, token: 3, loss: lost)
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
    }

    func testSequenceCountersWrapWithoutLosingFullEmptyFIFOOrLossState() throws {
        let queue = try OwnedPCMQueue(
            configuration: configuration(capacity: 2),
            initialSequence: UInt64.max - 1
        )
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: 5)
        XCTAssertEqual(enqueue(queue, source: source, time: 0, frames: 1, token: 1), .accepted)
        XCTAssertEqual(enqueue(queue, source: source, time: 1, frames: 1, token: 2), .accepted)
        assertChunk(queue, into: destination, time: 0, frames: 1, token: 1)
        XCTAssertEqual(enqueue(queue, source: source, time: 2, frames: 1, token: 3), .accepted)
        let lost = PCMFrameLoss(
            startSampleTime: 3, endSampleTimeExclusive: 4, frameCount: 1, bufferCount: 1
        )
        XCTAssertEqual(
            enqueue(queue, source: source, time: 3, frames: 1, token: 4),
            .full(loss: lost)
        )
        assertChunk(queue, into: destination, time: 1, frames: 1, token: 2)
        XCTAssertEqual(enqueue(queue, source: source, time: 4, frames: 1, token: 5), .accepted)
        assertChunk(queue, into: destination, time: 2, frames: 1, token: 3)
        assertChunk(queue, into: destination, time: 4, frames: 1, token: 5, loss: lost)
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .empty)
        queue.finish()
        XCTAssertEqual(
            queue.dequeue(into: destination.channelData, frameCapacity: 5),
            .finished(trailingLoss: nil)
        )
        XCTAssertEqual(queue.dequeue(into: destination.channelData, frameCapacity: 5), .closed)
    }

    func testParallelSPSCStressPreservesAcceptedSamplesOrderAndAllDroppedFrames() throws {
        let attemptCount = 20_000
        let capacity = 8
        let maxFrames = 7
        let queue = try OwnedPCMQueue(configuration: configuration(
            capacity: capacity, maxFrames: maxFrames, channels: 2
        ))
        let source = PlanarPCMBuffer(channelCount: 2, frameCapacity: maxFrames)
        let destination = PlanarPCMBuffer(channelCount: 2, frameCapacity: maxFrames)
        let producer = ProducerObservations()
        let consumer = ConsumerObservations()
        let signals = StressSignals()
        let group = DispatchGroup()
        let producerQueue = DispatchQueue(label: "LocalMinutes.tests.pcm.producer")
        let consumerQueue = DispatchQueue(label: "LocalMinutes.tests.pcm.consumer")

        producerQueue.async(group: group) {
            producer.attempts.reserveCapacity(attemptCount)
            var sourceTime: Int64 = 4_000
            for token in 0..<attemptCount {
                let frames = token % maxFrames + 1
                source.fill(token: token, frameCount: frames)
                let result = queue.enqueue(
                    channelData: source.channelData, channelCount: 2,
                    frameCount: frames, sourceSampleTime: sourceTime
                )
                producer.attempts.append(ProducerAttempt(
                    token: token, sourceSampleTime: sourceTime, frameCount: frames, result: result
                ))
                sourceTime += Int64(frames)
                if token == capacity {
                    // Ensure the full path is exercised before allowing a drain.
                    signals.warmupPublished.store(true, ordering: .releasing)
                    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
                    while !signals.firstChunkConsumed.load(ordering: .acquiring) {
                        if DispatchTime.now().uptimeNanoseconds >= deadline {
                            producer.synchronizationFailed = true
                            break
                        }
                        // Test scheduling only; the production callback must never wait.
                        Thread.sleep(forTimeInterval: 0.000_01)
                    }
                } else if token % 64 == 0 {
                    // Allow interleavings on a busy CI host; no throughput claim is made.
                    Thread.sleep(forTimeInterval: 0.000_01)
                }
            }
            queue.finish()
            signals.producerFinished.store(true, ordering: .releasing)
        }

        consumerQueue.async(group: group) {
            consumer.chunks.reserveCapacity(attemptCount)
            consumer.payloadTokens.reserveCapacity(attemptCount)
            let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
            while !signals.warmupPublished.load(ordering: .acquiring) {
                if DispatchTime.now().uptimeNanoseconds >= deadline {
                    consumer.error = "The producer did not reach the bounded warmup"
                    return
                }
                Thread.sleep(forTimeInterval: 0.000_01)
            }

            var polls = 0
            var emptyPollsAfterProducer = 0
            while polls < attemptCount * 128 &&
                    DispatchTime.now().uptimeNanoseconds < deadline {
                polls += 1
                switch queue.dequeue(into: destination.channelData, frameCapacity: maxFrames) {
                case .chunk(let metadata):
                    signals.firstChunkConsumed.store(true, ordering: .releasing)
                    consumer.chunks.append(metadata)
                    let firstSample = destination[0, 0]
                    guard firstSample.isFinite,
                          firstSample >= 0,
                          firstSample < Float(attemptCount * 64) else {
                        consumer.payloadValid = false
                        continue
                    }
                    let token = Int(firstSample) / 64
                    consumer.payloadTokens.append(token)
                    if metadata.frameCount != token % maxFrames + 1 {
                        consumer.payloadValid = false
                    }
                    guard metadata.frameCount > 0 && metadata.frameCount <= maxFrames else {
                        consumer.payloadValid = false
                        continue
                    }
                    for channel in 0..<2 {
                        for frame in 0..<metadata.frameCount {
                            if destination[channel, frame] !=
                                    pcmSample(token: token, channel: channel, frame: frame) {
                                consumer.payloadValid = false
                            }
                        }
                    }
                case .empty:
                    if signals.producerFinished.load(ordering: .acquiring) {
                        emptyPollsAfterProducer += 1
                        if emptyPollsAfterProducer >= 4_096 {
                            consumer.error = "Finished producer never yielded its final drain result"
                            return
                        }
                    }
                    if polls % 64 == 0 { Thread.sleep(forTimeInterval: 0.000_01) }
                case .finished(let trailingLoss):
                    consumer.sawFinished = true
                    consumer.trailingLoss = trailingLoss
                    consumer.closedAfterFinished =
                        queue.dequeue(into: destination.channelData, frameCapacity: maxFrames) == .closed
                    return
                case .tooSmall:
                    consumer.error = "A destination sized for maxFrames was rejected"
                    return
                case .closed:
                    consumer.error = "Closed was observed without the once-only finished result"
                    return
                }
            }
            consumer.error = "Bounded stress poll/deadline limit was reached"
        }

        let completion = group.wait(timeout: .now() + 8)
        guard completion == .success else {
            XCTFail("Parallel SPSC workers exceeded the bounded test timeout")
            return
        }
        XCTAssertFalse(producer.synchronizationFailed, "The consumer must drain while producer is active")
        XCTAssertNil(consumer.error)
        XCTAssertEqual(producer.attempts.count, attemptCount)
        XCTAssertTrue(consumer.payloadValid, "No chunk may contain torn, aliased or reordered PCM")
        XCTAssertTrue(consumer.sawFinished)
        XCTAssertTrue(consumer.closedAfterFinished)

        var accepted: [PCMChunkMetadata] = []
        var acceptedTokens: [Int] = []
        var droppedFrames: UInt64 = 0
        var droppedBuffers = 0
        var fullResultsValid = true
        var invalidResults = 0
        var pendingLoss: PCMFrameLoss?
        for attempt in producer.attempts {
            switch attempt.result {
            case .accepted:
                accepted.append(PCMChunkMetadata(
                    sourceSampleTime: attempt.sourceSampleTime,
                    frameCount: attempt.frameCount,
                    precedingLoss: pendingLoss
                ))
                acceptedTokens.append(attempt.token)
                pendingLoss = nil
            case .full(let loss):
                let end = attempt.sourceSampleTime + Int64(attempt.frameCount)
                if loss != PCMFrameLoss(
                    startSampleTime: attempt.sourceSampleTime, endSampleTimeExclusive: end,
                    frameCount: UInt64(attempt.frameCount), bufferCount: 1
                ) {
                    fullResultsValid = false
                }
                droppedFrames += UInt64(attempt.frameCount)
                droppedBuffers += 1
                pendingLoss = PCMFrameLoss(
                    startSampleTime: pendingLoss?.startSampleTime ?? attempt.sourceSampleTime,
                    endSampleTimeExclusive: end,
                    frameCount: (pendingLoss?.frameCount ?? 0) + UInt64(attempt.frameCount),
                    bufferCount: (pendingLoss?.bufferCount ?? 0) + 1
                )
            case .invalidBuffer, .closed:
                invalidResults += 1
            }
        }
        XCTAssertEqual(invalidResults, 0)
        XCTAssertTrue(fullResultsValid, "Each full result must identify exactly its dropped attempt")
        XCTAssertGreaterThan(accepted.count, capacity)
        XCTAssertGreaterThan(droppedBuffers, 0)
        XCTAssertEqual(accepted.count + droppedBuffers, attemptCount)
        XCTAssertEqual(consumer.chunks.count, accepted.count)
        XCTAssertTrue(
            consumer.chunks == accepted,
            "Consumer timing, FIFO order and loss metadata must match every accepted attempt"
        )
        XCTAssertTrue(
            consumer.payloadTokens == acceptedTokens,
            "Every accepted attempt must appear once in the same order"
        )
        XCTAssertEqual(consumer.trailingLoss, pendingLoss)

        let reportedLoss = consumer.chunks.compactMap(\.precedingLoss)
            + (consumer.trailingLoss.map { [$0] } ?? [])
        XCTAssertEqual(reportedLoss.reduce(UInt64(0)) { $0 + $1.frameCount }, droppedFrames)
        XCTAssertEqual(
            reportedLoss.reduce(UInt64(0)) { $0 + $1.bufferCount },
            UInt64(droppedBuffers)
        )
    }
}
