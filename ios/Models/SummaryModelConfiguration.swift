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

/// Reviewed total input + output capacity for one exact model variant.
/// Larger published windows sometimes require explicit positional scaling.
public struct SummaryContextWindow: Codable, Equatable, Sendable {
    public static let maximumSupportedTokens = 262_144
    public static let maximumSupportedOutputTokens = 16_384
    public static let maximumPromptUTF8Bytes = 8_388_608
    public static let legacy = SummaryContextWindow(maximumTokens: 4_096)
    public let maximumTokens: Int
    /// App response ceiling; nil preserves older immutable manifest decoding.
    public let maximumOutputTokens: Int?
    public var outputTokenLimit: Int {
        maximumOutputTokens ?? (maximumTokens > 1 ? min(1_024, maximumTokens - 1) : 0)
    }
    public let yarnOriginalContextTokens: Int?

    public init(maximumTokens: Int, yarnOriginalContextTokens: Int? = nil, maximumOutputTokens: Int? = nil) {
        self.maximumTokens = maximumTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.yarnOriginalContextTokens = yarnOriginalContextTokens
    }

    public var isSupported: Bool {
        guard (512...Self.maximumSupportedTokens).contains(maximumTokens),
              (1...Self.maximumSupportedOutputTokens).contains(outputTokenLimit),
              outputTokenLimit < maximumTokens else { return false }
        guard let original = yarnOriginalContextTokens else { return true }
        return original == 32_768 && maximumTokens == 131_072
    }

    /// KV cache allocation follows the actual request, while admission always
    /// uses the published maximum. Never allocate a full 256K cache for a short prompt.
    public func allocationTokens(requiredTokens: Int) -> Int? {
        guard isSupported, requiredTokens > 0, requiredTokens <= maximumTokens else { return nil }
        return min(maximumTokens, max(512, ((requiredTokens + 255) / 256) * 256))
    }
}

public struct SummaryModelConfiguration: Codable, Equatable, Sendable {
    public static let runtimeVersion = "llama.cpp-b11900"
    public let profileVersion: Int
    public let family: SummaryModelFamily
    public let variant: SummaryModelVariant
    // Optional so immutable manifests installed before context profiles still decode.
    public let contextWindow: SummaryContextWindow?

    public init(family: SummaryModelFamily, variant: SummaryModelVariant = .standard,
                profileVersion: Int = 1, contextWindow: SummaryContextWindow? = nil) {
        self.profileVersion = profileVersion
        self.family = family
        self.variant = variant
        self.contextWindow = contextWindow
    }

    public var isSupported: Bool {
        profileVersion == 1 && (variant == .standard || family == .qwen3)
            && (contextWindow?.isSupported ?? true)
            && (contextWindow?.yarnOriginalContextTokens == nil || (family == .qwen3 && variant == .standard))
            && (contextWindow?.outputTokenLimit ?? 1_024) <= outputPolicyLimit
    }

    private var outputPolicyLimit: Int {
        switch family {
        case .qwen25, .gemma3: 8_192
        case .phi3: 2_048
        case .qwen3, .phi4, .gemma4: 16_384
        }
    }
}
