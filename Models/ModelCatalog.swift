import Foundation

/// The app offers only these reviewed, immutable model variants. Downloading a
/// variant never performs repository discovery or follows a mutable branch.
public struct ModelCatalogVariant: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let manifest: ModelManifest
    public let profile: HuggingFaceRuntimeProfile

    public var repositoryName: String {
        manifest.upstreamRepository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    public var downloadBytes: Int64 { manifest.artifacts.reduce(0) { $0 + $1.byteCount } }

    public init(id: String, title: String, detail: String, manifest: ModelManifest,
                profile: HuggingFaceRuntimeProfile) {
        self.id = id; self.title = title; self.detail = detail
        self.manifest = manifest; self.profile = profile
    }

    /// Old installations keep their original provenance and runtime pin. Matching
    /// the exact source bytes lets an upgrade display/equip/remove those installs
    /// without downloading another copy solely to change catalogue metadata.
    public func matches(_ installed: ModelManifest) -> Bool {
        ModelCatalog.matchesSourceWeights(installed, manifest)
    }
}

public struct ModelCatalogFamily: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let purpose: ModelPurpose
    public let variants: [ModelCatalogVariant]

    public init(id: String, title: String, detail: String, purpose: ModelPurpose,
                variants: [ModelCatalogVariant]) {
        self.id = id; self.title = title; self.detail = detail
        self.purpose = purpose; self.variants = variants
    }
}

public enum ModelCatalog {
    private struct Catalog: Decodable {
        let schemaVersion: Int
        let families: [Family]
    }
    private struct Family: Decodable {
        let id: String
        let title: String
        let detail: String
        let variants: [Variant]
    }
    private struct Variant: Decodable {
        let id: String
        let title: String
        let detail: String
        let family: SummaryModelFamily
        let variant: SummaryModelVariant?
        let repository: String
        let revision: String
        let fileName: String
        let byteCount: Int64
        let sha256: String
        let licenseIdentifier: String
        let licenseURL: URL
        let sourceRepository: String?
    }
    private enum CatalogError: Error { case missingResource, invalidResource }
    private static let loaded: Result<[ModelCatalogFamily], Error> = Result {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "SummaryCatalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    public static var loadError: String? {
        if case .failure = loaded { return "The model catalogue could not be loaded. Reinstall the app to restore it." }
        return nil
    }
    public static var summaryFamilies: [ModelCatalogFamily] { (try? loaded.get()) ?? [] }

    public static func families(for purpose: ModelPurpose,
                                speechPacks: [ModelManifest] = []) -> [ModelCatalogFamily] {
        if purpose == .summary { return summaryFamilies }
        let v2 = ParakeetCoreMLModel.manifest
        var result = [speechFamily(v2, version: "v2", detail: "English speech recognition. Transcribes audio on this iPhone.")]
        // Exactly one reviewed v3 card. Other packs cannot expand the catalogue.
        if let v3 = speechPacks.first(where: {
            (try? ParakeetModelPack.configuration(for: $0).decoderContract) == "parakeet-tdt-v3"
        }) {
            result.append(speechFamily(v3, version: "v3", detail: "Multilingual speech recognition. Transcribes audio on this iPhone."))
        }
        return result
    }

    public static func variant(id: String) -> ModelCatalogVariant? {
        summaryFamilies.flatMap(\.variants).first { $0.id == id }
    }

    public static func matchesSourceWeights(_ lhs: ModelManifest, _ rhs: ModelManifest) -> Bool {
        guard lhs.purpose == rhs.purpose, lhs.upstreamRepository == rhs.upstreamRepository,
              lhs.revision == rhs.revision, lhs.artifacts.count == rhs.artifacts.count else { return false }
        let left = lhs.artifacts.sorted { $0.fileName < $1.fileName }
        let right = rhs.artifacts.sorted { $0.fileName < $1.fileName }
        return zip(left, right).allSatisfy { pair in
            let (first, second) = pair
            return first.role == second.role && first.fileName == second.fileName
                && first.byteCount == second.byteCount && first.sha256 == second.sha256
                && first.downloadURL == second.downloadURL
        }
    }

    private static func speechFamily(_ manifest: ModelManifest, version: String,
                                      detail: String) -> ModelCatalogFamily {
        .init(id: "parakeet-" + version, title: "Parakeet " + version, detail: detail,
              purpose: .speechRecognition, variants: [
                .init(id: manifest.modelID, title: "0.6B · INT8", detail: "Core ML · 16 kHz audio",
                      manifest: manifest, profile: .parakeetTDTCoreML)
              ])
    }

    /// Internal for tests: validate bundled data before any download is offered.
    static func decode(_ data: Data) throws -> [ModelCatalogFamily] {
        guard data.count <= 131_072 else { throw CatalogError.invalidResource }
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.schemaVersion == 1, !catalog.families.isEmpty else { throw CatalogError.invalidResource }
        var familyIDs = Set<String>()
        var variantIDs = Set<String>()
        func hex(_ value: String, length: Int) -> Bool {
            value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        return try catalog.families.map { family in
            guard familyIDs.insert(family.id).inserted, !family.title.isEmpty, !family.variants.isEmpty else {
                throw CatalogError.invalidResource
            }
            let variants = try family.variants.map { variant -> ModelCatalogVariant in
                let repositoryParts = variant.repository.split(separator: "/")
                guard variantIDs.insert(variant.id).inserted, ModelArtifactPath.component(variant.id),
                      variant.family.rawValue == family.id, !variant.title.isEmpty,
                      repositoryParts.count == 2,
                      repositoryParts.allSatisfy({ ModelArtifactPath.component(String($0)) }),
                      ["Qwen", "microsoft", "google", "ggml-org", "unsloth"].contains(String(repositoryParts[0])),
                      hex(variant.revision, length: 40), hex(variant.sha256, length: 64),
                      variant.byteCount > 0, variant.byteCount <= 8_589_934_592,
                      ModelArtifactPath.component(variant.fileName), variant.fileName.hasSuffix(".gguf"),
                      !variant.licenseIdentifier.isEmpty, variant.licenseURL.scheme == "https" else {
                    throw CatalogError.invalidResource
                }
                let repository = URL(string: "https://huggingface.co/" + variant.repository)!
                let attribution = variant.sourceRepository.map { "Original model: https://huggingface.co/\($0). " } ?? ""
                let configuration = SummaryModelConfiguration(family: variant.family,
                    variant: variant.variant ?? .standard)
                guard configuration.isSupported else { throw CatalogError.invalidResource }
                let manifest = ModelManifest(modelID: variant.id, purpose: .summary,
                    upstreamRepository: repository, revision: variant.revision,
                    licenseIdentifier: variant.licenseIdentifier,
                    licenseNotice: "Publisher: \(variant.repository). \(attribution)License and required notices: \(variant.licenseURL.absoluteString). Preserve the upstream terms and attribution when redistributing this model.",
                    runtimeVersion: SummaryModelConfiguration.runtimeVersion,
                    artifacts: [.init(role: .summary, fileName: variant.fileName,
                        byteCount: variant.byteCount, sha256: variant.sha256,
                        downloadURL: repository.appendingPathComponent("resolve/\(variant.revision)/\(variant.fileName)"),
                        digestProvenance: .upstreamReported)],
                    summaryConfiguration: configuration)
                return .init(id: variant.id, title: variant.title, detail: variant.detail,
                             manifest: manifest, profile: .llamaGGUF)
            }
            return .init(id: family.id, title: family.title, detail: family.detail,
                         purpose: .summary, variants: variants)
        }
    }
}
