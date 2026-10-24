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
    let heavyAdmission: HeavyModelAdmission?
    let recordingAdmission: RecordingHeavyModelAdmission?
    private(set) var intelligence: IntelligenceSession?
    private var intelligenceManifest: ModelManifest?
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
            return startup.state == .ready && !isChangingModels && !modelBrowser.isWorking
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
        metricsSampler?.cancel(); endurance?.beginEpoch()
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
    private(set) var operationMessage: String?
    private(set) var startupMessage: String?
    private(set) var modelError: String?
    private(set) var playback: AVAudioPlayer?
    @ObservationIgnored private var ownsPlaybackSession = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var intelligenceCleanup: (id: UUID, task: Task<Void, Never>)?

    static let summaryManifest = ModelManifest(
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
    init(rootURL: URL? = nil, modelConfiguration: URLSessionConfiguration = .ephemeral) throws {
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
            modelRevision: StreamingEnglishModel.manifest.revision,
            runtimeVersion: StreamingEnglishModel.manifest.runtimeVersion, buildNumber: number),
            clock: AppMetricsClock())
        self.metrics = metrics; diagnosticsDirectory = diagnostics
        endurance = try EnduranceMetricsRecorder(transcription: metrics, clock: AppMetricsClock())
        let admission = HeavyModelAdmission()
        let selections = ModelSelectionStore(rootURL: root.appendingPathComponent("ModelSelections", isDirectory: true),
            models: manager, availableProfiles: [.streamingZipformerONNX, .whisperGGML, .llamaGGUF],
            canChangeSelection: { admission.snapshot().phase == .idle })
        modelSelections = selections
        models = manager; store = database; meetingsDirectory = meetings
        live = LiveTranscriptionSession(models: manager, store: database, meetingsDirectory: meetings, metrics: metrics,
            selectedSpeechModel: {
                if try await selections.hasSelectionRecord(for: .speechRecognition) {
                    return try await selections.resolve(for: .speechRecognition)?.manifest
                }
                return StreamingEnglishModel.manifest
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
            usage: usage, admission: admission, modelPolicy: .capturedPinRequired)
        heavyAdmission = admission
        recordingAdmission = RecordingHeavyModelAdmission(usageRegistry: usage, heavyAdmission: admission)
        intelligence = IntelligenceSession(store: database, models: manager, admission: admission,
            manifest: Self.summaryManifest, summaryCheckpoints: checkpoints)
        intelligenceManifest = Self.summaryManifest
    }

    /// Retain cancellation independently of the scene/view that requested it.
    /// The captured request identity can never cancel a later meeting's work.
    func cancelCurrentIntelligence() {
        guard let intelligence else { return }
        let snapshot = intelligence.snapshot()
        guard let id = snapshot.requestID,
              [.loading, .generating, .saving, .draining, .failed].contains(snapshot.phase),
              intelligenceCleanup?.id != id else { return }
        let task = Task { @MainActor [weak self] in
            do { try await intelligence.cancelAndDrain(requestID: id) }
            catch IntelligenceSessionError.staleRequest { }
            catch { self?.modelError = "Local model cleanup is pending. Return to the meeting and tap Cancel to retry." }
            if self?.intelligenceCleanup?.id == id { self?.intelligenceCleanup = nil }
        }
        intelligenceCleanup = (id, task)
    }

    /// The retained coordinator coalesces callers and finishes admitted recovery
    /// even when a requesting view or intent is cancelled. A later explicit
    /// Start can retry failure; ready reports are reused without another replay.
    func initialize() async {
        do {
            let report = try await startup.run()
            guard startup.state == .ready else { return }
            startupMessage = report.issues.isEmpty ? nil : "Some saved meetings need recovery review."
        } catch {
            // A waiter from a failed attempt must not overwrite a newer retry's
            // running/ready projection. No paths or raw database errors escape.
            guard startup.state == .failed else { return }
            startupMessage = "Saved meetings could not be prepared. Recording is paused. Reopen LocalMinutes and try again."
        }
    }

    var isChangingModels: Bool { operation != nil }

    func deleteMeeting(id: UUID) async -> Bool {
        if let work = deletionWork[id] { return await work.value }
        guard !maintainingLibrary, playback == nil, !ownsPlaybackSession,
              recoveringMeetingID != id, heavyAdmission?.snapshot().phase == .idle else {
            libraryMessage = "Stop recording, playback or local processing before deleting this meeting."
            return false
        }
        let work = Task { @MainActor in
            defer { self.deletionWork[id] = nil }
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
        deletionWork[id] = work
        return await work.value
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
                speechInstalled = try await models.current(modelID: StreamingEnglishModel.manifest.modelID) != nil
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

    func download(_ manifest: ModelManifest) {
        guard operation == nil else { return }
        modelError = nil
        operationMessage = manifest.purpose == .speechRecognition ?
            "Downloading and verifying speech model…" :
            "Downloading and verifying summary model…"
        operation = Task {
            do { _ = try await models.download(manifest) }
            catch is CancellationError { modelError = "Download cancelled. The previous model was preserved." }
            catch { modelError = "The model could not be installed. Check connection and free storage, then try again." }
            await refreshModels()
            operationMessage = nil
            operation = nil
        }
    }

    func cancelDownload() { operation?.cancel() }

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

    func remove(_ manifest: ModelManifest) async {
        guard operation == nil else { return }
        do { try await models.remove(modelID: manifest.modelID); modelError = nil }
        catch { modelError = "This model is in use or could not be removed. Stop recording and try again." }
        await refreshModels()
    }
}
#endif
