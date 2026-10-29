#if os(iOS)
import AVFoundation
import Dispatch
import Foundation
import Observation

private struct AppMetricsClock: MetricsMonotonicClock {
    func nowNanoseconds() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

/// Persistent app services outlive every view. Paths remain stable across an
/// in-place signing refresh; preservation still requires physical verification.
@MainActor @Observable
final class LocalMinutesServices: PlaybackHardware {
    @MainActor private final class IntelligenceControllerReference {
        weak var value: MeetingIntelligenceController?
        init(_ value: MeetingIntelligenceController) { self.value = value }
    }
    @ObservationIgnored private var intelligenceControllers: [UUID: IntelligenceControllerReference] = [:]

    /// A running controller is retained by its operation. Recreated detail views
    /// rejoin it instead of presenting a second idle Summarize button. Weak
    /// references avoid retaining every opened meeting or a services cycle.
    func intelligenceController(for meetingID: UUID) -> MeetingIntelligenceController {
        if let controller = intelligenceControllers[meetingID]?.value { return controller }
        intelligenceControllers = intelligenceControllers.filter { $0.value.value != nil }
        let controller = MeetingIntelligenceController(services: self, meetingID: meetingID)
        intelligenceControllers[meetingID] = IntelligenceControllerReference(controller)
        return controller
    }

    @MainActor private final class DeletionResources: HeavyModelResourceLifecycle {
        var work: Task<Bool, Never>?
        var settled = false
        func requestCancellation() { work?.cancel() }
        func drain() async throws { if let work { _ = await work.value } }
        func unloadAndReleaseModel() async throws {
            guard settled else { throw HeavyModelAdmissionError.cleanupFailed }
        }
    }
    let heavyAdmission: HeavyModelAdmission?
    let recordingAdmission: RecordingHeavyModelAdmission?
    private(set) var intelligence: IntelligenceSession?
    private var intelligenceManifest: ModelManifest?
    @ObservationIgnored private(set) var intelligenceMemoryPressureMonitor: IntelligenceMemoryPressureMonitor?
    let intelligenceBackgroundExecution: IntelligenceBackgroundExecution
    @ObservationIgnored private var summaryStartupBinding: Task<Void, Never>?
    @ObservationIgnored private var summaryStartupBound = false
    let modelSelections: ModelSelectionStore
    @ObservationIgnored lazy var modelBrowser = ModelBrowserController(services: self)
    let metrics: TranscriptionMetricsRecorder?
    let endurance: EnduranceMetricsRecorder?
    let applicationRoot: URL
    let libraryRoot: URL
    let transferFactory: ModelTransferFactory
    let filesImporter: ModelFilesImporter
    let summaryCheckpoints: SummaryCheckpointStore
    let replay: MeetingTranscriptionReplayCoordinator
    let deletion: MeetingDeletionCoordinator
    @ObservationIgnored lazy var archives = LibraryArchiveCoordinator(applicationRoot: applicationRoot,
        currentLibraryRoot: libraryRoot, store: store, usage: usage, admission: heavyAdmission!,
        canMaintain: { [weak self] in
            guard let self else { return false }
            return startup.state == .ready && !modelBrowser.isWorking
                && playback == nil && !ownsPlaybackSession && recoveringMeetingID == nil
        })
    private(set) var maintainingLibrary = false
    private(set) var recoveringMeetingID: UUID?
    private(set) var libraryMessage: String?
    private let diagnosticsDirectory: URL
    @ObservationIgnored private var metricsSampler: Task<Void, Never>?
    @ObservationIgnored private var metricsVisibility: MetricsVisibility = .unknown
    @ObservationIgnored private var recoveryWork: Task<Void, Never>?
    @ObservationIgnored private var deletionWork: [UUID: Task<Bool, Never>] = [:]

