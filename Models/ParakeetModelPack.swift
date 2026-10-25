import Foundation

public struct ParakeetModelConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let decoderContract: String
    public let encoderPrecision: String
    public init(schemaVersion: Int = 1, decoderContract: String, encoderPrecision: String = "int8") {
        self.schemaVersion = schemaVersion; self.decoderContract = decoderContract
        self.encoderPrecision = encoderPrecision
    }
}

public enum ParakeetModelPackError: Error, Equatable, Sendable {
    case unsupportedContract, invalidManifest
}

public enum ParakeetModelPack {
    public static let runtimeVersion = "coreml-parakeet-tdt-fluid-c79c4106"
    public static func decode(_ data: Data) throws -> ModelManifest {
        guard !data.isEmpty, data.count <= 65_536 else { throw ParakeetModelPackError.invalidManifest }
        let manifest: ModelManifest
        do { manifest = try JSONDecoder().decode(ModelManifest.self, from: data) }
        catch { throw ParakeetModelPackError.invalidManifest }
        _ = try configuration(for: manifest)
        return manifest
    }
    public static func configuration(for manifest: ModelManifest) throws -> ParakeetModelConfiguration {
        if manifest == ParakeetCoreMLModel.manifest {
            return .init(decoderContract: "parakeet-tdt-v2")
        }
        guard let configuration = manifest.parakeetConfiguration else { throw ParakeetModelPackError.invalidManifest }
        guard configuration.schemaVersion == 1,
              ["parakeet-tdt-v2", "parakeet-tdt-v3"].contains(configuration.decoderContract) else {
            throw ParakeetModelPackError.unsupportedContract
        }
        guard ["int8", "int8-v2", "int4"].contains(configuration.encoderPrecision),
              configuration.decoderContract != "parakeet-tdt-v2" || configuration.encoderPrecision == "int8",
              manifest.schemaVersion == 1, manifest.purpose == .speechRecognition,
              manifest.runtimeVersion == runtimeVersion, manifest.sampleRate == 16_000, manifest.featureDimension == 128,
              ModelArtifactPath.component(manifest.modelID), hex(manifest.revision, count: 40),
              !manifest.licenseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.licenseIdentifier.utf8.count <= 256, manifest.licenseNotice.utf8.count <= 16_384,
              manifest.upstreamRepository.scheme == "https", manifest.upstreamRepository.host == "huggingface.co",
              manifest.upstreamRepository.port == nil, manifest.upstreamRepository.user == nil,
              manifest.upstreamRepository.password == nil, manifest.upstreamRepository.query == nil,
              manifest.upstreamRepository.fragment == nil,
              (5...256).contains(manifest.artifacts.count) else { throw ParakeetModelPackError.invalidManifest }
        let repositoryParts = manifest.upstreamRepository.path.split(separator: "/")
        guard repositoryParts.count == 2, repositoryParts.allSatisfy({ ModelArtifactPath.component(String($0)) }) else {
            throw ParakeetModelPackError.invalidManifest
        }
        let encoder = configuration.encoderPrecision == "int8-v2" ? "Encoder_v2.mlmodelc"
            : configuration.encoderPrecision == "int4" ? "EncoderInt4.mlmodelc" : "Encoder.mlmodelc"
        let joint = configuration.decoderContract == "parakeet-tdt-v3" ? "JointDecisionv3.mlmodelc" : "JointDecision.mlmodelc"
        let bundles: Set<String> = [encoder, joint, "Decoder.mlmodelc", "Preprocessor.mlmodelc"]
        var names: Set<String> = []
        var total: Int64 = 0
        for asset in manifest.artifacts {
            guard let parts = ModelArtifactPath.components(asset.fileName), asset.role == .coreMLAsset,
                  asset.byteCount > 0, hex(asset.sha256, count: 64), names.insert(asset.fileName).inserted,
                  asset.downloadURL == manifest.upstreamRepository.appendingPathComponent("resolve/\(manifest.revision)/\(asset.fileName)"),
                  (asset.fileName == "parakeet_vocab.json" && asset.byteCount <= 4_194_304)
                    || (parts.count > 1 && bundles.contains(parts[0])) else { throw ParakeetModelPackError.invalidManifest }
            let sum = total.addingReportingOverflow(asset.byteCount)
            guard !sum.overflow, sum.partialValue <= 8_589_934_592 else { throw ParakeetModelPackError.invalidManifest }
            total = sum.partialValue
        }
        guard names.contains("parakeet_vocab.json"),
              Set(names.map { $0.lowercased() }).count == names.count,
              ModelArtifactPath.directories(for: Array(names)).isDisjoint(with: names),
              bundles.allSatisfy({ bundle in
                  ["coremldata.bin", "metadata.json", "model.mil"].allSatisfy { names.contains(bundle + "/" + $0) }
              }), (try JSONEncoder().encode(manifest)).count <= 65_536 else { throw ParakeetModelPackError.invalidManifest }
        return configuration
    }

    private static func hex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
