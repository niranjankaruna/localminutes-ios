#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// Persistent app services outlive every view. Paths remain stable across an
/// in-place signing refresh; preservation still requires physical verification.
@MainActor @Observable
final class LocalMinutesServices: PlaybackHardware {
    // Test-first composition seams. No working heavy bridge before hosted RED.
    let heavyAdmission: HeavyModelAdmission? = nil
    let recordingAdmission: RecordingHeavyModelAdmission? = nil
    let intelligence: IntelligenceSession? = nil
    let metrics: TranscriptionMetricsRecorder? = nil

    func persistMetricsCheckpoint() throws -> URL { throw MetricsValidationError.notImplemented }
    func exportMetrics() throws -> Data { throw MetricsValidationError.notImplemented }
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

    static let summaryManifest = ModelManifest(
        modelID: "qwen2.5-1.5b-instruct-q4_k_m", purpose: .summary,
        upstreamRepository: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF")!,
        revision: "91cad51170dc346986eccefdc2dd33a9da36ead9",
        licenseIdentifier: "Apache-2.0",
        licenseNotice: "Qwen2.5-1.5B-Instruct by the Qwen team, Alibaba Cloud. Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0. Original model and license: https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF.",
        runtimeVersion: "llama.cpp-b5046",
        artifacts: [.init(role: .summary, fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            byteCount: 1_117_320_736,
            sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/91cad51170dc346986eccefdc2dd33a9da36ead9/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            digestProvenance: .independentlyDownloaded)])

    /// Explicit roots are an internal storage boundary for owned native test
    /// fixtures. Production nil keeps the same persistent ApplicationSupport path.
    init(rootURL: URL? = nil) throws {
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
        let modelRoot = root.appendingPathComponent("Models", isDirectory: true)
        let meetings = root.appendingPathComponent("Meetings", isDirectory: true)
        for directory in [modelRoot, meetings] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PersistentFilePolicy.protectDirectory(directory)
        }
        let transport = HTTPSModelTransport(stagingRootURL: modelRoot.appendingPathComponent(".staging"),
            allowedHosts: ["huggingface.co", "us.aws.cdn.hf.co", "cdn-lfs.huggingface.co",
                           "cdn-lfs-us-1.hf.co", "cas-bridge.xethub.hf.co"])
        let manager = ModelInstallationManager(rootURL: modelRoot,
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) },
            downloader: { artifact, destination in try await transport.download(artifact, to: destination) })
        let database = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        models = manager; store = database; meetingsDirectory = meetings
        live = LiveTranscriptionSession(models: manager, store: database, meetingsDirectory: meetings)
        library = MeetingLibraryController(store: database)
        let usage = MeetingUsageRegistry(requiresStartup: true)
        self.usage = usage
        startup = LibraryStartupCoordinator(store: database, recordingsRoot: meetings, usage: usage)
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

    func refreshModels() async {
        do {
            speechInstalled = try await models.current(modelID: StreamingEnglishModel.manifest.modelID) != nil
            summaryInstalled = try await models.current(modelID: Self.summaryManifest.modelID) != nil
        } catch {
            speechInstalled = false; summaryInstalled = false
            modelError = "An installed model did not pass verification. Download it again before use."
        }
    }

    func download(_ manifest: ModelManifest) {
        guard operation == nil else { return }
        modelError = nil
        operationMessage = manifest.purpose == .speechRecognition ?
            "Downloading and verifying speech model (73 MB)…" :
            "Downloading and verifying summary model (1.12 GB)…"
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