    func sampleEndurance(visibility: MetricsVisibility) throws {
        metricsVisibility = visibility
        try endurance?.sample(NativeEnduranceFacts.current(visibility: visibility))
    }
    func beginEnduranceEpoch() {
        metricsSampler?.cancel()
        // Owner preparation precedes the model's async pin binding. Clear the
        // previous PCM epoch synchronously before any retained sampler can run.
        metrics?.beginEpoch()
        endurance?.beginEpoch()
        metricsSampler = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try sampleEndurance(visibility: metricsVisibility)
                    _ = try persistMetricsCheckpoint()
                    try await Task.sleep(for: .seconds(10))
                } catch is CancellationError { return }
                catch { metrics?.recordError(.writeFailed) }
                // Storage/sensor errors must not create a tight retry loop.
                if !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }
    func endEnduranceEpoch() {
        metricsSampler?.cancel(); metricsSampler = nil
        do { try sampleEndurance(visibility: metricsVisibility); _ = try persistMetricsCheckpoint() }
        catch { metrics?.recordError(.writeFailed) }
    }

    func persistMetricsCheckpoint() throws -> URL {
        guard let metrics else { throw MetricsValidationError.invalidIdentity }
        let bytes = try MetricsExportCodec.encode(metrics.snapshot())
        let destination = diagnosticsDirectory.appendingPathComponent("transcription-metrics.json")
        try PersistentFilePolicy.writeAtomically(bytes, to: destination, within: diagnosticsDirectory)
        if let endurance {
            try PersistentFilePolicy.writeAtomically(EnduranceMetricsExportCodec.encode(endurance.snapshot()),
                to: diagnosticsDirectory.appendingPathComponent("endurance-metrics.json"), within: diagnosticsDirectory)
        }
        return destination
    }
    func exportMetrics() throws -> Data {
        let file = try persistMetricsCheckpoint()
        let bytes = try Data(contentsOf: file)
        _ = try MetricsExportCodec.decodeValidated(bytes)
        return bytes
    }
    func exportEnduranceMetrics() throws -> Data {
        guard let endurance else { throw MetricsValidationError.invalidIdentity }
        let bytes = try EnduranceMetricsExportCodec.encode(endurance.snapshot())
        _ = try EnduranceMetricsExportCodec.decodeValidated(bytes)
        return bytes
    }
    let models: ModelInstallationManager
    let store: SQLiteMeetingStore
    let live: LiveTranscriptionSession
    let library: MeetingLibraryController
    let meetingsDirectory: URL
    let usage: MeetingUsageRegistry
    let startup: LibraryStartupCoordinator
    private(set) var speechInstalled = false
    private(set) var summaryInstalled = false
    private(set) var startupMessage: String?
    private(set) var modelError: String?
    private(set) var playback: AVAudioPlayer?
    @ObservationIgnored private var ownsPlaybackSession = false

    static let summaryManifest = ModelCatalog.variant(id: "phi3-mini-4k-instruct-q4")?.manifest
        ?? legacySummaryManifest

    private static let legacySummaryManifest = ModelManifest(
        modelID: "phi3-mini-4k-instruct-q4", purpose: .summary,
        upstreamRepository: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf")!,
        revision: "a64113399c2f6b8ad3e11c394733a2ddadaa7f33",
        licenseIdentifier: "MIT",
        licenseNotice: "Phi-3-mini-4k-instruct by Microsoft. MIT license and attribution: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/blob/a64113399c2f6b8ad3e11c394733a2ddadaa7f33/LICENSE. Model card: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/blob/a64113399c2f6b8ad3e11c394733a2ddadaa7f33/README.md.",
        runtimeVersion: "llama.cpp-b5046",
        artifacts: [.init(role: .summary, fileName: "Phi-3-mini-4k-instruct-q4.gguf",
            byteCount: 2_393_231_072,
            sha256: "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef",
            downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/a64113399c2f6b8ad3e11c394733a2ddadaa7f33/Phi-3-mini-4k-instruct-q4.gguf")!,
            digestProvenance: .independentlyDownloaded)])

