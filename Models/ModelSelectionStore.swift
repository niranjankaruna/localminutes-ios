import Foundation
#if SWIFT_PACKAGE
import LocalMinutesCore
#endif

/// References an approved, fully installed immutable set; it never stores an
/// external path or a mutable Hugging Face branch as an inference authority.
public struct StoredModelSelection: Codable, Equatable, Sendable {
    public let manifest: ModelManifest
    public let profile: HuggingFaceRuntimeProfile
    public let installationID: UUID

    public init(manifest: ModelManifest, profile: HuggingFaceRuntimeProfile, installationID: UUID) {
        self.manifest = manifest; self.profile = profile; self.installationID = installationID
    }
}

public enum ModelSelectionError: Error, Equatable, Sendable {
    case invalidPurpose, unavailableRuntime, notInstalled, manifestMismatch
    case selectionInUse, invalidSelection, unsafeStorage
}

/// App composition supplies its actual heavy-admission idle check. Both sides
/// of manager suspension must be checked before an atomic selection is written.
/// Missing selection preserves legacy default fallback; invalid selection throws.
@MainActor
public final class ModelSelectionStore {
    private struct Unequipped: Codable {
        let schemaVersion: Int
        let purpose: ModelPurpose
        let unequipped: Bool
    }
    private enum Choice { case absent, unequipped, equipped(StoredModelSelection) }
    private let rootURL: URL
    private let models: ModelInstallationManager
    private let availableProfiles: Set<HuggingFaceRuntimeProfile>
    private let canChangeSelection: @MainActor () -> Bool
    private var changing = false

    public init(rootURL: URL, models: ModelInstallationManager,
                availableProfiles: Set<HuggingFaceRuntimeProfile>,
                canChangeSelection: @escaping @MainActor () -> Bool) {
        self.rootURL = rootURL.standardizedFileURL
        self.models = models
        self.availableProfiles = availableProfiles
        self.canChangeSelection = canChangeSelection
    }

    public func select(manifest: ModelManifest, profile: HuggingFaceRuntimeProfile,
                       for purpose: ModelPurpose) async throws -> StoredModelSelection {
        try beginChange()
        defer { changing = false }
        guard manifest.purpose == purpose, profileMatchesPurpose(profile, purpose) else {
            throw ModelSelectionError.invalidPurpose
        }
        guard availableProfiles.contains(profile) else { throw ModelSelectionError.unavailableRuntime }
        try validateShape(manifest, profile: profile)
        _ = try requireRoot(create: true)
        // Pin bytes against removal until publication. The real installer also
        // verifies all selected artifacts; no external path is accepted here.
        let lease: ModelLease
        do { lease = try await models.acquire(modelID: manifest.modelID) }
        catch ModelInstallationError.modelMissing { throw ModelSelectionError.notInstalled }
        do {
            guard lease.model.manifest == manifest else { throw ModelSelectionError.manifestMismatch }
            try requireIdle()
            let selected = StoredModelSelection(manifest: manifest, profile: profile,
                installationID: lease.model.installationID)
            try publish(try JSONEncoder().encode(selected), for: purpose)
            // This token is private to this invocation. Release cannot be
            // invalidated by another caller; no throwing I/O follows publication.
            try? await models.release(lease)
            return selected
        } catch {
            try? await models.release(lease)
            throw error
        }
    }

    /// Durable metadata only. Native callers must resolve/revalidate before use.
    public func selected(for purpose: ModelPurpose) async throws -> StoredModelSelection? {
        if case .equipped(let selection) = try readChoice(for: purpose) { return selection }
        return nil
    }

    public func resolve(for purpose: ModelPurpose) async throws -> VerifiedModel? {
        guard case .equipped(let selection) = try readChoice(for: purpose) else { return nil }
        guard availableProfiles.contains(selection.profile) else { throw ModelSelectionError.unavailableRuntime }
        guard let verified = try await models.current(modelID: selection.manifest.modelID) else {
            throw ModelSelectionError.notInstalled
        }
        guard verified.manifest == selection.manifest, verified.installationID == selection.installationID else {
            throw ModelSelectionError.manifestMismatch
        }
        return verified
    }

    public func hasSelectionRecord(for purpose: ModelPurpose) async throws -> Bool {
        if case .absent = try readChoice(for: purpose) { return false }
        return true
    }

    public func clear(for purpose: ModelPurpose) async throws {
        try beginChange()
        defer { changing = false }
        _ = try requireRoot(create: true)
        try publishUnequipped(for: purpose)
    }

    public func removeSelected(for purpose: ModelPurpose) async throws {
        try beginChange()
        defer { changing = false }
        let choice = try readChoice(for: purpose)
        _ = try requireRoot(create: true)
        guard case .equipped(let selected) = choice else {
            try publishUnequipped(for: purpose)
            return
        }
        guard let installed = try await models.current(modelID: selected.manifest.modelID) else {
            throw ModelSelectionError.notInstalled
        }
        guard installed.manifest == selected.manifest, installed.installationID == selected.installationID else {
            throw ModelSelectionError.manifestMismatch
        }
        try requireIdle()
        // Commit explicit unequip first: a failed removal leaves installed bytes
        // available for a later retry, never silently restores a legacy default.
        // The real manager independently rejects every live model-file lease.
        try publishUnequipped(for: purpose)
        try await models.remove(modelID: selected.manifest.modelID)
    }

