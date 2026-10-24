import Foundation
import XCTest
@testable import LocalMinutesModels

/// Metadata/policy only. Real Core ML model loading and speech inference are
/// separate mandatory native cases; these fixtures never supply transcripts.
final class ParakeetCoreMLCatalogTests: XCTestCase {
    private let profileName = "parakeetTDTCoreML"
    private var available: Set<HuggingFaceRuntimeProfile> {
        Set([.streamingZipformerONNX, .whisperGGML, .llamaGGUF] +
            [HuggingFaceRuntimeProfile(rawValue: profileName)].compactMap { $0 })
    }

    func testOriginalNvidiaNeMoModelExplainsNativeConversionAndSuggestsExactCoreMLFamily() throws {
        let source = try repository(id: "nvidia/parakeet-tdt-0.6b-v2",
            revision: String(repeating: "a", count: 40), files: [
                .init(fileName: "parakeet-tdt-0.6b-v2.nemo", byteCount: 2_400_000_000,
                    sha256: String(repeating: "b", count: 64),
                    downloadURL: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2/resolve/\(String(repeating: "a", count: 40))/parakeet-tdt-0.6b-v2.nemo")!)
            ], type: "fastconformer_tdt", library: "nemo")
        let format = source.assessment(for: .speechRecognition, maximumDownloadBytes: Int64.max)
        let assessed = ModelRuntimeCompatibility.assess(repository: source, format: format, availableProfiles: available)
        XCTAssertEqual(assessed.status, .conversionRequired)
        XCTAssertTrue(assessed.suggestedRepositories.contains("FluidInference/parakeet-tdt-0.6b-v2-coreml"))
        XCTAssertTrue(assessed.selectedFiles.isEmpty, "NeMo bytes cannot masquerade as a directly installable Core ML model")
        XCTAssertFalse(assessed.reasons.isEmpty)
    }

    func testCompletePinnedV2CoreMLFilesHaveDedicatedAdapterAndHonestEstimatedPhoneRequirements() throws {
        let model = ParakeetCoreMLModel.manifest
        let files = model.artifacts.map { HuggingFaceModelFile(fileName: $0.fileName,
            byteCount: $0.byteCount, sha256: $0.sha256, downloadURL: $0.downloadURL) }
        let repository = try repository(id: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
            revision: model.revision, files: files, type: "fastconformer_tdt", library: "coreml")
        let format = repository.assessment(for: .speechRecognition, maximumDownloadBytes: Int64.max)
        let result = ModelRuntimeCompatibility.assess(repository: repository, format: format, availableProfiles: available)
        XCTAssertEqual(result.status, .supported)
        XCTAssertEqual(result.profile?.rawValue, profileName)
        XCTAssertEqual(result.selectedFiles.map(\.fileName).sorted(), files.map(\.fileName).sorted())
        XCTAssertEqual(result.totalBytes, 464_413_247)
        XCTAssertTrue(result.reasons.joined(separator: " ").lowercased().contains("core ml"))
        XCTAssertTrue(result.reasons.joined(separator: " ").lowercased().contains("chunk"))
        let resources = repository.resourceAssessment(for: .speechRecognition, contextTokens: 4_096,
            device: .init(freeDiskBytes: 8_000_000_000, totalMemoryBytes: 8_000_000_000,
                          availableAppMemoryBytes: 4_000_000_000))
        XCTAssertEqual(resources.requiredDiskBytes, 464_413_247)
        let low = try XCTUnwrap(resources.estimatedRAMLowerBoundBytes)
        let high = try XCTUnwrap(resources.estimatedRAMUpperBoundBytes)
        XCTAssertGreaterThanOrEqual(low, 800_000_000); XCTAssertGreaterThanOrEqual(high, low)
        XCTAssertEqual(resources.status, .caution, "Publisher RAM estimates cannot certify phone speed or memory")
        XCTAssertTrue(resources.notes.joined(separator: " ").lowercased().contains("estimate"))
        XCTAssertEqual(repository.resourceAssessment(for: .speechRecognition,
            device: .init(freeDiskBytes: 1, totalMemoryBytes: 8_000_000_000,
                          availableAppMemoryBytes: 4_000_000_000)).status, .insufficientStorage)
    }

    func testMissingChangedUnreviewedOrGatedCoreMLAssetsCannotAdvertiseReadyAndONNXCannotUseNativeProfile() throws {
        let model = ParakeetCoreMLModel.manifest
        let files = model.artifacts.map { HuggingFaceModelFile(fileName: $0.fileName,
            byteCount: $0.byteCount, sha256: $0.sha256, downloadURL: $0.downloadURL) }
        let changed = HuggingFaceModelFile(fileName: files[0].fileName, byteCount: files[0].byteCount,
            sha256: String(repeating: "f", count: 64), downloadURL: files[0].downloadURL)
        for (revision, values, gated) in [
            (model.revision, Array(files.dropLast()), false),
            (model.revision, [changed] + Array(files.dropFirst()), false),
            (String(repeating: "e", count: 40), files, false),
            (model.revision, files, true)
        ] {
            let repo = try repository(id: "FluidInference/parakeet-tdt-0.6b-v2-coreml", revision: revision,
                files: values, type: "fastconformer_tdt", library: "coreml", gated: gated)
            let format = repo.assessment(for: .speechRecognition, maximumDownloadBytes: Int64.max)
            XCTAssertNotEqual(ModelRuntimeCompatibility.assess(repository: repo, format: format,
                availableProfiles: available).status, .supported)
        }
        let onnx = try repository(id: "unreviewed/parakeet", revision: model.revision,
            files: [.init(fileName: "encoder.int8.onnx", byteCount: 100,
                sha256: String(repeating: "a", count: 64), downloadURL: files[0].downloadURL)],
            type: "fastconformer_tdt", library: "onnx")
        XCTAssertNotEqual(onnx.assessment(for: .speechRecognition,
            maximumDownloadBytes: Int64.max).profile?.rawValue, profileName)
        let good = try repository(id: "FluidInference/parakeet-tdt-0.6b-v2-coreml", revision: model.revision,
            files: files, type: "fastconformer_tdt", library: "coreml")
        let format = good.assessment(for: .speechRecognition, maximumDownloadBytes: Int64.max)
        XCTAssertNotEqual(ModelRuntimeCompatibility.assess(repository: good, format: format,
            availableProfiles: []).status, .supported, "Missing native code must never advertise a usable engine")
    }

    private func repository(id: String, revision: String, files: [HuggingFaceModelFile],
                            type: String, library: String, gated: Bool = false) throws -> HuggingFaceModelRepository {
        .init(id: try HuggingFaceRepositoryID(input: id), revision: revision, files: files,
            licenseIdentifier: "cc-by-4.0", cardMarkdown: "# Synthetic metadata fixture; no real inference",
            pipelineTag: "automatic-speech-recognition", libraryName: library, modelType: type,
            architectures: ["FastConformerTDT"], isGated: gated, contextConfiguration: nil)
    }
}