    /// Explicit roots are an internal storage boundary for owned native test
    /// fixtures. Production nil keeps the same persistent ApplicationSupport path.
    init(rootURL: URL? = nil, modelConfiguration: URLSessionConfiguration = .ephemeral,
         backgroundProvider: (any IntelligenceBackgroundProviding)? = nil) throws {
        intelligenceBackgroundExecution = IntelligenceBackgroundExecution(
            provider: backgroundProvider ?? SystemIntelligenceBackgroundProvider())
        let root: URL
        if let rootURL {
            guard rootURL.isFileURL else { throw PersistentFilePolicyError.invalidRoot }
            root = rootURL.standardizedFileURL
        } else {
            root = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalMinutes", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PersistentFilePolicy.protectDirectory(root)
        let activeLibrary = try LibraryArchiveCoordinator.activeLibraryRoot(at: root)
        applicationRoot = root; libraryRoot = activeLibrary
        let modelRoot = root.appendingPathComponent("Models", isDirectory: true)
        let meetings = activeLibrary.appendingPathComponent("Meetings", isDirectory: true)
        let diagnostics = root.appendingPathComponent("Diagnostics", isDirectory: true)
        for directory in [modelRoot, meetings, diagnostics] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PersistentFilePolicy.protectDirectory(directory)
        }
        let factory = ModelTransferFactory(appRootURL: root, configuration: modelConfiguration)
        transferFactory = factory
        let manager = factory.makeManager()
        filesImporter = ModelFilesImporter(manager: manager, stagingRootURL: root.appendingPathComponent("ModelImports", isDirectory: true))
        let database = try SQLiteMeetingStore(databaseURL: activeLibrary.appendingPathComponent("meetings.sqlite"))
        let checkpoints = try SummaryCheckpointStore(directoryURL: activeLibrary.appendingPathComponent("SummaryCheckpoints", isDirectory: true))
        summaryCheckpoints = checkpoints
        guard let source = Bundle.main.object(forInfoDictionaryKey: "LocalMinutesSourceCommit") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let number = Int(build) else { throw MetricsValidationError.invalidIdentity }
        let metrics = try TranscriptionMetricsRecorder(identity: .init(sourceCommit: source,
            modelRevision: ParakeetCoreMLModel.manifest.revision,
            runtimeVersion: ParakeetCoreMLModel.manifest.runtimeVersion, buildNumber: number),
            clock: AppMetricsClock())
        self.metrics = metrics; diagnosticsDirectory = diagnostics
        endurance = try EnduranceMetricsRecorder(transcription: metrics, clock: AppMetricsClock())
        let admission = HeavyModelAdmission()
        let selections = ModelSelectionStore(rootURL: root.appendingPathComponent("ModelSelections", isDirectory: true),
            models: manager, availableProfiles: ModelRuntimeContracts.availableProfiles,
            canChangeSelection: { admission.snapshot().phase == .idle })
        modelSelections = selections
        models = manager; store = database; meetingsDirectory = meetings
        live = LiveTranscriptionSession(models: manager, store: database, meetingsDirectory: meetings, metrics: metrics,
            selectedSpeechModel: {
                if try await selections.hasSelectionRecord(for: .speechRecognition) {
                    return try await selections.resolve(for: .speechRecognition)?.manifest
                }
                return ParakeetCoreMLModel.manifest
            })
        library = MeetingLibraryController(store: database)
        let usage = MeetingUsageRegistry(requiresStartup: true)
        self.usage = usage
        let checkpointRoot = activeLibrary.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
        startup = LibraryStartupCoordinator(store: database, recordingsRoot: meetings, usage: usage,
            summaryCheckpointRoot: checkpointRoot)
        deletion = MeetingDeletionCoordinator(store: database, recordingsRoot: meetings, usage: usage,
            summaryCheckpointRoot: checkpointRoot)
        replay = MeetingTranscriptionReplayCoordinator(store: database, models: manager, recordingsRoot: meetings,
            usage: usage, admission: admission)
        heavyAdmission = admission
        recordingAdmission = RecordingHeavyModelAdmission(usageRegistry: usage, heavyAdmission: admission)
        intelligence = IntelligenceSession(store: database, models: manager, admission: admission,
            manifest: Self.summaryManifest, summaryCheckpoints: checkpoints)
        intelligenceManifest = Self.summaryManifest
        intelligenceMemoryPressureMonitor = IntelligenceMemoryPressureMonitor(activeSession: { [weak self] in
            self?.intelligence
        })
    }

