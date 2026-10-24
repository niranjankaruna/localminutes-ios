import Foundation

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
    public init(rootURL: URL, models: ModelInstallationManager,
                availableProfiles: Set<HuggingFaceRuntimeProfile>,
                canChangeSelection: @escaping @MainActor () -> Bool) {}

    // TEST-FIRST no-op seams only. No verification, persistence or selection
    // behavior is implemented before the exact hosted assertion RED is read.
    public func select(manifest: ModelManifest, profile: HuggingFaceRuntimeProfile,
                       for purpose: ModelPurpose) async throws -> StoredModelSelection {
        StoredModelSelection(manifest: manifest, profile: profile,
            installationID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }

    public func selected(for purpose: ModelPurpose) async throws -> StoredModelSelection? { nil }
    public func resolve(for purpose: ModelPurpose) async throws -> VerifiedModel? { nil }
    public func hasSelectionRecord(for purpose: ModelPurpose) async throws -> Bool { false }
    public func clear(for purpose: ModelPurpose) async throws {}
    public func removeSelected(for purpose: ModelPurpose) async throws {}
}
