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
    private(set) var isImporting = false
    private(set) var isPreparingStorageCheck = false
    private(set) var storageCheckReport: StoragePrivacyReport?
    private(set) var storageCheckJSON: String?
    private(set) var storageCheckError: String?
    private(set) var message: String?
    private(set) var errorMessage: String?
    private(set) var downloadProgress: ModelTransferProgress?
    private(set) var usingPackDescriptor = false
    var appleAvailability: AppleSummaryAvailability { AppleFoundationRuntime.availability() }
    var appleEquipped: Bool { equippedSummaryID == AppleSummaryModel.identifier }
    func updateDownloadProgress(_ value: ModelTransferProgress) { downloadProgress = value }
    @ObservationIgnored private weak var services: LocalMinutesServices?
    @ObservationIgnored private let remote = HuggingFaceRepositoryService()
    @ObservationIgnored private var download: Task<Void, Never>?

    init(services: LocalMinutesServices) { self.services = services }

    func prepareStorageCheck(recordingOwner: RecordingSessionOwner?) async {
        guard !isPreparingStorageCheck else { return }
        storageCheckReport = nil; storageCheckJSON = nil; storageCheckError = nil
        guard !isWorking, !isInspecting else {
            storageCheckError = "Finish model changes before preparing the storage check."
            return
        }
        guard let services, let recordingOwner else {
            storageCheckError = "Storage check is unavailable until the app is ready."
            return
        }
        isPreparingStorageCheck = true
        defer { isPreparingStorageCheck = false }
        do {
            let recording = await recordingOwner.snapshot()
            try Task.checkCancellation()
            let bytes = try await services.exportStoragePrivacyReport(recording: recording)
            try Task.checkCancellation()
            let report = try JSONDecoder().decode(StoragePrivacyReport.self, from: bytes)
            guard let text = String(data: bytes, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            storageCheckReport = report
            storageCheckJSON = text
        } catch StoragePrivacyReportError.recordingActive {
            storageCheckError = "Stop recording and wait for cleanup before preparing the storage check."
        } catch StoragePrivacyReportError.busy {
            storageCheckError = "Finish playback, local processing or library changes before preparing the storage check."
        } catch StoragePrivacyReportError.notReady {
            storageCheckError = "Storage check is unavailable until the app is ready."
        } catch StoragePrivacyReportError.invalidBuildIdentity {
            storageCheckError = "Build information could not be verified for this storage check."
        } catch is CancellationError {
            storageCheckError = "Storage check cancelled."
        } catch {
            storageCheckError = "The storage check could not be prepared. Try again when the app is idle."
        }
    }

    var compatibility: HuggingFaceCompatibilityAssessment? {
        guard let repository else { return nil }
        let result = repository.assessment(for: purpose, fileName: selectedFileName,
            maximumDownloadBytes: resources.freeDiskBytes ?? Int64.max)
        return ModelRuntimeCompatibility.assess(repository: repository, format: result,
            availableProfiles: [.llamaGGUF, .parakeetTDTCoreML])
    }
    var resourceAssessment: ModelResourceAssessment? {
        repository?.resourceAssessment(for: purpose, fileName: selectedFileName,
            contextTokens: 4_096, device: resources)
    }
    var canDownload: Bool {
        guard !isWorking, !isInspecting, !isPreparingStorageCheck, let assessment = compatibility else { return false }
        let recognized = assessment.status == .supported
        guard recognized, assessment.profile != nil, !assessment.selectedFiles.isEmpty else { return false }
        return resourceAssessment?.status != .insufficientStorage
    }

    func inspect() async {
        guard !isInspecting, !isWorking, !isPreparingStorageCheck else { return }
        isInspecting = true; errorMessage = nil; message = nil; selectedFileName = nil
        defer { isInspecting = false }
        do {
            let found = try await remote.inspect(repositoryInput)
            var enriched = found
            for pack in BundledParakeetPacks.manifests where
                pack.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == found.id.rawValue.lowercased()
                    && pack.revision == found.revision {
                enriched.parakeetManifest = pack
            }
            repository = enriched; usingPackDescriptor = false
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
        if purpose == .summary, try services.modelSelections.isAppleIntelligenceSelected() {
            return AppleSummaryModel.identifier
        }
        if try await services.modelSelections.hasSelectionRecord(for: purpose) {
            return try await services.modelSelections.selected(for: purpose)?.manifest.modelID
        }
        let legacy = purpose == .speechRecognition ? ParakeetCoreMLModel.manifest : LocalMinutesServices.summaryManifest
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
        downloadProgress = nil
        message = "Downloading selected model files, then verifying their size and checksum…"
        download = Task { [weak self] in
            guard let self else { return }
            let updates = AsyncStream<ModelTransferProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let consumer = Task { @MainActor [weak self] in
                for await event in updates.stream { self?.updateDownloadProgress(event) }
            }
            do {
                _ = try await services.models.download(manifest, progress: { event in
                    _ = updates.continuation.yield(event)
                })
                message = "Downloaded and verified. Tap Equip to use this model."
            } catch is CancellationError { message = "Download paused. Choose the same file and tap Download to resume its verified saved prefix." }
            catch { errorMessage = Self.describe(error) }
            updates.continuation.finish()
            await consumer.value
            isDownloading = false; isWorking = false; download = nil
            await services.refreshModels(); await refresh()
        }
    }

    func cancelDownload() { download?.cancel() }

    func equipAppleIntelligence() async {
        guard !isWorking, let services else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            try await services.modelSelections.selectAppleIntelligence(available: appleAvailability == .available)
            await services.refreshModels(); await refresh()
            message = "Apple Intelligence selected for on-device summaries and questions."
        } catch { errorMessage = Self.describe(error) }
    }

    func loadParakeetPack(_ manifest: ModelManifest) throws {
        guard !isWorking, !isInspecting, !isPreparingStorageCheck else { throw ModelSelectionError.selectionInUse }
        _ = try ParakeetModelPack.configuration(for: manifest)
        let id = try HuggingFaceRepositoryID(input: manifest.upstreamRepository.absoluteString)
        var descriptor = HuggingFaceModelRepository(id: id, revision: manifest.revision,
            files: manifest.artifacts.map { .init(fileName: $0.fileName, byteCount: $0.byteCount,
                sha256: $0.sha256, downloadURL: $0.downloadURL) },
            licenseIdentifier: manifest.licenseIdentifier, cardMarkdown: nil,
            pipelineTag: "automatic-speech-recognition", libraryName: "coreml", modelType: "parakeet_tdt",
            architectures: ["FastConformerTDT"], isGated: false, contextConfiguration: nil)
        descriptor.parakeetManifest = manifest
        purpose = .speechRecognition; repository = descriptor; repositoryInput = id.rawValue
        usingPackDescriptor = true; selectedFileName = nil; errorMessage = nil
        message = "Model pack descriptor loaded. Review its source, license and files before downloading or importing weights."
    }

    func loadBundledParakeetV3() {
        do {
            guard let manifest = BundledParakeetPacks.manifests.first else { throw ParakeetModelPackError.invalidManifest }
            try loadParakeetPack(manifest)
        } catch { errorMessage = Self.describe(error) }
    }

    #if DEBUG
    func loadScreenshotModelCard() throws {
        guard AppScreenshotFixture.requested,
              let manifest = BundledParakeetPacks.manifests.first else { throw ParakeetModelPackError.invalidManifest }
        try loadParakeetPack(manifest)
        guard let descriptor = repository else { throw ParakeetModelPackError.invalidManifest }
        var fixture = HuggingFaceModelRepository(id: descriptor.id, revision: descriptor.revision,
            files: descriptor.files, licenseIdentifier: descriptor.licenseIdentifier,
            cardMarkdown: "# Parakeet TDT Core ML\n\nSample model card for UI review.\n\nSpeech recognition runs on this iPhone after downloading and equipping the complete model pack.",
            pipelineTag: descriptor.pipelineTag, libraryName: descriptor.libraryName,
            modelType: descriptor.modelType, architectures: descriptor.architectures,
            isGated: false, contextConfiguration: descriptor.contextConfiguration)
        fixture.parakeetManifest = manifest
        repository = fixture
    }
    #endif

    func importParakeetPack(_ url: URL) {
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, (1...65_536).contains(size) else { throw ParakeetModelPackError.invalidManifest }
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let data = try input.read(upToCount: 65_537) ?? Data()
            guard data.count == size else { throw ParakeetModelPackError.invalidManifest }
            try loadParakeetPack(ParakeetModelPack.decode(data))
        } catch { errorMessage = Self.describe(error) }
    }

    func selectedImportManifest() -> ModelManifest? {
        guard !isWorking, !isPreparingStorageCheck, let repository else { return nil }
        let format = repository.assessment(for: purpose, fileName: selectedFileName, maximumDownloadBytes: .max)
        let assessment = ModelRuntimeCompatibility.assess(repository: repository, format: format,
            availableProfiles: [.llamaGGUF, .parakeetTDTCoreML])
        guard assessment.status == .supported else { return nil }
        return try? Self.manifest(repository, assessment: assessment, purpose: purpose)
    }

    func discardSelectedDownload() {
        guard let manifest = selectedImportManifest(), let services else { return }
        do {
            try services.transferFactory.discardProgress(for: manifest)
            message = "Unfinished download removed. Installed models remain available."
        } catch { errorMessage = "This download is still in use or its files could not be safely removed. Pause it and try again." }
    }

    func importSelectedFiles(_ files: [URL], manifest: ModelManifest) {
        guard !isWorking, !isPreparingStorageCheck, let services, !services.maintainingLibrary else { return }
        isWorking = true; isImporting = true; errorMessage = nil
        message = "Reading the selected files and verifying this model…"
        download = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await services.filesImporter.importFiles(files, manifest: manifest)
                message = "Imported and verified. Tap Equip to use this model."
            } catch is CancellationError { message = "Import cancelled. Existing installed models were preserved." }
            catch { errorMessage = Self.describe(error) }
            isImporting = false; isWorking = false; download = nil
            await services.refreshModels(); await refresh()
        }
    }

    func equip(_ manifest: ModelManifest) async {
        guard !isWorking, !isPreparingStorageCheck, let services else { return }
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
        guard !isWorking, !isPreparingStorageCheck, let services else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            if isEquipped(manifest), services.heavyAdmission?.snapshot().phase != .idle {
                throw ModelSelectionError.selectionInUse
            }
            try services.transferFactory.discardProgress(for: manifest)
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
        case ParakeetCoreMLModel.runtimeVersion, ParakeetModelPack.runtimeVersion: return .parakeetTDTCoreML
        case "llama.cpp-b5046": return .llamaGGUF
        default: return nil
        }
    }

    private static func manifest(_ repository: HuggingFaceModelRepository,
        assessment: HuggingFaceCompatibilityAssessment, purpose: ModelPurpose) throws -> ModelManifest {
        guard let profile = assessment.profile, let license = repository.licenseIdentifier,
              !license.isEmpty, !assessment.selectedFiles.isEmpty else { throw ModelInstallationError.invalidManifest }
        if profile == .parakeetTDTCoreML {
            let pack = repository.parakeetManifest ?? ParakeetCoreMLModel.manifest
            guard assessment.status == .supported, repository.revision == pack.revision else {
                throw ModelInstallationError.invalidManifest
            }
            _ = try ParakeetModelPack.configuration(for: pack)
            return pack
        }
        let artifacts = try assessment.selectedFiles.map { file -> ModelArtifact in
            guard let bytes = file.byteCount, let digest = file.sha256, bytes > 0 else {
                throw ModelInstallationError.invalidManifest
            }
            let name = URL(fileURLWithPath: file.fileName).lastPathComponent
            return ModelArtifact(role: .summary, fileName: name, byteCount: bytes, sha256: digest,
                downloadURL: file.downloadURL, digestProvenance: .upstreamReported)
        }
        let identifier = ModelInstallationIdentity.make(repositoryID: repository.id.rawValue,
            revision: repository.revision, purpose: purpose,
            repositoryRelativeFiles: assessment.selectedFiles.map(\.fileName))
        let upstream = URL(string: "https://huggingface.co/" + repository.id.rawValue)!
        return ModelManifest(modelID: String(identifier), purpose: purpose, upstreamRepository: upstream,
            revision: repository.revision, licenseIdentifier: license,
            licenseNotice: "Publisher: \(repository.id.rawValue). Declared license: \(license). Preserve upstream attribution and terms from the pinned model card: https://huggingface.co/\(repository.id.rawValue)/blob/\(repository.revision)/README.md",
            runtimeVersion: "llama.cpp-b5046", artifacts: artifacts)
    }

    private static func describe(_ error: any Error) -> String {
        if let value = error as? ParakeetModelPackError {
            switch value {
            case .unsupportedContract: return "This Parakeet decoder version needs an app update."
            case .invalidManifest: return "This model pack has invalid source, checksum or component details."
            }
        }
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
