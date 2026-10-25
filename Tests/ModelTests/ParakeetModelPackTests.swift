import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesModels

@MainActor
final class ParakeetModelPackTests: XCTestCase {
    func testLegacyV2PinResolvesItsDecoderWithoutChangingItsManifest() throws {
        let legacy = ParakeetCoreMLModel.manifest
        XCTAssertNil(legacy.parakeetConfiguration)
        XCTAssertEqual(try ParakeetModelPack.configuration(for: legacy).decoderContract, "parakeet-tdt-v2")
        XCTAssertEqual(try JSONDecoder().decode(ModelManifest.self, from: JSONEncoder().encode(legacy)), legacy)
    }

    func testCompatiblePacksFromDifferentPublishersRevisionsAndWeightsInstallAndEquipIndependently() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-parakeet-pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { _ in 32_000_000_000 }, downloader: { artifact, output in
                let bytes = Self.bytes(artifact.fileName)
                try bytes.write(to: output)
            })
        for (index, contract) in ["parakeet-tdt-v2", "parakeet-tdt-v3"].enumerated() {
            let manifest = pack(contract: contract, suffix: String(index))
            let decoded = try ParakeetModelPack.decode(JSONEncoder().encode(manifest))
            XCTAssertEqual(decoded, manifest, "A pack's exact integrity pin must survive decoding")
            XCTAssertEqual(try ParakeetModelPack.configuration(for: decoded).decoderContract, contract)
            let installed: VerifiedModel
            do { installed = try await manager.download(decoded) }
            catch { XCTFail("Compatible native packs must install using their own reviewed hashes: \(error)"); continue }
            let choices = ModelSelectionStore(directory: root.appendingPathComponent("Selections", isDirectory: true),
                models: manager, availableProfiles: [.parakeetTDTCoreML], canChangeSelection: { true })
            do {
                _ = try await choices.select(manifest: installed.manifest, profile: .parakeetTDTCoreML, for: .speechRecognition)
                let reopened = try await choices.resolve(for: .speechRecognition)
                XCTAssertEqual(reopened?.manifest, decoded)
            } catch { XCTFail("The family adapter must accept an installed pack independently of its publisher: \(error)") }
        }
        let all = try await manager.installedManifests()
        XCTAssertEqual(all.count, 2, "Equipping a new pack must retain the previous installed model")
    }

    func testUnknownFutureDecoderContractRequiresAnEngineUpdateInsteadOfGuessingV2() throws {
        XCTAssertThrowsError(try ParakeetModelPack.decode(JSONEncoder().encode(pack(contract: "parakeet-tdt-v4")))) {
            XCTAssertEqual($0 as? ParakeetModelPackError, .unsupportedContract)
        }
    }

    func testPackRejectsMissingComponentsUnpinnedURLsDuplicatesAndInvalidDigests() throws {
        let valid = pack(contract: "parakeet-tdt-v3")
        for change in ["missing", "url", "duplicate", "digest"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
            var assets = try XCTUnwrap(object["artifacts"] as? [[String: Any]])
            switch change {
            case "missing": assets.removeAll { ($0["fileName"] as? String)?.hasPrefix("Decoder.mlmodelc/") == true }
            case "url": assets[0]["downloadURL"] = "https://huggingface.co/another/publisher/resolve/\(valid.revision)/foreign.bin"
            case "duplicate": assets.append(assets[0])
            default: assets[0]["sha256"] = "invalid"
            }
            object["artifacts"] = assets
            XCTAssertThrowsError(try ParakeetModelPack.decode(JSONSerialization.data(withJSONObject: object)), change)
        }
    }

    private func pack(contract: String, suffix: String = "0") -> ModelManifest {
        let revision = String(repeating: suffix == "0" ? "a" : "b", count: 40)
        let repository = URL(string: "https://huggingface.co/community/compatible-pack-\(suffix)")!
        let joint = contract == "parakeet-tdt-v2" ? "JointDecision" : "JointDecisionv3"
        let paths = ["Decoder", "Encoder", "Preprocessor", joint].flatMap { name in
            ["analytics/coremldata.bin", "coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" }
        } + ["parakeet_vocab.json"]
        return ModelManifest(modelID: "community-pack-\(suffix)", purpose: .speechRecognition,
            upstreamRepository: repository, revision: revision, licenseIdentifier: "CC0-1.0",
            licenseNotice: "Original synthetic integrity fixture; not inference weights.",
            runtimeVersion: ParakeetModelPack.runtimeVersion, sampleRate: 16_000, featureDimension: 128,
            artifacts: paths.map { path in
                let bytes = Self.bytes(path)
                return .init(role: .coreMLAsset, fileName: path, byteCount: Int64(bytes.count),
                    sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                    downloadURL: repository.appendingPathComponent("resolve/\(revision)/\(path)"),
                    digestProvenance: .independentlyDownloaded)
            }, parakeetConfiguration: .init(decoderContract: contract))
    }

    private nonisolated static func bytes(_ path: String) -> Data { Data("Original model-pack integrity fixture \(path)".utf8) }
}