    /// The retained coordinator coalesces callers and finishes admitted recovery
    /// even when a requesting view or intent is cancelled. A later explicit
    /// Start can retry failure; ready reports are reused without another replay.
    func initialize() async {
        do {
            let report = try await startup.run()
            guard startup.state == .ready else { return }
            await restoreSummarySelectionForStartup()
            startupMessage = report.issues.isEmpty ? nil : "Some saved meetings need recovery review."
        } catch {
            // A waiter from a failed attempt must not overwrite a newer retry's
            // running/ready projection. No paths or raw database errors escape.
            guard startup.state == .failed else { return }
            startupMessage = "Saved meetings could not be prepared. Recording is paused. Reopen LocalMinutes and try again."
        }
    }

    /// Join one verification/binding operation per service lifetime. Constructing
    /// a session retains only its manifest; no model runtime is loaded here.
    /// A busy admission leaves restoration retryable, never a usable default.
    private func restoreSummarySelectionForStartup() async {
        guard !summaryStartupBound else { return }
        if let binding = summaryStartupBinding {
            await binding.value
            return
        }
        let binding = Task { @MainActor in
            guard self.heavyAdmission?.snapshot().phase == .idle else {
                self.intelligence = nil
                self.intelligenceManifest = nil
                return
            }
            do {
                let chosen: ModelManifest?
                if try await self.modelSelections.hasSelectionRecord(for: .summary) {
                    chosen = try await self.modelSelections.resolve(for: .summary)?.manifest
                    self.summaryInstalled = chosen != nil
                } else {
                    // Missing legacy weights remain a truthful model-required
                    // result when generation acquires this default manifest.
                    if let existing = try await self.models.current(modelID: Self.summaryManifest.modelID),
                       ModelCatalog.matchesSourceWeights(existing.manifest, Self.summaryManifest) {
                        chosen = existing.manifest
                    } else {
                        chosen = Self.summaryManifest
                    }
                }
                guard self.heavyAdmission?.snapshot().phase == .idle else {
                    self.intelligence = nil
                    self.intelligenceManifest = nil
                    return
                }
                if let chosen, let admission = self.heavyAdmission {
                    self.intelligence = IntelligenceSession(store: self.store, models: self.models,
                        admission: admission, manifest: chosen, summaryCheckpoints: self.summaryCheckpoints)
                } else {
                    self.intelligence = nil
                }
                self.intelligenceManifest = chosen
                self.summaryStartupBound = true
            } catch {
                self.intelligence = nil
                self.intelligenceManifest = nil
                self.summaryInstalled = false
                self.modelError = "An installed model did not pass verification. Download it again before use."
                self.summaryStartupBound = true
            }
        }
        summaryStartupBinding = binding
        await binding.value
        summaryStartupBinding = nil
    }

    func deleteMeeting(id: UUID) async -> Bool {
        if let work = deletionWork[id] { return await work.value }
        guard !maintainingLibrary, playback == nil, !ownsPlaybackSession,
              recoveringMeetingID != id, heavyAdmission?.snapshot().phase == .idle else {
            libraryMessage = "Stop recording, playback or local processing before deleting this meeting."
            return false
        }
        guard let admission = heavyAdmission else { return false }
        let resources = DeletionResources()
        let lease: HeavyModelUseLease
        do { lease = try admission.acquire(purpose: .libraryMaintenance, requestID: id, resource: resources) }
        catch { libraryMessage = "Local processing is still in use. Try deleting again after it finishes."; return false }
        let work = Task { @MainActor in
            await self.initialize()
            guard self.startup.state == .ready else { return false }
            do {
                try await self.deletion.delete(meetingID: id)
                if self.library.selected?.id == id { await self.library.open(id: id); await self.library.search("") }
                await self.library.refresh()
                self.libraryMessage = "Meeting and its audio, transcript, notes, summaries and answers deleted."
                return true
            } catch {
                self.libraryMessage = "The meeting could not be fully deleted. Stop any use of it and try again; unfinished deletion is retained for recovery."
                return false
            }
        }
        resources.work = work
        // Cleanup joins the worker from a separate retained task. The heavy
        // gate excludes new generation until SQL and private cache cleanup end.
        let completion = Task { @MainActor in
            defer { self.deletionWork[id] = nil }
            let result = await work.value
            resources.settled = true
            do { try await admission.cancelAndDrain(lease); return result }
            catch { self.libraryMessage = "Deletion cleanup is still pending. Keep the app open and retry."; return false }
        }
        deletionWork[id] = completion
        return await completion.value
    }

