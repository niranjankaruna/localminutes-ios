import AVFoundation
import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
@testable import LocalMinutesTranscription

/// These tests use synthetic bytes and a protocol spy to verify orchestration.
/// They do not make any claim about native ASR quality or model readiness.
@MainActor
final class SpeechModelRuntimeTests: XCTestCase {
    func testDefaultRegistryBuildsParakeetBehindSpeechInterfaceWithoutLoadingWeights() async throws {
        try await fixture { f in
            let runtime: any SpeechModelRuntime = try SpeechModelRuntimeRegistry.makeRuntime(for: f.model)
            XCTAssertTrue(runtime is ParakeetSpeechAdapter)
            XCTAssertEqual(runtime.profile, .parakeetTDTCoreML)
            XCTAssertEqual(runtime.capabilities.sampleRate, 16_000)
            XCTAssertEqual(runtime.capabilities.channelCount, 1)
            let snapshot = await runtime.runtimeSnapshot()
            XCTAssertEqual(snapshot.phase, .unloaded)
            XCTAssertNil(snapshot.modelRevision)
            await runtime.unload()
        }
    }

    func testLiveRecordingUsesInjectedRuntimeAndRetainsLeaseUntilUnload() async throws {
        try await fixture { f in
            let runtime = SpeechRuntimeSpy(revision: f.model.manifest.revision)
            let session = f.live(runtime: runtime)
            let id = UUID()
            let prepared = await session.prepare(sessionID: id)
            guard case .ready(let directory) = prepared else { return XCTFail("Injected runtime must prepare") }
            let pin = try await f.store.speechModelPin(meetingID: id)
            XCTAssertEqual(pin?.selection.manifest, f.model.manifest)
            XCTAssertEqual(pin?.selection.profile, runtime.profile)
            XCTAssertEqual(pin?.selection.installationID, f.model.installationID)
            do { try await f.models.remove(modelID: f.model.manifest.modelID); XCTFail("Active runtime must retain model lease") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
            let manifest = try f.writeAudio(directory: directory, id: id, sink: session.normalizedSink)
            let failure = await session.finish(sessionID: id, manifest: manifest)
            XCTAssertNil(failure)
            let rows = try await f.store.transcript(meetingID: id)
            XCTAssertEqual(rows.map(\.text), [SpeechRuntimeSpy.fixtureText])
            XCTAssertEqual(rows.first?.startSample, 0)
            XCTAssertEqual(rows.first?.endSample, 3_200)
            XCTAssertEqual(rows.first?.modelRevision, f.model.manifest.revision)
            let events = await runtime.events()
            XCTAssertEqual(events, ["load", "start", "accept:0:3200", "finish", "unload"])
            try await f.models.remove(modelID: f.model.manifest.modelID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.model.directoryURL.path))
        }
    }

