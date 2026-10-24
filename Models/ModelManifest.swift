import Foundation

// TEST-FIRST INTERFACE DRAFT. Immutable metadata only; no installer behavior.
public enum ModelPurpose: String, Codable, Sendable { case speechRecognition, summary }
public enum ModelFileRole: String, Codable, Sendable { case encoder, decoder, joiner, tokens, summary, whisper, coreMLAsset }
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

    public init(schemaVersion: Int = 1, modelID: String, purpose: ModelPurpose,
                upstreamRepository: URL, revision: String, licenseIdentifier: String,
                licenseNotice: String, runtimeVersion: String, sampleRate: Int? = nil,
                featureDimension: Int? = nil, artifacts: [ModelArtifact]) {
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
    }
}

public enum StreamingEnglishModel {
    // These are immutable expected upstream digests, not a local download or
    // inference claim. Only tokens.txt has prior independent download evidence.
    public static let manifest = ModelManifest(
        modelID: "sherpa-zipformer-en-2023-06-26-chunk16-left128-int8",
        purpose: .speechRecognition,
        upstreamRepository: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26")!,
        revision: "672fbf1b30579d6585301139bb363f42a0ad4a24",
        licenseIdentifier: "Apache-2.0",
        licenseNotice: "Model publisher: csukuangfj. Training model: Zengwei/icefall-asr-librispeech-streaming-zipformer-2023-05-17. Publisher model card identifies Apache-2.0. License: https://www.apache.org/licenses/LICENSE-2.0. Preserve upstream attribution and license with the application.",
        runtimeVersion: "sherpa-onnx-1.13.8",
        sampleRate: 16_000,
        featureDimension: 80,
        artifacts: [
            artifact(.encoder, "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 71_083_163,
                     "563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1", .upstreamReported),
            artifact(.decoder, "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 1_307_236,
                     "98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02", .upstreamReported),
            artifact(.joiner, "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 259_335,
                     "d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297", .upstreamReported),
            artifact(.tokens, "tokens.txt", 5_048,
                     "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb", .independentlyDownloaded)
        ]
    )

    private static func artifact(_ role: ModelFileRole, _ name: String, _ count: Int64,
                                 _ digest: String, _ provenance: ModelDigestProvenance) -> ModelArtifact {
        ModelArtifact(role: role, fileName: name, byteCount: count, sha256: digest,
            downloadURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26/resolve/672fbf1b30579d6585301139bb363f42a0ad4a24/\(name)")!,
            digestProvenance: provenance)
    }
}
