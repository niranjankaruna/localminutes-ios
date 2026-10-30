import AVFoundation
import Foundation
import Observation
import Synchronization
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesRecording
import LocalMinutesModels
import LocalMinutesPersistence
#endif

public struct LiveTranscriptSnapshot: Equatable, Sendable {
    public let sessionID: UUID?
    public let partial: String
    public let finalized: [StoredTranscriptSegment]
    public let receivedSampleCount: Int64
    public let failure: RecordingFailure?

    public init(sessionID: UUID? = nil, partial: String = "",
                finalized: [StoredTranscriptSegment] = [], receivedSampleCount: Int64 = 0,
                failure: RecordingFailure? = nil) {
        self.sessionID = sessionID; self.partial = partial; self.finalized = finalized
        self.receivedSampleCount = receivedSampleCount; self.failure = failure
    }
}

@MainActor @Observable
public final class LiveTranscriptionSession: RecordingPreparationSource {
    public let normalizedSink: (any NormalizedCaptureSink)?
    public private(set) var transcript = LiveTranscriptSnapshot()
    private let models: ModelInstallationManager
    private let store: SQLiteMeetingStore
    private let meetingsDirectory: URL
    private let router: TranscriptSinkRouter
    private let storageReserveBytes: Int64
    @ObservationIgnored private let runtimeFactory: SpeechModelRuntimeFactory
    private let availableStorageBytes: @MainActor (URL) throws -> Int64
    @ObservationIgnored private let metrics: TranscriptionMetricsRecorder?
    // Evaluated once per reserved epoch. An in-flight recording retains its
    // exact approved manifest and model-file lease across later UI changes.
    @ObservationIgnored private let selectedSpeechModel: @MainActor () async throws -> ModelManifest?
    var metricsRecorder: TranscriptionMetricsRecorder? { metrics }
    @ObservationIgnored private var current: LiveTranscriptEpoch?

    public init(models: ModelInstallationManager, store: SQLiteMeetingStore,
                meetingsDirectory: URL, metrics: TranscriptionMetricsRecorder? = nil,
                storageReserveBytes: Int64 = 1_000_000_000,
                availableStorageBytes: @escaping @MainActor (URL) throws -> Int64 = {
                    try ModelStoragePolicy.availableBytes(at: $0)
                },
                runtimeFactory: @escaping SpeechModelRuntimeFactory = SpeechModelRuntimeRegistry.makeRuntime,
                selectedSpeechModel: @escaping @MainActor () async throws -> ModelManifest? = {
                    ParakeetCoreMLModel.manifest
                }) {
        self.models = models
        self.store = store
        self.meetingsDirectory = meetingsDirectory
        self.metrics = metrics
        self.storageReserveBytes = max(1_000_000_000, storageReserveBytes)
        self.availableStorageBytes = availableStorageBytes
        self.selectedSpeechModel = selectedSpeechModel
        self.runtimeFactory = runtimeFactory
        let router = TranscriptSinkRouter()
        self.router = router
        normalizedSink = router
    }