    func testLoadFailureUnloadsAdapterAndReleasesLeaseBeforeRejectingPreparation() async throws {
        try await fixture { f in
            let runtime = SpeechRuntimeSpy(revision: f.model.manifest.revision, failsLoad: true)
            let session = f.live(runtime: runtime)
            let prepared = await session.prepare(sessionID: UUID())
            XCTAssertEqual(prepared, .rejected(.modelUnavailable))
            let events = await runtime.events()
            XCTAssertEqual(events, ["load", "unload"])
            let meetings = try await f.store.history()
            XCTAssertTrue(meetings.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.recordings.path))
            try await f.models.remove(modelID: f.model.manifest.modelID)
        }
    }

    func testIncompatibleAudioContractIsRejectedAndAdapterIsUnloaded() async throws {
        try await fixture { f in
            let runtime = SpeechRuntimeSpy(revision: f.model.manifest.revision,
                capabilities: .init(sampleRate: 48_000, maximumInputSampleCount: 3_200, producesPartialResults: false))
            let result = await f.live(runtime: runtime).prepare(sessionID: UUID())
            XCTAssertEqual(result, .rejected(.modelUnavailable))
            let events = await runtime.events()
            XCTAssertEqual(events, ["unload"])
            try await f.models.remove(modelID: f.model.manifest.modelID)
        }
    }

    func testRecoveryUsesPinnedInstallationThroughInjectedRuntimeAndReleasesResources() async throws {
        try await fixture { f in
            let id = UUID()
            let directory = f.recordings.appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await f.store.createMeeting(.init(id: id, title: "Protocol recovery fixture", createdAt: Date(), recordingState: .interrupted))
            try await f.store.saveSpeechModelPin(.init(meetingID: id, selection: .init(
                manifest: f.model.manifest, profile: .parakeetTDTCoreML, installationID: f.model.installationID)))
            _ = try f.writeAudio(directory: directory, id: id)
            let runtime = SpeechRuntimeSpy(revision: f.model.manifest.revision)
            let expected = f.model
            let admission = HeavyModelAdmission()
            let replay = MeetingTranscriptionReplayCoordinator(store: f.store, models: f.models,
                recordingsRoot: f.recordings, usage: MeetingUsageRegistry(), admission: admission,
                runtimeFactory: { model in
                    guard model == expected else { throw SpeechRecognitionError.invalidModel }
                    return runtime
                })
            let report = try await replay.replay(meetingID: id)
            XCTAssertEqual(report.replayedFrameCount, 3_200)
            XCTAssertEqual(report.timelineEndSample, 3_200)
            let rows = try await f.store.transcript(meetingID: id)
            XCTAssertEqual(rows.map(\.text), [SpeechRuntimeSpy.fixtureText])
            XCTAssertEqual(rows.first?.modelRevision, expected.manifest.revision)
            let events = await runtime.events()
            XCTAssertEqual(events, ["load", "start", "accept:0:3200", "finish", "unload"])
            XCTAssertEqual(admission.snapshot().phase, .idle)
            // A complete replay is idempotent and does not construct/load a runtime.
            let repeated = try await replay.replay(meetingID: id)
            XCTAssertEqual(repeated.replayedFrameCount, 0)
            let repeatedEvents = await runtime.events()
            XCTAssertEqual(repeatedEvents, events)
            try await f.models.remove(modelID: f.model.manifest.modelID)
        }
    }

    private func fixture(_ body: @MainActor (SpeechRuntimeFixture) async throws -> Void) async throws {
        let f = try await SpeechRuntimeFixture.create()
        do { try await body(f) } catch { await f.remove(); throw error }
        await f.remove()
    }
}

private actor SpeechRuntimeSpy: SpeechModelRuntime {
    static let fixtureText = "Synthetic protocol-wiring transcript."
    nonisolated let profile = HuggingFaceRuntimeProfile.parakeetTDTCoreML
    nonisolated let capabilities: SpeechModelCapabilities
    private let revision: String
    private let failsLoad: Bool
    private var recorded: [String] = []
    private var epochID: UUID?
    private var accepted: Int64 = 0
    private var phase: SpeechRecognitionPhase = .unloaded

    init(revision: String, failsLoad: Bool = false,
         capabilities: SpeechModelCapabilities = .init(maximumInputSampleCount: 3_200, producesPartialResults: false)) {
        self.revision = revision; self.failsLoad = failsLoad; self.capabilities = capabilities
    }
    func load() throws {
        recorded.append("load")
        if failsLoad { throw SpeechRecognitionError.invalidModel }
        phase = .ready
    }
    func start(epochID: UUID) {
        recorded.append("start"); self.epochID = epochID; accepted = 0; phase = .streaming
    }
    func accept(_ samples: [Float], at globalSampleOffset: Int64) throws -> SpeechUpdate {
        guard let epochID, phase == .streaming, globalSampleOffset == accepted else {
            throw SpeechRecognitionError.invalidSamples
        }
        recorded.append("accept:\(globalSampleOffset):\(samples.count)")
        accepted += Int64(samples.count)
        return .init(epochID: epochID, partial: "", finalized: [])
    }
    func finish() throws -> SpeechUpdate {
        guard let epochID else { throw SpeechRecognitionError.noActiveStream }
        recorded.append("finish")
        let finalized: [SpeechSegment] = phase != .finished && accepted > 0
            ? [.init(id: UUID(), startSample: 0, endSample: accepted, text: Self.fixtureText)] : []
        phase = .finished
        return .init(epochID: epochID, partial: "", finalized: finalized)
    }
    func cancel(epochID: UUID) {
        guard self.epochID == epochID else { return }
        recorded.append("cancel"); phase = .cancelled
    }
    func unload() { recorded.append("unload"); phase = .unloaded }
    func runtimeSnapshot() -> SpeechModelSnapshot {
        .init(phase: phase, epochID: epochID, modelRevision: revision, acceptedSampleCount: accepted, bufferedSampleCount: 0)
    }
    func events() -> [String] { recorded }
}