    private func beginChange() throws {
        guard !changing else { throw ModelSelectionError.selectionInUse }
        try requireIdle()
        changing = true
    }

    private func requireIdle() throws {
        guard canChangeSelection() else { throw ModelSelectionError.selectionInUse }
    }

    private func profileMatchesPurpose(_ profile: HuggingFaceRuntimeProfile, _ purpose: ModelPurpose) -> Bool {
        switch profile {
        case .llamaGGUF: purpose == .summary
        case .streamingZipformerONNX, .whisperGGML, .parakeetTDTCoreML: purpose == .speechRecognition
        }
    }

    private func validateShape(_ manifest: ModelManifest, profile: HuggingFaceRuntimeProfile) throws {
        let roles = Set(manifest.artifacts.map(\.role))
        let valid: Bool
        switch profile {
        case .parakeetTDTCoreML:
            valid = manifest == ParakeetCoreMLModel.manifest
        case .llamaGGUF:
            valid = manifest.purpose == .summary && manifest.artifacts.count == 1 && roles == [.summary]
                && manifest.artifacts[0].fileName.lowercased().hasSuffix(".gguf")
        case .streamingZipformerONNX:
            valid = manifest.purpose == .speechRecognition && manifest.artifacts.count == 4
                && roles == [.encoder, .decoder, .joiner, .tokens] && manifest.sampleRate == 16_000
                && manifest.featureDimension == 80
        case .whisperGGML:
            valid = manifest.purpose == .speechRecognition && manifest.artifacts.count == 1 && roles == [.whisper]
                && manifest.sampleRate == 16_000 && manifest.featureDimension == nil
                && manifest.runtimeVersion == "whisper.cpp-1.7.5"
        }
        guard valid else { throw ModelSelectionError.invalidPurpose }
    }

    private func pointer(_ purpose: ModelPurpose) -> URL {
        rootURL.appendingPathComponent(purpose.rawValue + ".json")
    }

    private func readChoice(for purpose: ModelPurpose) throws -> Choice {
        guard try requireRoot(create: false) else { return .absent }
        let url = pointer(purpose)
        guard try exists(url) else { return .absent }
        do { try PersistentFilePolicy.validateItem(url, within: rootURL) }
        catch { throw ModelSelectionError.unsafeStorage }
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize, (1...1_048_576).contains(count) else {
            throw ModelSelectionError.invalidSelection
        }
        let data = try Data(contentsOf: url)
        if let none = try? JSONDecoder().decode(Unequipped.self, from: data) {
            guard none.schemaVersion == 1, none.purpose == purpose, none.unequipped else {
                throw ModelSelectionError.invalidSelection
            }
            return .unequipped
        }
        let selected: StoredModelSelection
        do { selected = try JSONDecoder().decode(StoredModelSelection.self, from: data) }
        catch { throw ModelSelectionError.invalidSelection }
        guard selected.manifest.purpose == purpose, profileMatchesPurpose(selected.profile, purpose) else {
            throw ModelSelectionError.invalidSelection
        }
        try validateShape(selected.manifest, profile: selected.profile)
        return .equipped(selected)
    }

    private func publishUnequipped(for purpose: ModelPurpose) throws {
        try publish(try JSONEncoder().encode(Unequipped(schemaVersion: 1, purpose: purpose, unequipped: true)), for: purpose)
    }

    private func publish(_ data: Data, for purpose: ModelPurpose) throws {
        guard data.count <= 1_048_576 else { throw ModelSelectionError.invalidSelection }
        try requireIdle()
        do { try PersistentFilePolicy.writeAtomically(data, to: pointer(purpose), within: rootURL) }
        catch { throw ModelSelectionError.unsafeStorage }
    }

    private func requireRoot(create: Bool) throws -> Bool {
        guard rootURL.isFileURL, rootURL.path != "/" else { throw ModelSelectionError.unsafeStorage }
        let parent = rootURL.deletingLastPathComponent()
        do {
            if try !exists(rootURL) {
                guard create else { return false }
                try PersistentFilePolicy.validateItem(parent, within: parent)
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
            }
            try PersistentFilePolicy.validateItem(rootURL, within: parent)
            let values = try URL(fileURLWithPath: rootURL.path).resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw ModelSelectionError.unsafeStorage }
            if create { try PersistentFilePolicy.protectItem(rootURL, within: parent) }
            return true
        } catch { throw ModelSelectionError.unsafeStorage }
    }

    private func exists(_ url: URL) throws -> Bool {
        do {
            // lstat-style attributes also recognize a dangling final symlink;
            // it must never become an absent-selection legacy fallback.
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }
}
