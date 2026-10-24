import Foundation
import XCTest
@testable import LocalMinutesModels

// Pure adapter-readiness policy only. Fixture metadata is not inference proof;
// actual native recognizer/template tests remain independent mandatory gates.
final class ModelRuntimeCompatibilityTests: XCTestCase {
    private let available: Set<HuggingFaceRuntimeProfile> = [.streamingZipformerONNX, .whisperGGML, .llamaGGUF]

    private func repository(revision: String = String(repeating: "a", count: 40),
                            type: String? = nil, architectures: [String] = [],
                            files: [HuggingFaceModelFile] = []) throws -> HuggingFaceModelRepository {
        HuggingFaceModelRepository(id: try HuggingFaceRepositoryID(input: "arbitrary-publisher/model"),
            revision: revision, files: files, licenseIdentifier: "apache-2.0", cardMarkdown: "# Public synthetic fixture",
            pipelineTag: nil, libraryName: nil, modelType: type, architectures: architectures,
            isGated: false, contextConfiguration: nil)
    }
    private func file(_ name: String, bytes: Int64 = 128,
                      sha: String = String(repeating: "b", count: 64)) -> HuggingFaceModelFile {
        HuggingFaceModelFile(fileName: name, byteCount: bytes, sha256: sha,
            downloadURL: URL(string: "https://huggingface.co/arbitrary-publisher/model/resolve/\(String(repeating: "a", count: 40))/\(name)")!)
    }
    private func format(_ profile: HuggingFaceRuntimeProfile, files: [HuggingFaceModelFile],
                        status: HuggingFaceCompatibilityStatus = .supported) -> HuggingFaceCompatibilityAssessment {
        .init(status: status, profile: profile, selectedFiles: files,
            totalBytes: files.reduce(0) { $0 + ($1.byteCount ?? 0) },
            reasons: ["Metadata format fixture; not runtime validation."], suggestedRepositories: [])
    }
    private func pinnedFiles() -> [HuggingFaceModelFile] {
        StreamingEnglishModel.manifest.artifacts.map {
            HuggingFaceModelFile(fileName: $0.fileName, byteCount: $0.byteCount,
                sha256: $0.sha256, downloadURL: $0.downloadURL)
        }
    }

    func testOnlyTheRealPinnedStreamingZipformerRevisionAndCompleteArtifactTuplesAreReady() throws {
        let files = pinnedFiles()
        let known = try repository(revision: StreamingEnglishModel.manifest.revision, type: "zipformer", files: files)
        let assessed = ModelRuntimeCompatibility.assess(repository: known,
            format: format(.streamingZipformerONNX, files: files), availableProfiles: available)
        XCTAssertEqual(assessed.status, .supported)
        XCTAssertEqual(assessed.selectedFiles, files)
        let changedRevision = try repository(type: "zipformer", files: files)
        XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: changedRevision,
            format: format(.streamingZipformerONNX, files: files), availableProfiles: available).status, .unsupported)
    }

    func testChangedZipformerHashSizeNameOrMissingArtifactCannotBeEquippedAsReady() throws {
        let original = pinnedFiles()
        let variants: [[HuggingFaceModelFile]] = [
            [file(original[0].fileName, bytes: original[0].byteCount!, sha: String(repeating: "c", count: 64))] + Array(original.dropFirst()),
            [file(original[0].fileName, bytes: original[0].byteCount! + 1, sha: original[0].sha256!)] + Array(original.dropFirst()),
            [file("different-encoder.onnx", bytes: original[0].byteCount!, sha: original[0].sha256!)] + Array(original.dropFirst()),
            Array(original.dropLast())
        ]
        for files in variants {
            let repo = try repository(revision: StreamingEnglishModel.manifest.revision, type: "zipformer", files: files)
            let result = ModelRuntimeCompatibility.assess(repository: repo,
                format: format(.streamingZipformerONNX, files: files), availableProfiles: available)
            XCTAssertEqual(result.status, .unsupported)
            XCTAssertFalse(result.reasons.isEmpty)
        }
    }

    func testGGUFRuntimeAcceptsReviewedQwenAndPhiArchitecturesButRejectsUnknownChatFamilies() throws {
        let files = [file("chosen.gguf")]
        for type in ["qwen2", "phi3"] {
            let repo = try repository(type: type, files: files)
            XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: repo,
                format: format(.llamaGGUF, files: files), availableProfiles: available).status, .supported)
        }
        for type in ["llama", "mistral", "unreviewed"] {
            let repo = try repository(type: type, files: files)
            XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: repo,
                format: format(.llamaGGUF, files: files), availableProfiles: available).status, .unsupported)
        }
        let unknown = try repository(files: files)
        XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: unknown,
            format: format(.llamaGGUF, files: files), availableProfiles: available).status, .unverified)
        let nested = [file("quant/chosen.gguf")]
        XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: try repository(type: "phi3", files: nested),
            format: format(.llamaGGUF, files: nested), availableProfiles: available).status, .unsupported,
            "Do not advertise nested GGUF readiness while the loader requires a root-level remote file")
    }

    func testWhisperVariantsUseActualAvailableEngineWithoutRestrictingPublisherOrClaimingQuality() throws {
        for name in ["ggml-tiny.en.bin", "ggml-base.bin", "ggml-small.en-q5_1.bin"] {
            let files = [file(name)]
            let repo = try repository(type: "whisper", files: files)
            let candidate = format(.whisperGGML, files: files, status: .plannedRuntime)
            let ready = ModelRuntimeCompatibility.assess(repository: repo, format: candidate, availableProfiles: available)
            XCTAssertEqual(ready.status, .supported)
            XCTAssertEqual(ready.selectedFiles.map(\.fileName), [name])
            let absent = ModelRuntimeCompatibility.assess(repository: repo, format: candidate,
                availableProfiles: [.llamaGGUF, .streamingZipformerONNX])
            XCTAssertEqual(absent.status, .plannedRuntime)
        }
    }

    func testMissingCompiledEngineCannotAdvertiseSupportedEvenWithCorrectPinnedFormat() throws {
        let files = pinnedFiles()
        let repo = try repository(revision: StreamingEnglishModel.manifest.revision, type: "zipformer", files: files)
        let result = ModelRuntimeCompatibility.assess(repository: repo,
            format: format(.streamingZipformerONNX, files: files), availableProfiles: [])
        XCTAssertEqual(result.status, .plannedRuntime)
    }

    func testRuntimePolicyNeverUpgradesBlockedOrUnverifiedMetadata() throws {
        let files = [file("ggml-tiny.en.bin")]
        let repo = try repository(type: "whisper", files: files)
        let blocked: [HuggingFaceCompatibilityStatus] = [.unverified, .tooLarge, .gated, .conversionRequired, .unsupported, .selectionRequired]
        for status in blocked {
            let original = format(.whisperGGML, files: files, status: status)
            XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: repo, format: original,
                availableProfiles: available), original)
        }
    }
}
