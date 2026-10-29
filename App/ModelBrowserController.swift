#if os(iOS)
import Foundation
import Observation

/// App-retained catalogue actions. Only bundled, pinned variants can be downloaded.
@MainActor @Observable
final class ModelBrowserController {
    var purpose: ModelPurpose = .speechRecognition
    private(set) var installed: [ModelManifest] = []
    private(set) var equippedSpeechID: String?
    private(set) var equippedSummaryID: String?
    private(set) var resources = DeviceModelResources(freeDiskBytes: nil,
        totalMemoryBytes: nil, availableAppMemoryBytes: nil)
    private(set) var isWorking = false
    private(set) var isDownloading = false
    private(set) var isPreparingStorageCheck = false
    private(set) var storageCheckReport: StoragePrivacyReport?
    private(set) var storageCheckJSON: String?
    private(set) var storageCheckError: String?
    private(set) var message: String?
    private(set) var errorMessage: String?
    private(set) var downloadProgress: ModelTransferProgress?
    private(set) var transferManifest: ModelManifest?
    private(set) var partialDownloadIDs: Set<String> = []
    @ObservationIgnored private weak var services: LocalMinutesServices?
    @ObservationIgnored private var transferTask: Task<Void, Never>?
    #if DEBUG
    private var fixtureFamilies: [ModelCatalogFamily]?
    #endif

    init(services: LocalMinutesServices) { self.services = services }

    func families(for purpose: ModelPurpose) -> [ModelCatalogFamily] {
        #if DEBUG
        if let fixtureFamilies { return fixtureFamilies.filter { $0.purpose == purpose } }
        #endif
        return ModelCatalog.families(for: purpose, speechPacks: BundledParakeetPacks.manifests)
    }

    func variant(id: String) -> ModelCatalogVariant? { allVariants.first { $0.id == id } }

    private var allVariants: [ModelCatalogVariant] {
        families(for: .speechRecognition).flatMap(\.variants)
            + families(for: .summary).flatMap(\.variants)
    }

    /// Reuse legacy installation IDs only when source and pinned weights match.
    func installedManifest(for manifest: ModelManifest) -> ModelManifest? {
        let matches = installed.filter { Self.sameWeights($0, manifest) }
        return matches.first(where: isEquipped) ?? matches.first
    }

    private static func sameWeights(_ lhs: ModelManifest, _ rhs: ModelManifest) -> Bool {
        ModelCatalog.matchesSourceWeights(lhs, rhs)
    }

    func canDownload(_ variant: ModelCatalogVariant) -> Bool {
        guard !isWorking, !isPreparingStorageCheck,
              allVariants.contains(where: { $0.id == variant.id && $0.manifest == variant.manifest }),
              installedManifest(for: variant.manifest) == nil,
              let size = Self.downloadBytes(variant.manifest) else { return false }
        // The resumable cache and installer staging coexist during verification.
        let required = size.multipliedReportingOverflow(by: 2)
        guard !required.overflow else { return false }
        return resources.freeDiskBytes.map { $0 >= required.partialValue } ?? true
    }

    func hasPartialDownload(_ manifest: ModelManifest) -> Bool { partialDownloadIDs.contains(manifest.modelID) }

