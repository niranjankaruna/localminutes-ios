import Foundation
import XCTest
@testable import LocalMinutesModels

final class ModelCatalogTests: XCTestCase {
    func testEveryVariantCarriesItsPublishedMaximumAndOnlyQwen4BNeedsYarn() throws {
        let expected = [
            "qwen2.5-0.5b-instruct-q4_k_m": 32_768, "qwen2.5-1.5b-instruct-q4_k_m": 32_768,
            "qwen3-0.6b-q8_0": 32_768, "qwen3-1.7b-q8_0": 32_768,
            "qwen3-4b-q4_k_m": 131_072, "qwen3-4b-instruct-2507-q4_k_m": 262_144,
            "phi3-mini-4k-instruct-q4": 4_096, "phi4-mini-instruct-q4_k_m": 131_072,
            "gemma3-1b-it-qat-q4_0": 32_768, "gemma3-4b-it-qat-q4_0": 131_072,
            "gemma4-e2b-it-qat-q4_0": 131_072, "gemma4-e4b-it-qat-q4_0": 131_072
        ]
        for variant in ModelCatalog.summaryFamilies.flatMap(\.variants) {
            let context = try XCTUnwrap(variant.contextWindow)
            XCTAssertEqual(context.maximumTokens, expected[variant.id])
            XCTAssertTrue(context.isSupported)
            let output = variant.manifest.summaryConfiguration?.family == .phi3 ? 2_048 :
                (["qwen25", "gemma3"].contains(variant.manifest.summaryConfiguration?.family.rawValue ?? "") ? 8_192 : 16_384)
            XCTAssertEqual(context.outputTokenLimit, output)
            XCTAssertLessThan(output, context.maximumTokens)
            XCTAssertEqual(variant.contextSourceURL?.scheme, "https")
            XCTAssertEqual(context.yarnOriginalContextTokens, variant.id == "qwen3-4b-q4_k_m" ? 32_768 : nil)
            XCTAssertEqual(context.allocationTokens(requiredTokens: 1_000), 1_024)
            XCTAssertEqual(context.allocationTokens(requiredTokens: context.maximumTokens), context.maximumTokens)
            XCTAssertNil(context.allocationTokens(requiredTokens: context.maximumTokens + 1))
        }
    }

