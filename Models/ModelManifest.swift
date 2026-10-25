import Foundation

// Immutable model metadata; installation is owned by ModelInstallationManager.
public enum ModelPurpose: String, Codable, Sendable { case speechRecognition, summary }
public enum ModelFileRole: String, Codable, Sendable { case summary, coreMLAsset }
public enum ModelDigestProvenance: String, Codable, Sendable {
    case upstreamReported, independentlyDownloaded
}

public struct ModelArtifact: Codable, Equatable, Sendable {
    public let role: ModelFileRole
    public let fileName: String
    public let byteCount: Int64
    public let sha256: String
    public let downloadURL: URL
    public let digestProvenance: ModelDigestProvenance

    public init(role: ModelFileRole, fileName: String, byteCount: Int64, sha256: String,
                downloadURL: URL, digestProvenance: ModelDigestProvenance) {
        self.role = role
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.downloadURL = downloadURL
        self.digestProvenance = digestProvenance
    }
}

public struct ModelManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelID: String
    public let purpose: ModelPurpose
    public let upstreamRepository: URL
    public let revision: String
    public let licenseIdentifier: String
    public let licenseNotice: String
    public let runtimeVersion: String
    public let sampleRate: Int?
    public let featureDimension: Int?
    public let artifacts: [ModelArtifact]
    public let parakeetConfiguration: ParakeetModelConfiguration?

    public init(schemaVersion: Int = 1, modelID: String, purpose: ModelPurpose,
                upstreamRepository: URL, revision: String, licenseIdentifier: String,
                licenseNotice: String, runtimeVersion: String, sampleRate: Int? = nil,
                featureDimension: Int? = nil, artifacts: [ModelArtifact],
                parakeetConfiguration: ParakeetModelConfiguration? = nil) {
        self.schemaVersion = schemaVersion
        self.modelID = modelID
        self.purpose = purpose
        self.upstreamRepository = upstreamRepository
        self.revision = revision
        self.licenseIdentifier = licenseIdentifier
        self.licenseNotice = licenseNotice
        self.runtimeVersion = runtimeVersion
        self.sampleRate = sampleRate
        self.featureDimension = featureDimension
        self.artifacts = artifacts
        self.parakeetConfiguration = parakeetConfiguration
    }
}
