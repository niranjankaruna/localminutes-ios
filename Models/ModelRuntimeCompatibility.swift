import Foundation

/// Separates public format discovery from this build's actual adapter scope.
public enum ModelRuntimeCompatibility {
    public static func assess(repository: HuggingFaceModelRepository,
                              format: HuggingFaceCompatibilityAssessment,
                              availableProfiles: Set<HuggingFaceRuntimeProfile>) -> HuggingFaceCompatibilityAssessment {
        guard [.supported, .plannedRuntime].contains(format.status), let profile = format.profile else {
            return format
        }
        func result(_ status: HuggingFaceCompatibilityStatus, _ reason: String) -> HuggingFaceCompatibilityAssessment {
            .init(status: status, profile: profile, selectedFiles: format.selectedFiles,
                  totalBytes: format.totalBytes, reasons: [reason],
                  suggestedRepositories: format.suggestedRepositories)
        }
        guard availableProfiles.contains(profile) else {
            return result(.plannedRuntime, "This file format is recognized, but its inference engine is not available in this build.")
        }
        switch profile {
        case .parakeetTDTCoreML:
            let reviewed = repository.parakeetManifest ?? ParakeetCoreMLModel.manifest
            guard (try? ParakeetModelPack.configuration(for: reviewed)) != nil,
                  repository.id.rawValue.lowercased() == reviewed.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased(),
                  repository.revision == reviewed.revision,
                  format.selectedFiles.count == reviewed.artifacts.count,
                  Set(format.selectedFiles.map(\.fileName)).count == reviewed.artifacts.count,
                  format.selectedFiles.allSatisfy({ file in reviewed.artifacts.contains {
                      $0.fileName == file.fileName && $0.byteCount == file.byteCount && $0.sha256 == file.sha256
                  } }) else {
                return result(.unsupported, "The native Core ML adapter needs the complete resource set declared by this supported Parakeet model pack.")
            }
            return result(.supported, "Core ML decodes speech on CPU in short chunks. Memory use, live speed and locked-screen operation still need checks on this iPhone.")
        case .llamaGGUF:
            guard let architecture = repository.modelType?.lowercased() else {
                return result(.unverified, "The repository does not identify its GGUF architecture. This build supports reviewed Qwen2 and Phi3 templates; compatibility cannot be confirmed from this metadata.")
            }
            guard ["qwen2", "phi3"].contains(architecture) else {
                return result(.unsupported, "The GGUF container is recognized, but this build has no reviewed chat template for \(architecture). Current summary adapters support Qwen2 and Phi3.")
            }
            guard format.selectedFiles.allSatisfy({ !$0.fileName.contains("/") }) else {
                return result(.unsupported, "This build's summary loader requires a GGUF file at the repository root. Nested-file loading needs a tested adapter update.")
            }
            return result(.supported, "This GGUF architecture is supported by the CPU llama.cpp engine. The installed file and its actual chat template are verified again before inference; quality and phone resources still need measurement.")
        }
    }
}