    func testInstalledManifestsWithoutContextMetadataResolveCurrentSettingsWithoutChangingWeights() throws {
        for variant in ModelCatalog.summaryFamilies.flatMap(\.variants) {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(variant.manifest)) as? [String: Any])
            var profile = try XCTUnwrap(object["summaryConfiguration"] as? [String: Any])
            profile.removeValue(forKey: "contextWindow")
            object["summaryConfiguration"] = profile
            let old = try JSONDecoder().decode(ModelManifest.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(old.summaryConfiguration?.contextWindow)
            XCTAssertTrue(variant.matches(old))
            XCTAssertEqual(ModelCatalog.summaryConfiguration(for: old)?.contextWindow, variant.contextWindow)
            XCTAssertEqual(old.artifacts, variant.manifest.artifacts)
        }
    }

    func testInvalidContextProfilesAreRejected() {
        for maximum in [0, -1, 511, 262_145, Int.max] {
            XCTAssertFalse(SummaryContextWindow(maximumTokens: maximum).isSupported)
        }
        XCTAssertFalse(SummaryContextWindow(maximumTokens: 131_072, yarnOriginalContextTokens: 4_096).isSupported)
        XCTAssertFalse(SummaryModelConfiguration(family: .gemma3,
            contextWindow: .init(maximumTokens: 131_072, yarnOriginalContextTokens: 32_768)).isSupported)
        for output in [0, -1, 16_385, Int.max] {
            XCTAssertFalse(SummaryContextWindow(maximumTokens: 32_768, maximumOutputTokens: output).isSupported)
        }
        XCTAssertFalse(SummaryContextWindow(maximumTokens: 4_096, maximumOutputTokens: 4_096).isSupported)
        XCTAssertFalse(SummaryModelConfiguration(family: .qwen25,
            contextWindow: .init(maximumTokens: 32_768, maximumOutputTokens: 16_384)).isSupported)
    }

    func testBundledCatalogLoadsAllRequestedFamiliesWithRegisteredContracts() throws {
        XCTAssertNil(ModelCatalog.loadError)
        let families = ModelCatalog.families(for: .summary)
        XCTAssertEqual(families.map(\.id), ["qwen25", "qwen3", "phi3", "phi4", "gemma3", "gemma4"])
        XCTAssertEqual(families.map { $0.variants.count }, [2, 4, 1, 1, 2, 2])
        let variants = families.flatMap(\.variants)
        XCTAssertEqual(Set(variants.map(\.id)).count, 12)
        for variant in variants {
            XCTAssertEqual(variant.id, variant.manifest.modelID)
            XCTAssertEqual(variant.profile, .llamaGGUF)
            XCTAssertTrue(ModelRuntimeContracts.supports(variant.manifest, profile: variant.profile))
            XCTAssertEqual(variant.manifest.runtimeVersion, SummaryModelConfiguration.runtimeVersion)
            XCTAssertEqual(variant.manifest.artifacts.count, 1)
            XCTAssertGreaterThan(variant.downloadBytes, 0)
            XCTAssertEqual(variant.manifest.upstreamRepository.host, "huggingface.co")
        }
        let qwen = try XCTUnwrap(families.first { $0.id == "qwen25" })
        XCTAssertEqual(qwen.variants.map(\.title), ["0.5B", "1.5B"])
        XCTAssertEqual(ModelCatalog.variant(id: "qwen3-4b-instruct-2507-q4_k_m")?
            .manifest.summaryConfiguration?.variant, .qwen3Instruct2507)
    }

    func testSpeechCatalogContainsOnlyV2AndV3EvenWhenExtraPacksAreSupplied() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Parakeet/parakeet-v3.modelpack.json")
        let v3 = try ParakeetModelPack.decode(Data(contentsOf: fixture))
        let families = ModelCatalog.families(for: .speechRecognition,
            speechPacks: [v3, v3, ParakeetCoreMLModel.manifest])
        XCTAssertEqual(families.map(\.title), ["Parakeet v2", "Parakeet v3"])
        XCTAssertEqual(families.map { $0.variants.count }, [1, 1])
        XCTAssertEqual(families[0].variants[0].manifest, ParakeetCoreMLModel.manifest)
        XCTAssertEqual(families[1].variants[0].manifest, v3)
    }

    func testLegacyWeightsMatchWithoutLosingOriginalManifestProvenance() throws {
        let variant = try XCTUnwrap(ModelCatalog.variant(id: "phi3-mini-4k-instruct-q4"))
        let model = variant.manifest
        let artifact = try XCTUnwrap(model.artifacts.first)
        let legacyArtifact = ModelArtifact(role: artifact.role, fileName: artifact.fileName,
            byteCount: artifact.byteCount, sha256: artifact.sha256, downloadURL: artifact.downloadURL,
            digestProvenance: .independentlyDownloaded)
        let legacy = ModelManifest(modelID: "legacy-phi", purpose: model.purpose,
            upstreamRepository: model.upstreamRepository, revision: model.revision,
            licenseIdentifier: model.licenseIdentifier, licenseNotice: "Original legacy attribution",
            runtimeVersion: "llama.cpp-b5046", artifacts: [legacyArtifact])
        XCTAssertTrue(variant.matches(legacy))
        XCTAssertNil(legacy.summaryConfiguration)
        XCTAssertEqual(legacy.artifacts[0].digestProvenance, .independentlyDownloaded)
        let changedArtifact = ModelArtifact(role: artifact.role, fileName: artifact.fileName,
            byteCount: artifact.byteCount, sha256: String(repeating: "0", count: 64),
            downloadURL: artifact.downloadURL, digestProvenance: .upstreamReported)
        let changed = ModelManifest(modelID: legacy.modelID, purpose: legacy.purpose,
            upstreamRepository: legacy.upstreamRepository, revision: legacy.revision,
            licenseIdentifier: legacy.licenseIdentifier, licenseNotice: legacy.licenseNotice,
            runtimeVersion: legacy.runtimeVersion, artifacts: [changedArtifact])
        XCTAssertFalse(variant.matches(changed), "A similar display name never equates different weights")
    }

    func testCatalogRejectsMutableRevisionsTraversalAndWrongFamilyProfiles() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Models/Resources/SummaryCatalog.json")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        for (field, badValue) in [("revision", "main"), ("fileName", "../model.gguf"),
                                  ("repository", "individual/unreviewed"), ("sha256", "invalid"),
                                  ("variant", "qwen3Instruct2507")] {
            var object = original
            var families = try XCTUnwrap(object["families"] as? [[String: Any]])
            var variants = try XCTUnwrap(families[0]["variants"] as? [[String: Any]])
            variants[0][field] = badValue
            families[0]["variants"] = variants; object["families"] = families
            XCTAssertThrowsError(try ModelCatalog.decode(JSONSerialization.data(withJSONObject: object)), field)
        }
    }
}