    public func prepare(sessionID: UUID) async -> RecordingPreparationResult {
        if let current {
            guard current.id == sessionID, let operation = current.preparation else {
                return .rejected(.captureUnavailable)
            }
            return await operation.value
        }
        // Reserve before any actor suspension; no competing prepare can acquire
        // another lease or replace the active sink during model loading.
        let epoch = LiveTranscriptEpoch(id: sessionID)
        current = epoch
        // Metrics reset after the reserved epoch resolves its verified model,
        // before any consumer starts. Coalesced preparations never reset it.
        let operation = Task { await self.prepare(epoch) }
        epoch.preparation = operation
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private func prepare(_ epoch: LiveTranscriptEpoch) async -> RecordingPreparationResult {
        var stageFailure = RecordingFailure.storageFull
        do {
            try Task.checkCancellation()
            // Installed weights already occupy their volume. Require this much
            // additional free space before acquiring/loading ASR or creating any
            // meeting/OS capture resources. Unknown capacity fails closed.
            guard meetingsDirectory.isFileURL else { throw MeetingStoreError.invalidInput }
            var capacityURL = meetingsDirectory.standardizedFileURL
            while !FileManager.default.fileExists(atPath: capacityURL.path), capacityURL.path != "/" {
                capacityURL.deleteLastPathComponent()
            }
            guard try availableStorageBytes(capacityURL) >= storageReserveBytes else {
                throw LiveRecordingStorageError.insufficientSpace
            }
            stageFailure = .modelUnavailable
            guard let selected = try await selectedSpeechModel(), selected.purpose == .speechRecognition else {
                throw SpeechRecognitionError.invalidModel
            }
            epoch.selectedManifest = selected
            try Task.checkCancellation()
            let lease = try await models.acquire(modelID: selected.modelID)
            epoch.lease = lease
            let model = lease.model
            guard model.manifest == selected, model.manifest.sampleRate == 16_000 else {
                throw SpeechRecognitionError.invalidModel
            }
            metrics?.beginEpoch(modelRevision: selected.revision, runtimeVersion: selected.runtimeVersion)
            let recognizer = try runtimeFactory(model)
            epoch.recognizer = recognizer
            guard recognizer.capabilities.sampleRate == 16_000,
                  recognizer.capabilities.channelCount == 1,
                  recognizer.capabilities.maximumInputSampleCount >= 3_200 else {
                throw SpeechRecognitionError.invalidModel
            }
            try await recognizer.load()
            try Task.checkCancellation()
            try await recognizer.start(epochID: epoch.id)
            try Task.checkCancellation()
            stageFailure = .writeFailed
            guard meetingsDirectory.isFileURL else { throw MeetingStoreError.invalidInput }
            let directory = meetingsDirectory.appendingPathComponent(epoch.id.uuidString, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: directory.path) else {
                throw MeetingStoreError.meetingConflict
            }
            let ingress = try TranscriptIngress(metrics: metrics)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try await store.createMeeting(.init(id: epoch.id, title: "Meeting", createdAt: Date(),
                                                recordingState: .recording))
            epoch.meetingCreated = true
            try await store.saveSpeechModelPin(.init(meetingID: epoch.id,
                selection: .init(manifest: selected, profile: recognizer.profile,
                    installationID: model.installationID)))
            try Task.checkCancellation()
            epoch.ingress = ingress
            epoch.directory = directory
            transcript = .init(sessionID: epoch.id)
            let id = epoch.id
            let token = epoch.token
            let revision = model.manifest.revision
            let store = self.store
            let publish: @Sendable (LiveTranscriptSnapshot) async -> Void = { [weak self] value in
                await self?.publish(value, token: token)
            }
            epoch.consumer = Task.detached(priority: .userInitiated) {
                await Self.consume(ingress, recognizer: recognizer, store: store, id: id,
                                   revision: revision, publish: publish)
            }
            router.install(ingress)
            return .ready(directory: directory)
        } catch {
            if let recognizer = epoch.recognizer { await recognizer.unload() }
            if let lease = epoch.lease {
                do { try await models.release(lease); epoch.lease = nil }
                catch { stageFailure = .modelUnavailable }
            }
            if epoch.meetingCreated {
                try? await store.updateRecordingState(id: epoch.id, state: .failed, capturedSampleCount: 0)
            }
            epoch.preparationFailure = error is CancellationError ? nil : stageFailure
            if current === epoch { current = nil }
            return .rejected(stageFailure)
        }
    }

    public func finish(sessionID: UUID, manifest: AudioCaptureManifest?) async -> RecordingFailure? {
        await finish(sessionID: sessionID, manifest: manifest, disposition: .completed)
    }

    public func finish(sessionID: UUID, manifest: AudioCaptureManifest?,
                       disposition: RecordingFinishDisposition) async -> RecordingFailure? {
        guard let epoch = current else {
            return transcript.sessionID == sessionID ? transcript.failure : nil
        }
        guard epoch.id == sessionID else { return .captureUnavailable }
        if let completion = epoch.completion { return await completion.value }
        let completion = Task { await self.finish(epoch, manifest: manifest, disposition: disposition) }
        epoch.completion = completion
        return await completion.value
    }

    private func finish(_ epoch: LiveTranscriptEpoch, manifest: AudioCaptureManifest?,
                        disposition: RecordingFinishDisposition) async -> RecordingFailure? {
        if let preparation = epoch.preparation { _ = await preparation.value }
        guard let ingress = epoch.ingress, let recognizer = epoch.recognizer,
              let consumer = epoch.consumer else { return epoch.preparationFailure }
        // RecordingSessionOwner calls this only after capture's conversion/file
        // producer has quiesced. Admission additionally joins an already-entered
        // offer before the queue's producer-finished publication.
        router.remove(ingress)
        ingress.admission.close()
        while !ingress.admission.isClosedAndQuiescent {
            try? await Task.sleep(for: .milliseconds(1))
        }
        ingress.queue.finish()
        let drained = await consumer.value
        var failure = drained.snapshot.failure
        let validManifest = manifest?.sessionID == epoch.id && manifest?.schemaVersion == 1 &&
            manifest?.totalFrames == drained.snapshot.receivedSampleCount
        if !validManifest || ingress.failed.load(ordering: .acquiring) {
            failure = failure ?? .captureUnavailable
        }
        await recognizer.unload()
        if let lease = epoch.lease {
            do { try await models.release(lease); epoch.lease = nil }
            catch { failure = failure ?? .modelUnavailable }
        }
        do {
            try await store.updateRecordingState(id: epoch.id,
                state: failure == nil ? (disposition == .interrupted ? .interrupted : .completed) : .failed,
                capturedSampleCount: manifest?.sessionID == epoch.id ? max(0, manifest?.totalFrames ?? 0) : 0)
        } catch { failure = .writeFailed }
        let final = LiveTranscriptSnapshot(sessionID: epoch.id, partial: "",
            finalized: drained.snapshot.finalized,
            receivedSampleCount: drained.snapshot.receivedSampleCount, failure: failure)
        publish(final, token: epoch.token)
        if current === epoch { current = nil }
        return failure
    }

    private func publish(_ value: LiveTranscriptSnapshot, token: UUID) {
        guard current?.token == token else { return }
        if let metrics {
            do {
                if !value.partial.isEmpty, value.partial != transcript.partial {
                    try metrics.partialPublished(endSample: value.receivedSampleCount)
                }
                if value.finalized.count > transcript.finalized.count {
                    for segment in value.finalized.dropFirst(transcript.finalized.count) {
                        try metrics.finalPublished(endSample: segment.endSample)
                    }
                }
                try metrics.checkpoint()
            } catch {
                // Telemetry cannot interrupt otherwise valid capture. Preserve
                // an explicit invalid-evidence counter instead of inventing facts.
                metrics.recordError(.invalidTimestamp)
            }
        }
        transcript = value
    }

    private nonisolated static func consume(_ ingress: TranscriptIngress,
        recognizer: any SpeechModelRuntime, store: SQLiteMeetingStore, id: UUID, revision: String,
        publish: @escaping @Sendable (LiveTranscriptSnapshot) async -> Void) async -> TranscriptDrain {
        var scratch = [Float](repeating: 0, count: 3_200)
        var cursor: Int64 = 0
        var finalized: [StoredTranscriptSegment] = []
        var partial = ""
        var failure: RecordingFailure?
        do {
            var ended = false
            while !ended {
                let next = scratch.withUnsafeMutableBufferPointer { samples in
                    var plane = samples.baseAddress!
                    return withUnsafePointer(to: &plane) {
                        ingress.dequeue(into: $0, frameCapacity: samples.count)
                    }
                }
                switch next {
                case .chunk(let metadata):
                    guard metadata.precedingLoss == nil, metadata.sourceSampleTime == cursor else {
                        throw SpeechRecognitionError.invalidSamples
                    }
                    let started = ingress.metrics?.nowNanoseconds()
                    let update = try await recognizer.accept(Array(scratch.prefix(metadata.frameCount)), at: cursor)
                    guard update.epochID == id else { throw SpeechRecognitionError.noActiveStream }
                    if let metrics = ingress.metrics, let started {
                        do { try metrics.processed(startSample: cursor, frameCount: metadata.frameCount,
                            workStartedAtNanoseconds: started) }
                        catch { metrics.recordError(.invalidTimestamp) }
                    }
                    cursor += Int64(metadata.frameCount)
                    finalized = try await persistFinals(update.finalized, previous: finalized,
                        through: cursor, store: store, id: id, revision: revision)
                    partial = update.partial
                    await publish(.init(sessionID: id, partial: partial, finalized: finalized, receivedSampleCount: cursor))
                case .empty: try await Task.sleep(for: .milliseconds(5))
                case .finished(let loss):
                    guard loss == nil else { throw SpeechRecognitionError.invalidSamples }
                    ended = true
                case .closed: ended = true
                case .tooSmall: throw SpeechRecognitionError.invalidSamples
                }
            }
            guard !ingress.failed.load(ordering: .acquiring) else { throw SpeechRecognitionError.invalidSamples }
            let started = ingress.metrics?.nowNanoseconds()
            let ending = try await recognizer.finish()
            guard ending.epochID == id else { throw SpeechRecognitionError.noActiveStream }
            if let metrics = ingress.metrics, let started {
                do { try metrics.finalizationCompleted(workStartedAtNanoseconds: started) }
                catch { metrics.recordError(.invalidTimestamp) }
            }
            finalized = try await persistFinals(ending.finalized, previous: finalized,
                through: cursor, store: store, id: id, revision: revision)
            partial = ""
        } catch {
            failure = error is MeetingStoreError ? .writeFailed : .captureUnavailable
            ingress.metrics?.recordError(error is MeetingStoreError ? .writeFailed : .inferenceFailed)
            ingress.failed.store(true, ordering: .releasing)
            ingress.admission.close()
            await recognizer.cancel(epochID: id)
        }
        let snapshot = LiveTranscriptSnapshot(sessionID: id, partial: partial, finalized: finalized,
            receivedSampleCount: cursor, failure: failure)
        await publish(snapshot)
        return TranscriptDrain(snapshot: snapshot)
    }

    private nonisolated static func persistFinals(_ delta: [SpeechSegment],
        previous: [StoredTranscriptSegment], through cursor: Int64, store: SQLiteMeetingStore,
        id: UUID, revision: String) async throws -> [StoredTranscriptSegment] {
        guard !delta.isEmpty else { return previous }
        var end = previous.last?.endSample ?? 0
        var ids = Set(previous.map(\.id))
        var rows: [StoredTranscriptSegment] = []
        for source in delta {
            guard source.startSample >= end, source.endSample > source.startSample,
                  source.endSample <= cursor, !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(source.id).inserted else { throw SpeechRecognitionError.invalidSamples }
            rows.append(.init(id: source.id, meetingID: id, sequence: previous.count + rows.count,
                startSample: source.startSample, endSample: source.endSample, text: source.text, modelRevision: revision))
            end = source.endSample
        }
        try await store.appendFinalizedSegments(rows, to: id)
        return previous + rows
    }
}

@MainActor
private final class LiveTranscriptEpoch {
    let id: UUID
    let token = UUID()
    var lease: ModelLease?
    var selectedManifest: ModelManifest?
    var recognizer: (any SpeechModelRuntime)?
    var ingress: TranscriptIngress?
    var directory: URL?
    var meetingCreated = false
    var preparationFailure: RecordingFailure?
    var preparation: Task<RecordingPreparationResult, Never>?
    var consumer: Task<TranscriptDrain, Never>?
    var completion: Task<RecordingFailure?, Never>?
    init(id: UUID) { self.id = id }
}

private struct TranscriptDrain: Sendable { let snapshot: LiveTranscriptSnapshot }
private enum LiveRecordingStorageError: Error { case insufficientSpace }

private final class TranscriptIngress: Sendable {
    let queue: OwnedPCMQueue
    let metrics: TranscriptionMetricsRecorder?
    let admission = CaptureCallbackAdmission()
    let failed = Atomic<Bool>(false)
    // Instrumented queue publication and timing registration share one short
    // worker-only critical section. The consumer cannot observe a chunk before
    // its accepted-input timestamp exists. Native inference is outside this lock.
    private let metricQueueDepth = Mutex<Int>(0)

