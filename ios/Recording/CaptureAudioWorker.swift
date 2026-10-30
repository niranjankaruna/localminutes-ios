import AVFoundation
import Dispatch
import Foundation
import Synchronization
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// Copy only native format values across ownership domains, never SDK buffers.
struct CaptureInputDescription: Sendable {
    let sampleRate: Double
    let channelCount: Int

    init(_ format: AVAudioFormat) throws {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0 else { throw CaptureRuntimeFailure.preparationRejected }
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)
    }

    func makeFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                        channels: AVAudioChannelCount(channelCount)) else {
            throw CaptureRuntimeFailure.preparationRejected
        }
        return format
    }
}

/// Stable for one tap epoch. The gate serializes the queue's producer role and
/// publishes its exit to shutdown. Callback faults/readiness use atomic values;
/// polling and all event delivery happen outside the real-time callback.
final class CaptureTapContext: @unchecked Sendable {
    let admission = CaptureCallbackAdmission()
    let queue: OwnedPCMQueue
    let input: CaptureInputDescription
    private let accepted = Atomic<Bool>(false)
    private let fault = Atomic<Int>(0)
    private let afterAdmission: (@Sendable () -> Void)?

    init(input: CaptureInputDescription, configuration: CaptureRuntimeTestConfiguration,
         afterAdmission: (@Sendable () -> Void)?) throws {
        self.input = input
        self.afterAdmission = afterAdmission
        queue = try OwnedPCMQueue(configuration: PCMQueueConfiguration(
            capacity: configuration.queueCapacity,
            maxFramesPerChunk: configuration.maxFramesPerBuffer,
            channelCount: input.channelCount, sampleRate: input.sampleRate
        ))
    }

    var firstBufferAccepted: Bool { accepted.load(ordering: .acquiring) }
    var failure: CaptureRuntimeFailure? {
        switch fault.load(ordering: .acquiring) {
        case 1: .invalidTimestamp
        case 2: .queueLoss
        default: nil
        }
    }

    // Constructed outside an actor-isolated closure and before engine start.
    func makeHandler() -> CaptureTapHandler {
        { [self] buffer, time in receive(buffer, time: time) }
    }

    private func fail(_ code: Int) {
        _ = fault.compareExchange(expected: 0, desired: code, ordering: .releasing)
        admission.close()
    }

    private func receive(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        switch admission.enter() {
        case .closed: return
        case .overlapping:
            fail(2)
            return
        case .admitted: break
        }
        defer { _ = admission.leave() }
        // Nil in every public/production construction. Only deterministic tests
        // pause here; no production callback waits, creates tasks or takes locks.
        afterAdmission?()
        guard time.isSampleTimeValid, time.sampleRate == input.sampleRate else {
            fail(1)
            return
        }
        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.sampleRate == input.sampleRate,
              Int(format.channelCount) == input.channelCount else {
            fail(2)
            return
        }
        switch queue.enqueue(channelData: buffer.floatChannelData,
                             channelCount: input.channelCount,
                             frameCount: Int(buffer.frameLength),
                             sourceSampleTime: time.sampleTime) {
        case .accepted: accepted.store(true, ordering: .releasing)
        case .full: fail(2)
        case .invalidBuffer: fail(2)
        case .closed: fail(2)
        }
    }
}

struct CaptureWorkerFacts: Sendable, Equatable {
    let firstBufferAccepted: Bool
    let failure: CaptureRuntimeFailure?
}

struct CaptureWorkerResult: Sendable {
    let manifest: AudioCaptureManifest?
    let failure: CaptureRuntimeFailure?
}

/// All SDK buffers, converter and file writer below are accessed only on serial.
/// The unchecked conformance transfers this owner, never its mutable SDK state.
final class CaptureAudioWorker: @unchecked Sendable {
    private let serial = DispatchQueue(label: "LocalMinutes.capture.conversion", qos: .userInitiated)
    private let context: CaptureTapContext
    private var converter: PCMStreamConverter?
    private var writer: SegmentCAFWriter?
    private var scratch: AVAudioPCMBuffer?
    private var failure: CaptureRuntimeFailure?
    private var timer: (any DispatchSourceTimer)?
    private var onFacts: (@Sendable (CaptureWorkerFacts) -> Void)?
    private var reportedFacts: CaptureWorkerFacts?
    private var finalResult: CaptureWorkerResult?
    private let normalizedSink: (any NormalizedCaptureSink)?
    private var normalizedFrames: Int64 = 0

