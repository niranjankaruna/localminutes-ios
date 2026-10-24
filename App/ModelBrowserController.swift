#if os(iOS)
import CryptoKit
import Foundation
import Observation

/// App-retained model work; browsing never starts capture or native inference.
@MainActor @Observable
final class ModelBrowserController {
    var repositoryInput = ""
    var purpose: ModelPurpose = .speechRecognition {
        didSet { if purpose != oldValue { selectedFileName = nil; errorMessage = nil } }
    }
    var selectedFileName: String?
    private(set) var repository: HuggingFaceModelRepository?
    private(set) var installed: [ModelManifest] = []
    private(set) var equippedSpeechID: String?
    private(set) var equippedSummaryID: String?
    private(set) var resources = DeviceModelResources(freeDiskBytes: nil,
        totalMemoryBytes: nil, availableAppMemoryBytes: nil)
    private(set) var isInspecting = false
    private(set) var isWorking = false
    private(set) var isDownloading = false
    private(set) var message: String?
    private(set) var errorMessage: String?
    @ObservationIgnored private weak var services: LocalMinutesServices?
    @ObservationIgnored private let remote = HuggingFaceRepositoryService()
    @ObservationIgnored private var download: Task<Void, Never>?

    init(services: LocalMinutesServices) { self.services = services }

    var compatibility: HuggingFaceCompatibilityAssessment? {
        guard let repository else { return nil }
        let result = repository.assessment(for: purpose, fileName: selectedFileName,
            maximumDownloadBytes: resources.freeDiskBytes ?? Int64.max)
        return ModelRuntimeCompatibility.assess(repository: repository, format: result,
            availableProfiles: [.streamingZipformerONNX, .whisperGGML, .llamaGGUF])
    }
    var resourceAssessment: ModelResourceAssessment? {
        repository?.resourceAssessment(for: purpose, fileName: selectedFileName,
            contextTokens: 4_096, device: resources)
    }
    var canDownload: Bool {
        guard !isWorking, !isInspecting, let assessment = compatibility else { return false }
        let recognized = assessment.status == .supported
        guard recognized, assessment.profile != nil, !assessment.selectedFiles.isEmpty else { return false }
        return resourceAssessment?.status != .insufficientStorage
    }

    func inspect() async {
        guard !isInspecting, !isWorking else { return }
        isInspecting = true; errorMessage = nil; message = nil; selectedFileName = nil
        defer { isInspecting = false }
        do {
            let found = try await remote.inspect(repositoryInput)
            repository = found
            repositoryInput = found.id.rawValue
            if let services { resources = ModelDeviceResourcesReader.current(at: services.meetingsDirectory) }
            message = "Repository details loaded. Choose a file and review its format and estimated resources."
        } catch is CancellationError { message = "Lookup cancelled." }
        catch {
            repository = nil
            errorMessage = Self.describe(error)
        }
    }

    func refresh() async {
        guard let services else { return }
        resources = ModelDeviceResourcesReader.current(at: services.meetingsDirectory)
        do {
            installed = try await services.models.installedManifests()
            equippedSpeechID = try await selectionID(for: .speechRecognition, services: services)
            equippedSummaryID = try await selectionID(for: .summary, services: services)
        } catch { errorMessage = Self.describe(error) }
    }

    private func selectionID(for purpose: ModelPurpose, services: LocalMinutesServices) async throws -> String? {
        if try await services.modelSelections.hasSelectionRecord(for: purpose) {
            return try await services.modelSelections.selected(for: purpose)?.manifest.modelID
        }
        let legacy = purpose == .speechRecognition ? StreamingEnglishModel.manifest : LocalMinutesServices.summaryManifest
        return installed.contains(where: { $0 == legacy }) ? legacy.modelID : nil
    }