    init(metrics: TranscriptionMetricsRecorder? = nil) throws {
        self.metrics = metrics
        queue = try OwnedPCMQueue(configuration: .init(capacity: 128, maxFramesPerChunk: 3_200,
                                                     channelCount: 1, sampleRate: 16_000))
    }

    func dequeue(into destination: UnsafePointer<UnsafeMutablePointer<Float>>,
                 frameCapacity: Int) -> PCMDequeueResult {
        guard metrics != nil else { return queue.dequeue(into: destination, frameCapacity: frameCapacity) }
        return metricQueueDepth.withLock { depth in
            let result = queue.dequeue(into: destination, frameCapacity: frameCapacity)
            if case .chunk = result { depth -= 1 }
            return result
        }
    }

    func offer(_ buffer: AVAudioPCMBuffer, at source: Int64) -> Bool {
        switch admission.enter() {
        case .closed: return false
        case .overlapping:
            metrics?.recordError(.captureUnavailable)
            failed.store(true, ordering: .releasing)
            admission.close()
            return false
        case .admitted: break
        }
        defer { _ = admission.leave() }
        let format = buffer.format
        let frameCount = Int(buffer.frameLength)
        let (_, sourceOverflow) = source.addingReportingOverflow(Int64(frameCount))
        // A tap size is only a hint, and resampling can expand its output.
        // Permit a bounded conversion burst (at most21 queue copies), while
        // every owned/native chunk remains <=3,200 frames. No buffer is retained.
        guard source >= 0, format.sampleRate == 16_000, format.channelCount == 1,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              frameCount > 0, frameCount <= 65_536, !sourceOverflow,
              let samples = buffer.floatChannelData?.pointee else {
            metrics?.recordError(.invalidTimestamp)
            failed.store(true, ordering: .releasing)
            admission.close()
            return false
        }
        var offset = 0
        while offset < frameCount {
            let count = min(3_200, frameCount - offset)
            var plane = samples.advanced(by: offset)
            let result = withUnsafePointer(to: &plane) {
                enqueue(channelData: $0, frameCount: count, sourceSampleTime: source + Int64(offset))
            }
            guard result == .accepted else {
                metrics?.recordError(.queueOverflow)
                // Earlier chunks may already have been durably queued. Reject
                // the whole offer explicitly; never report a partial success.
                failed.store(true, ordering: .releasing)
                admission.close()
                return false
            }
            offset += count
        }
        return true
    }