    init(context: CaptureTapContext, normalizedSink: (any NormalizedCaptureSink)? = nil) {
        self.context = context
        self.normalizedSink = normalizedSink
    }

    func prepare(directory: URL, sessionID: UUID, maximumSegmentFrames: Int64) async -> CaptureRuntimeFailure? {
        await withCheckedContinuation { continuation in
            serial.async { [self] in
                do {
                    let format = try context.input.makeFormat()
                    converter = try PCMStreamConverter(inputFormat: format)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                        frameCapacity: AVAudioFrameCount(context.queue.configuration.maxFramesPerChunk)) else {
                        throw CaptureRuntimeFailure.preparationRejected
                    }
                    scratch = buffer
                } catch {
                    failure = .preparationRejected
                    continuation.resume(returning: failure)
                    return
                }
                do {
                    writer = try SegmentCAFWriter(directory: directory, sessionID: sessionID,
                                                  maximumSegmentFrames: maximumSegmentFrames)
                    continuation.resume(returning: nil)
                } catch {
                    failure = .writeFailed
                    continuation.resume(returning: failure)
                }
            }
        }
    }

    func beginPolling(onFacts: @escaping @Sendable (CaptureWorkerFacts) -> Void) {
        serial.async { [self] in
            guard finalResult == nil else { return }
            self.onFacts = onFacts
            let source = DispatchSource.makeTimerSource(queue: serial)
            source.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
        }
    }

    private func poll() {
        // Bound each drain to one queue capacity, even if the producer continues.
        if failure == nil { drain(limit: context.queue.configuration.capacity) }
        let facts = CaptureWorkerFacts(firstBufferAccepted: context.firstBufferAccepted,
                                       failure: failure ?? context.failure)
        if facts != reportedFacts {
            reportedFacts = facts
            onFacts?(facts)
        }
    }

    private func fail(_ value: CaptureRuntimeFailure) {
        if failure == nil { failure = value }
        context.admission.close()
    }

    private func write(_ buffers: [AVAudioPCMBuffer]) {
        guard failure == nil, let writer else { return }
        do {
            for buffer in buffers {
                try writer.append(buffer)
                guard buffer.frameLength > 0 else { continue }
                if let normalizedSink,
                   !normalizedSink.offer(buffer, sourceStartSample: normalizedFrames) {
                    fail(.queueLoss)
                    return
                }
                let next = normalizedFrames.addingReportingOverflow(Int64(buffer.frameLength))
                guard !next.overflow else { fail(.queueLoss); return }
                normalizedFrames = next.partialValue
            }
        }
        catch { fail(.writeFailed) }
    }

    private func drain(limit: Int) {
        guard let scratch, let planes = scratch.floatChannelData, let converter else { return }
        for _ in 0..<limit {
            switch context.queue.dequeue(into: planes, frameCapacity: Int(scratch.frameCapacity)) {
            case .chunk(let metadata):
                guard metadata.precedingLoss == nil else { fail(.queueLoss); return }
                scratch.frameLength = AVAudioFrameCount(metadata.frameCount)
                do { write(try converter.append(scratch)) }
                catch { fail(.conversionFailed) }
                if failure != nil { return }
            case .finished(let trailingLoss):
                if trailingLoss != nil { fail(.queueLoss) }
                return
            case .empty, .closed: return
            case .tooSmall: fail(.queueLoss); return
            }
        }
    }

    /// Called only after the control owner acquired closed/quiescent admission.
    /// Timer cancellation and all final SDK/file access remain serial-owned.
    func finish() async -> CaptureWorkerResult {
        await withCheckedContinuation { continuation in
            serial.async { [self] in
                if let finalResult { continuation.resume(returning: finalResult); return }
                timer?.cancel()
                timer = nil
                onFacts = nil
                context.queue.finish()
                if failure == nil { drain(limit: context.queue.configuration.capacity + 1) }
                if failure == nil, let converter {
                    do { write(try converter.finish()) }
                    catch { fail(.conversionFailed) }
                }
                var manifest: AudioCaptureManifest?
                if failure == nil, let writer {
                    do { manifest = try writer.finish() }
                    catch { fail(.writeFailed) }
                }
                let result = CaptureWorkerResult(manifest: manifest, failure: failure ?? context.failure)
                finalResult = result
                continuation.resume(returning: result)
            }
        }
    }
}
