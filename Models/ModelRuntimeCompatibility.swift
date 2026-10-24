import Foundation

/// Separates public format discovery from this build's actual adapter scope.
/// TEST-FIRST extraction: deliberately retains broad pre-regression behavior.
public enum ModelRuntimeCompatibility {
    public static func assess(repository: HuggingFaceModelRepository,
                              format: HuggingFaceCompatibilityAssessment,
                              availableProfiles: Set<HuggingFaceRuntimeProfile>) -> HuggingFaceCompatibilityAssessment {
        if format.status == .plannedRuntime, format.profile == .whisperGGML {
            return HuggingFaceCompatibilityAssessment(status: .supported, profile: format.profile,
                selectedFiles: format.selectedFiles, totalBytes: format.totalBytes,
                reasons: ["Whisper GGML format is supported by this build. Accuracy and live speed on this phone still need measurement."],
                suggestedRepositories: format.suggestedRepositories)
        }
        return format
    }
}
