import Foundation

/// Shared installation/provenance contracts. Selection and persistence use this
/// registry; neither layer needs to know a particular speech decoder's format.
public enum ModelRuntimeContracts {
    public static let summaryArchitectures: Set<String> = ["qwen2", "qwen3", "phi3", "gemma3", "gemma4"]
    private struct Contract: Sendable {
        let profile: HuggingFaceRuntimeProfile
        let purpose: ModelPurpose
        let validate: @Sendable (ModelManifest) -> Bool
    }

    private static let contracts: [Contract] = [
        .init(profile: .parakeetTDTCoreML, purpose: .speechRecognition, validate: {
            (try? ParakeetModelPack.configuration(for: $0)) != nil
        }),
        .init(profile: .llamaGGUF, purpose: .summary, validate: { manifest in
            guard manifest.artifacts.count == 1,
                  manifest.artifacts[0].role == .summary,
                  manifest.artifacts[0].fileName.lowercased().hasSuffix(".gguf") else { return false }
            if let configuration = manifest.summaryConfiguration {
                return configuration.profileVersion == 1
                    && manifest.runtimeVersion == SummaryModelConfiguration.runtimeVersion
                    && (configuration.variant == .standard
                        || configuration.family == .qwen3 && configuration.variant == .qwen3Instruct2507)
            }
            // Preserve legacy installation metadata; inference performs the
            // stricter runtime-version, actual architecture and template checks.
            return true
        })
    ]

    public static var availableProfiles: Set<HuggingFaceRuntimeProfile> { Set(contracts.map(\.profile)) }

    public static func matchesPurpose(_ profile: HuggingFaceRuntimeProfile, _ purpose: ModelPurpose) -> Bool {
        contracts.contains { $0.profile == profile && $0.purpose == purpose }
    }

    public static func supports(_ manifest: ModelManifest, profile: HuggingFaceRuntimeProfile) -> Bool {
        contracts.first { $0.profile == profile && $0.purpose == manifest.purpose }?.validate(manifest) ?? false
    }
}