@MainActor
private final class SpeechRuntimeFixture {
    let root: URL, recordings: URL
    let models: ModelInstallationManager
    let model: VerifiedModel
    let store: SQLiteMeetingStore
    private var session: LiveTranscriptionSession?

    private init(root: URL, models: ModelInstallationManager, model: VerifiedModel, store: SQLiteMeetingStore) {
        self.root = root; self.models = models; self.model = model; self.store = store
        recordings = root.appendingPathComponent("Meetings", isDirectory: true)
    }
    static func create() async throws -> SpeechRuntimeFixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-speech-protocol-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        do {
            let revision = String(repeating: "a", count: 40)
            let repository = URL(string: "https://huggingface.co/example/synthetic-speech-protocol")!
            let paths = ["Decoder", "Encoder", "JointDecision", "Preprocessor"].flatMap { bundle in
                ["coremldata.bin", "metadata.json", "model.mil"].map { bundle + ".mlmodelc/" + $0 }
            } + ["parakeet_vocab.json"]
            var artifacts: [ModelArtifact] = []
            for path in paths {
                let bytes = Data("Synthetic protocol fixture; never executable model bytes: \(path)".utf8)
                let url = source.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: url)
                artifacts.append(.init(role: .coreMLAsset, fileName: path, byteCount: Int64(bytes.count),
                    sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                    downloadURL: repository.appendingPathComponent("resolve/\(revision)/\(path)"), digestProvenance: .independentlyDownloaded))
            }
            let manifest = ModelManifest(modelID: "synthetic-speech-protocol", purpose: .speechRecognition,
                upstreamRepository: repository, revision: revision, licenseIdentifier: "CC0-1.0",
                licenseNotice: "Original synthetic test bytes; no inference claim.", runtimeVersion: ParakeetModelPack.runtimeVersion,
                sampleRate: 16_000, featureDimension: 128, artifacts: artifacts,
                parakeetConfiguration: .init(decoderContract: "parakeet-tdt-v2"))
            let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
            let model = try await models.importDirectory(source, manifest: manifest)
            let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
            return .init(root: root, models: models, model: model, store: store)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    func live(runtime: any SpeechModelRuntime) -> LiveTranscriptionSession {
        let expected = model
        let live = LiveTranscriptionSession(models: models, store: store, meetingsDirectory: recordings,
            availableStorageBytes: { _ in .max }, runtimeFactory: { model in
                guard model == expected else { throw SpeechRecognitionError.invalidModel }
                return runtime
            }, selectedSpeechModel: { expected.manifest })
        session = live
        return live
    }
    func writeAudio(directory: URL, id: UUID, sink: (any NormalizedCaptureSink)? = nil) throws -> AudioCaptureManifest {
        let writer = try SegmentCAFWriter(directory: directory, sessionID: id)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3_200))
        buffer.frameLength = 3_200
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for index in 0..<3_200 { samples[index] = 0 }
        try writer.append(buffer)
        if let sink { XCTAssertTrue(sink.offer(buffer, sourceStartSample: 0)) }
        return try writer.finish()
    }
    func remove() async {
        if let session, let id = session.transcript.sessionID { _ = await session.finish(sessionID: id, manifest: nil) }
        try? await store.close()
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-speech-protocol-"), root.resolvingSymlinksInPath() == root else {
            return XCTFail("Refuse cleanup outside owned protocol fixture")
        }
        try? FileManager.default.removeItem(at: root)
    }
}
