import Foundation

/// Reviewed text-generation families. A family identifies an adapter, not a
/// promise that every weight file published under that family is compatible.
public enum SummaryModelFamily: String, CaseIterable, Codable, Equatable, Sendable {
    case qwen25, qwen3, phi3, phi4, gemma3, gemma4
}

public enum SummaryModelVariant: String, Codable, Equatable, Sendable {
    case standard
    /// This release has no thinking mode and must not receive a think prefill.
    case qwen3Instruct2507
}

public struct SummaryModelConfiguration: Codable, Equatable, Sendable {
    public static let runtimeVersion = "llama.cpp-b11900"
    public let profileVersion: Int
    public let family: SummaryModelFamily
    public let variant: SummaryModelVariant

    public init(family: SummaryModelFamily, variant: SummaryModelVariant = .standard,
                profileVersion: Int = 1) {
        self.profileVersion = profileVersion
        self.family = family
        self.variant = variant
    }

    public var isSupported: Bool {
        profileVersion == 1 && (variant == .standard || family == .qwen3)
    }
}