    func resumeTranscript(meetingID: UUID) {
        guard recoveryWork == nil, !maintainingLibrary, playback == nil,
              heavyAdmission?.snapshot().phase == .idle else {
            libraryMessage = "Stop recording, playback or generation before resuming a transcript."; return
        }
        recoveringMeetingID = meetingID
        recoveryWork = Task { @MainActor in
            defer { self.recoveryWork = nil; self.recoveringMeetingID = nil }
            await self.initialize()
            guard self.startup.state == .ready else { return }
            do {
                let result = try await self.replay.replay(meetingID: meetingID)
                self.libraryMessage = "Transcript recovery finished. \(result.insertedSegmentIDs.count) new segments saved."
            } catch is CancellationError { self.libraryMessage = "Recovery paused. Saved progress can be resumed." }
            catch TranscriptionReplayError.modelUnavailable {
                self.libraryMessage = "Recovery needs this meeting's original speech model installation. An unrecorded legacy model cannot be guessed from today's selection."
            } catch { self.libraryMessage = "The saved audio or recovery checkpoint needs review. Original audio and text were preserved." }
            await self.library.refresh()
        }
    }
    func cancelTranscriptRecovery() { recoveryWork?.cancel() }
    func cancelTranscriptRecoveryAndDrain() async {
        guard let work = recoveryWork else { return }
        work.cancel(); await work.value
    }

    func beginLibraryMaintenance() throws {
        guard !maintainingLibrary, deletionWork.isEmpty else { throw LibraryArchiveCoordinatorError.busy }
        maintainingLibrary = true
    }
    func endLibraryMaintenance() { maintainingLibrary = false }

    /// Read-only diagnostics must not overlap work which can mutate the owned
    /// tree or retain the shared audio session after its player has stopped.
    var canPrepareStoragePrivacyReport: Bool {
        startup.state == .ready && !maintainingLibrary && deletionWork.isEmpty
            && !modelBrowser.isWorking
            && playback == nil && !ownsPlaybackSession && recoveringMeetingID == nil
    }

    func exportBackup() async throws -> URL {
        await initialize()
        try beginLibraryMaintenance(); defer { endLibraryMaintenance() }
        let parent = applicationRoot.appendingPathComponent("Exports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        }
        try PersistentFilePolicy.protectDirectory(parent)
        let output = parent.appendingPathComponent(UUID().uuidString + ".localminutesbackup", isDirectory: true)
        _ = try await archives.export(to: output)
        return output
    }

    func refreshModels() async {
        do {
            if try await modelSelections.hasSelectionRecord(for: .speechRecognition) {
                speechInstalled = try await modelSelections.resolve(for: .speechRecognition) != nil
            } else {
                speechInstalled = try await models.current(modelID: ParakeetCoreMLModel.manifest.modelID) != nil
            }
            let chosen: ModelManifest?
            if try await modelSelections.hasSelectionRecord(for: .summary) {
                chosen = try await modelSelections.resolve(for: .summary)?.manifest
            } else {
                chosen = try await models.current(modelID: Self.summaryManifest.modelID)?.manifest
            }
            summaryInstalled = chosen != nil
            if heavyAdmission?.snapshot().phase == .idle, intelligenceManifest != chosen {
                if let chosen, let admission = heavyAdmission {
                    intelligence = IntelligenceSession(store: store, models: models, admission: admission,
                        manifest: chosen, summaryCheckpoints: summaryCheckpoints)
                } else { intelligence = nil }
                intelligenceManifest = chosen
            }
        } catch {
            speechInstalled = false; summaryInstalled = false
            modelError = "An installed model did not pass verification. Download it again before use."
        }
    }

    func startPlayback(at location: MeetingPlaybackLocation) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        ownsPlaybackSession = true
        try session.setActive(true)
        let audio = try AVAudioPlayer(contentsOf: location.fileURL)
        audio.currentTime = Double(location.frameOffset) / 16_000
        guard audio.prepareToPlay(), audio.play() else { throw MeetingPlaybackError.unreadableAudio }
        playback = audio
    }

    func stopPlayback() throws {
        playback?.stop()
        playback = nil
        if ownsPlaybackSession {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsPlaybackSession = false
        }
    }

}
#endif