    private func enqueue(channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
                         frameCount: Int, sourceSampleTime: Int64) -> PCMEnqueueResult {
        guard let metrics else {
            return queue.enqueue(channelData: channelData, channelCount: 1, frameCount: frameCount,
                                 sourceSampleTime: sourceSampleTime)
        }
        return metricQueueDepth.withLock { depth in
            let result = queue.enqueue(channelData: channelData, channelCount: 1, frameCount: frameCount,
                                       sourceSampleTime: sourceSampleTime)
            if result == .accepted {
                depth += 1
                do {
                    try metrics.audioQueued(startSample: sourceSampleTime, frameCount: frameCount, queueDepth: depth)
                } catch let error as MetricsValidationError {
                    metrics.recordError(error == .pendingOverflow ? .queueOverflow : .invalidTimestamp)
                } catch { metrics.recordError(.invalidTimestamp) }
            }
            return result
        }
    }
}

// The short mutex protects route selection only on the conversion worker/control
// boundary. It never guards inference or buffer copying, and is not in the tap.
// Each epoch's gate rejects overlap before touching its SPSC producer state.
private final class TranscriptSinkRouter: NormalizedCaptureSink {
    private let selected = Mutex<TranscriptIngress?>(nil)
    func install(_ ingress: TranscriptIngress) { selected.withLock { $0 = ingress } }
    func remove(_ ingress: TranscriptIngress) {
        selected.withLock { if $0 === ingress { $0 = nil } }
    }
    func offer(_ buffer: AVAudioPCMBuffer, sourceStartSample: Int64) -> Bool {
        let ingress = selected.withLock { $0 }
        return ingress?.offer(buffer, at: sourceStartSample) ?? false
    }
}