    static func downloadBytes(_ manifest: ModelManifest) -> Int64? {
        var total: Int64 = 0
        for artifact in manifest.artifacts {
            guard artifact.byteCount > 0 else { return nil }
            let next = total.addingReportingOverflow(artifact.byteCount)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }

    func refresh() async {
        guard let services else { return }
        resources = ModelDeviceResourcesReader.current(at: services.meetingsDirectory)
        if let failure = ModelCatalog.loadError { errorMessage = failure }
        else if families(for: .speechRecognition).count != 2 {
            errorMessage = "The Parakeet v3 catalogue details are missing. Reinstall the app to restore both speech models."
        }
        do {
            installed = try await services.models.installedManifests()
            equippedSpeechID = try await selectionID(for: .speechRecognition, services: services)
            equippedSummaryID = try await selectionID(for: .summary, services: services)
            partialDownloadIDs = Set(allVariants.compactMap { variant in
                let hasBytes = variant.manifest.artifacts.contains { artifact in
                    guard let checkpoint = try? services.transferFactory.checkpointDirectory(for: artifact) else { return false }
                    let partial = checkpoint.appendingPathComponent("partial.bin")
                    guard let values = try? partial.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
                        return false
                    }
                    return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) > 0
                }
                return hasBytes ? variant.id : nil
            })
        } catch { errorMessage = Self.describe(error) }
    }

    private func selectionID(for purpose: ModelPurpose, services: LocalMinutesServices) async throws -> String? {
        if try await services.modelSelections.hasSelectionRecord(for: purpose) {
            return try await services.modelSelections.selected(for: purpose)?.manifest.modelID
        }
        let legacy = purpose == .speechRecognition ? ParakeetCoreMLModel.manifest : LocalMinutesServices.summaryManifest
        return installed.contains(where: {
            $0.modelID == legacy.modelID && Self.sameWeights($0, legacy)
        }) ? legacy.modelID : nil
    }

    func download(_ variant: ModelCatalogVariant) {
        guard canDownload(variant), let services else { return }
        let manifest = variant.manifest
        isWorking = true; isDownloading = true; errorMessage = nil
        transferManifest = manifest; downloadProgress = nil
        message = "Downloading model files, then verifying their size and checksum…"
        transferTask = Task { [weak self] in
            guard let self else { return }
            let updates = AsyncStream<ModelTransferProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let consumer = Task { @MainActor [weak self] in
                for await event in updates.stream { self?.downloadProgress = event }
            }
            do {
                // Legacy installs may have an implicit default selection. Keep
                // that selection, but persist an explicit empty choice before a
                // first download so installing default weights never equips them.
                let hasSelection = try await services.modelSelections.hasSelectionRecord(for: manifest.purpose)
                if !hasSelection {
                    let defaultModel = manifest.purpose == .speechRecognition
                        ? ParakeetCoreMLModel.manifest : LocalMinutesServices.summaryManifest
                    let existing = try await services.models.current(modelID: defaultModel.modelID)
                    if existing.map({ Self.sameWeights($0.manifest, defaultModel) }) != true {
                        try await services.modelSelections.clear(for: manifest.purpose)
                    }
                }
                _ = try await services.models.download(manifest, progress: { event in
                    _ = updates.continuation.yield(event)
                })
                // Installation now owns verified bytes. Remove redundant cache copies.
                try services.transferFactory.discardProgress(for: manifest)
                message = "Model downloaded. Equip it when you are ready."
            } catch is CancellationError { message = "Download paused. Your progress is saved." }
            catch { errorMessage = Self.describe(error) }
            updates.continuation.finish()
            await consumer.value
            isDownloading = false; isWorking = false; transferTask = nil
            await services.refreshModels(); await refresh()
        }
    }

    func resumeDownload() {
        guard let manifest = transferManifest, let variant = variant(id: manifest.modelID) else { return }
        download(variant)
    }
    func cancelDownload() { transferTask?.cancel() }

    func equip(_ manifest: ModelManifest) async {
        guard !isWorking, !isPreparingStorageCheck, let services,
              let installed = installedManifest(for: manifest),
              let variant = allVariants.first(where: { Self.sameWeights($0.manifest, installed) }) else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await services.modelSelections.select(manifest: installed, profile: variant.profile, for: installed.purpose)
            await services.refreshModels(); await refresh()
            message = "Equipped for \(manifest.purpose == .speechRecognition ? "recording" : "summaries and answers")."
        } catch { errorMessage = Self.describe(error) }
    }

    /// Remove installed bytes and retained checkpoints, including older IDs for
    /// the same pinned weights. Explicit unequip prevents a legacy fallback.
    func remove(_ manifest: ModelManifest) async {
        guard !isWorking, !isPreparingStorageCheck, let services else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let matches = installed.filter { Self.sameWeights($0, manifest) }
            if matches.contains(where: isEquipped), services.heavyAdmission?.snapshot().phase != .idle {
                throw ModelSelectionError.selectionInUse
            }
            try services.transferFactory.discardProgress(for: manifest)
            for model in matches {
                try services.transferFactory.discardProgress(for: model)
                let selected = try await services.modelSelections.selected(for: model.purpose)
                if selected?.manifest.modelID == model.modelID {
                    try await services.modelSelections.removeSelected(for: model.purpose)
                } else {
                    if isEquipped(model) { try await services.modelSelections.clear(for: model.purpose) }
                    try await services.models.remove(modelID: model.modelID)
                }
            }
            if transferManifest.map({ Self.sameWeights($0, manifest) }) == true {
                transferManifest = nil; downloadProgress = nil
            }
            await services.refreshModels(); await refresh()
            message = "Model files removed and storage freed. Meetings and notes were preserved."
        } catch {
            await services.refreshModels(); await refresh()
            errorMessage = Self.describe(error)
        }
    }

    func isEquipped(_ manifest: ModelManifest) -> Bool {
        manifest.modelID == (manifest.purpose == .speechRecognition ? equippedSpeechID : equippedSummaryID)
    }

    func prepareStorageCheck(recordingOwner: RecordingSessionOwner?) async {
        guard !isPreparingStorageCheck else { return }
        storageCheckReport = nil; storageCheckJSON = nil; storageCheckError = nil
        guard !isWorking else {
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
            guard let text = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            storageCheckReport = report; storageCheckJSON = text
        } catch StoragePrivacyReportError.recordingActive {
            storageCheckError = "Stop recording and wait for cleanup before preparing the storage check."
        } catch StoragePrivacyReportError.busy {
            storageCheckError = "Finish playback, local processing or library changes before preparing the storage check."
        } catch StoragePrivacyReportError.notReady {
            storageCheckError = "Storage check is unavailable until the app is ready."
        } catch StoragePrivacyReportError.invalidBuildIdentity {
            storageCheckError = "Build information could not be verified for this storage check."
        } catch is CancellationError { storageCheckError = "Storage check cancelled." }
        catch { storageCheckError = "The storage check could not be prepared. Try again when the app is idle." }
    }

    #if DEBUG
    func useFixtureCatalog(_ families: [ModelCatalogFamily]) {
        guard ModelBrowserAccessibilityFixture.requested else { return }
        fixtureFamilies = families
    }
    func updateDownloadProgress(_ value: ModelTransferProgress) { downloadProgress = value }
    #endif

    private static func describe(_ error: any Error) -> String {
        if let value = error as? ModelSelectionError {
            switch value {
            case .selectionInUse: return "Stop recording or local inference before changing equipped models."
            case .unavailableRuntime: return "This model's inference engine is not available in this build."
            default: return "The model did not pass verification. Download it again before equipping it."
            }
        }
        if let value = error as? ModelInstallationError {
            switch value {
            case .modelInUse: return "This model is in use. Stop recording or local inference and try again."
            case .insufficientSpace: return "There is not enough free storage. Remove another downloaded model and try again."
            case .checksumMismatch, .sizeMismatch: return "The downloaded files could not be verified. Remove the download and try again."
            default: break
            }
        }
        return "The model operation failed. Check your connection and free storage, then try again."
    }
}
#endif
