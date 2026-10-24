import Foundation

public enum HuggingFaceRepositoryError: Error, Equatable, Sendable {
    case notImplemented, invalidRepository, invalidResponse, invalidRevision, invalidFile
    case responseTooLarge, tooManyFiles, unapprovedResponseURL, invalidLimits
    case httpStatus(Int)
}

public struct HuggingFaceRepositoryID: Equatable, Sendable {
    public let owner: String
    public let name: String
    public var rawValue: String { "\(owner)/\(name)" }

    // TEST-FIRST stub: normalization must wait for observed behavioral RED.
    public init(input: String) throws { throw HuggingFaceRepositoryError.notImplemented }
}

public struct HuggingFaceRepositoryLimits: Sendable {
    public let metadataBytes: Int
    public let cardBytes: Int
    public let configBytes: Int
    public let fileCount: Int
    public init(metadataBytes: Int = 1_048_576, cardBytes: Int = 262_144,
                configBytes: Int = 262_144, fileCount: Int = 2_048) {
        self.metadataBytes = metadataBytes; self.cardBytes = cardBytes
        self.configBytes = configBytes; self.fileCount = fileCount
    }
}

public struct HuggingFaceModelFile: Equatable, Sendable {
    public let fileName: String
    public let byteCount: Int64?
    /// An upstream-reported SHA-256, never a claim of locally verified bytes.
    public let sha256: String?
    public let downloadURL: URL
}

public enum HuggingFaceRuntimeProfile: String, Codable, Hashable, Sendable {
    case streamingZipformerONNX, whisperGGML, llamaGGUF
}

public enum HuggingFaceCompatibilityStatus: String, Equatable, Sendable {
    case notImplemented, supported, plannedRuntime, conversionRequired
    case unsupported, unverified, tooLarge, gated, selectionRequired
}

public struct HuggingFaceCompatibilityAssessment: Equatable, Sendable {
    public let status: HuggingFaceCompatibilityStatus
    public let profile: HuggingFaceRuntimeProfile?
    public let selectedFiles: [HuggingFaceModelFile]
    public let totalBytes: Int64?
    public let reasons: [String]
    public let suggestedRepositories: [String]
    public var suggestedRepository: String? { suggestedRepositories.first }
}

public struct DeviceModelResources: Equatable, Sendable {
    public let freeDiskBytes: Int64?
    public let totalMemoryBytes: Int64?
    public let availableAppMemoryBytes: Int64?
    public init(freeDiskBytes: Int64?, totalMemoryBytes: Int64?, availableAppMemoryBytes: Int64?) {
        self.freeDiskBytes = freeDiskBytes; self.totalMemoryBytes = totalMemoryBytes
        self.availableAppMemoryBytes = availableAppMemoryBytes
    }
}

public enum ModelResourceStatus: String, Equatable, Sendable {
    case notImplemented, sufficient, insufficientStorage, insufficientMemory
    case caution, unknown, contextLimitExceeded
}

public enum ModelMemoryEstimateBasis: String, Equatable, Sendable {
    case unknown, upstreamWhisperReference, weightsAndContextEstimate
}

public struct ModelResourceAssessment: Equatable, Sendable {
    public let status: ModelResourceStatus
    public let requiredDiskBytes: Int64?
    public let estimatedRAMLowerBoundBytes: Int64?
    public let estimatedRAMUpperBoundBytes: Int64?
    public let requestedContextTokens: Int
    public let maximumContextTokens: Int?
    public let estimateBasis: ModelMemoryEstimateBasis
    public let notes: [String]
}

public struct HuggingFaceContextConfiguration: Equatable, Sendable {
    public let maximumTokens: Int?
    public let hiddenSize: Int?
    public let layerCount: Int?
    public let attentionHeadCount: Int?
    public let keyValueHeadCount: Int?
}

public struct HuggingFaceModelRepository: Equatable, Sendable {
    public let id: HuggingFaceRepositoryID
    public let revision: String
    public let files: [HuggingFaceModelFile]
    public let licenseIdentifier: String?
    /// Untrusted Markdown. UI must render it as inert text or sanitize it;
    /// never execute card code/HTML or load its embedded remote images.
    public let cardMarkdown: String?
    public let pipelineTag: String?
    public let libraryName: String?
    public let modelType: String?
    public let architectures: [String]
    public let isGated: Bool
    public let contextConfiguration: HuggingFaceContextConfiguration?

    /// Format compatibility is not installed-model readiness or quality proof.
    /// Whisper GGML is a planned backend; only reviewed Qwen2/Phi3 GGUF and
    /// streaming Zipformer configurations can qualify for existing runtimes.
    public func assessment(for purpose: ModelPurpose, fileName: String? = nil,
                           maximumDownloadBytes: Int64) -> HuggingFaceCompatibilityAssessment {
        HuggingFaceCompatibilityAssessment(status: .notImplemented, profile: nil,
            selectedFiles: [], totalBytes: nil, reasons: [], suggestedRepositories: [])
    }

    /// Compare only the selected artifact/set against actual device facts.
    /// Estimates are guidance, never measured peak memory or admission proof.
    public func resourceAssessment(for purpose: ModelPurpose, fileName: String? = nil,
                                   contextTokens: Int = 2_048,
                                   device: DeviceModelResources) -> ModelResourceAssessment {
        ModelResourceAssessment(status: .notImplemented, requiredDiskBytes: nil,
            estimatedRAMLowerBoundBytes: nil, estimatedRAMUpperBoundBytes: nil,
            requestedContextTokens: contextTokens, maximumContextTokens: nil,
            estimateBasis: .unknown, notes: [])
    }
}

/// Public, unauthenticated metadata only. No weights, remote code, tokens,
/// browser cookies or model-card embedded resources may be fetched here.
public actor HuggingFaceRepositoryService {
    public init(configuration: URLSessionConfiguration = .ephemeral,
                limits: HuggingFaceRepositoryLimits = .init()) {}

    // TEST-FIRST stub: no network or metadata behavior before hosted RED.
    public func inspect(_ input: String) async throws -> HuggingFaceModelRepository {
        throw HuggingFaceRepositoryError.notImplemented
    }
}