    func downloadSelected() {
        guard canDownload, let repository, let assessment = compatibility, let services else { return }
        let manifest: ModelManifest
        do { manifest = try Self.manifest(repository, assessment: assessment, purpose: purpose) }
        catch { errorMessage = Self.describe(error); return }
        guard !installed.contains(where: { $0 == manifest }) else {
            message = "This model is already downloaded. Tap Equip to use it."; return
        }
        isWorking = true; isDownloading = true; errorMessage = nil
        message = "Downloading selected model files, then verifying their size and checksum…"
        download = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await services.models.download(manifest)
                message = "Downloaded and verified. Tap Equip to use this model."
            } catch is CancellationError { message = "Download cancelled. Installed alternatives were preserved." }
            catch { errorMessage = Self.describe(error) }
            isDownloading = false; isWorking = false; download = nil
            await services.refreshModels(); await refresh()
        }
    }

    func cancelDownload() { download?.cancel() }

    func equip(_ manifest: ModelManifest) async {
        guard !isWorking, let services else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            guard let profile = Self.profile(manifest) else { throw ModelSelectionError.unavailableRuntime }
            _ = try await services.modelSelections.select(manifest: manifest, profile: profile, for: manifest.purpose)
            await services.refreshModels(); await refresh()
            message = "Equipped for \(manifest.purpose == .speechRecognition ? "speech" : "summary and Q&A")."
        } catch { errorMessage = Self.describe(error) }
    }

    func remove(_ manifest: ModelManifest) async {
        guard !isWorking, let services else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            if isEquipped(manifest), services.heavyAdmission?.snapshot().phase != .idle {
                throw ModelSelectionError.selectionInUse
            }
            let selected = try await services.modelSelections.selected(for: manifest.purpose)
            if selected?.manifest.modelID == manifest.modelID {
                try await services.modelSelections.removeSelected(for: manifest.purpose)
            } else {
                try await services.models.remove(modelID: manifest.modelID)
                if isEquipped(manifest) { try await services.modelSelections.clear(for: manifest.purpose) }
            }
            await services.refreshModels(); await refresh()
            message = "Model removed. Meetings and notes were preserved."
        } catch { errorMessage = Self.describe(error) }
    }

    func isEquipped(_ manifest: ModelManifest) -> Bool {
        manifest.modelID == (manifest.purpose == .speechRecognition ? equippedSpeechID : equippedSummaryID)
    }

    private static func profile(_ manifest: ModelManifest) -> HuggingFaceRuntimeProfile? {
        switch manifest.runtimeVersion {
        case "whisper.cpp-1.7.5": return .whisperGGML
        case "sherpa-onnx-1.13.8": return .streamingZipformerONNX
        case "llama.cpp-b5046": return .llamaGGUF
        default: return nil
        }
    }

    private static func manifest(_ repository: HuggingFaceModelRepository,
        assessment: HuggingFaceCompatibilityAssessment, purpose: ModelPurpose) throws -> ModelManifest {
        guard let profile = assessment.profile, let license = repository.licenseIdentifier,
              !license.isEmpty, !assessment.selectedFiles.isEmpty else { throw ModelInstallationError.invalidManifest }
        let artifacts = try assessment.selectedFiles.map { file -> ModelArtifact in
            guard let bytes = file.byteCount, let digest = file.sha256, bytes > 0 else {
                throw ModelInstallationError.invalidManifest
            }
            let name = URL(fileURLWithPath: file.fileName).lastPathComponent
            let role: ModelFileRole
            switch profile {
            case .llamaGGUF: role = .summary
            case .whisperGGML: role = .whisper
            case .streamingZipformerONNX:
                if name.hasPrefix("encoder-") { role = .encoder }
                else if name.hasPrefix("decoder-") { role = .decoder }
                else if name.hasPrefix("joiner-") { role = .joiner }
                else if name == "tokens.txt" { role = .tokens }
                else { throw ModelInstallationError.invalidManifest }
            }
            return ModelArtifact(role: role, fileName: name, byteCount: bytes, sha256: digest,
                downloadURL: file.downloadURL, digestProvenance: .upstreamReported)
        }
        let identifier = ModelInstallationIdentity.make(repositoryID: repository.id.rawValue,
            revision: repository.revision, purpose: purpose,
            repositoryRelativeFiles: assessment.selectedFiles.map(\.fileName))
        let upstream = URL(string: "https://huggingface.co/" + repository.id.rawValue)!
        let runtime: String
        switch profile {
        case .llamaGGUF: runtime = "llama.cpp-b5046"
        case .whisperGGML: runtime = "whisper.cpp-1.7.5"
        case .streamingZipformerONNX: runtime = "sherpa-onnx-1.13.8"
        }
        return ModelManifest(modelID: String(identifier), purpose: purpose, upstreamRepository: upstream,
            revision: repository.revision, licenseIdentifier: license,
            licenseNotice: "Publisher: \(repository.id.rawValue). Declared license: \(license). Preserve upstream attribution and terms from the pinned model card: https://huggingface.co/\(repository.id.rawValue)/blob/\(repository.revision)/README.md",
            runtimeVersion: runtime, sampleRate: purpose == .speechRecognition ? 16_000 : nil,
            featureDimension: profile == .streamingZipformerONNX ? 80 : nil, artifacts: artifacts)
    }

    private static func describe(_ error: any Error) -> String {
        if let value = error as? HuggingFaceRepositoryError {
            switch value {
            case .invalidRepository: return "Paste an owner/repository name or a Hugging Face model URL."
            case .httpStatus(let code): return "Hugging Face returned HTTP \(code). Check public access and try again later."
            case .responseTooLarge, .tooManyFiles: return "Repository details exceed this app's safe lookup limits."
            default: return "The repository details could not be verified. Check its public files and pinned model metadata."
            }
        }
        if let value = error as? ModelSelectionError {
            switch value {
            case .selectionInUse: return "Stop recording or local inference before changing equipped models."
            case .unavailableRuntime: return "This model's inference engine is not available in this build."
            default: return "The model did not pass installation or selection checks. Download and equip a verified compatible file."
            }
        }
        return "The model operation failed. Check connection, free storage and whether the model is in use."
    }
}
#endif
