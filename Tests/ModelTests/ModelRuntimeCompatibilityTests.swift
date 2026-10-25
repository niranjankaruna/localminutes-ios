import Foundation
import XCTest
@testable import LocalMinutesModels

// Pure adapter-readiness policy only. Fixture metadata is not inference proof;
// actual native recognizer/template tests remain independent mandatory gates.
final class ModelRuntimeCompatibilityTests: XCTestCase {
    private let available: Set<HuggingFaceRuntimeProfile> = [.parakeetTDTCoreML, .llamaGGUF]

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


    func testRuntimePolicyNeverUpgradesBlockedOrUnverifiedMetadata() throws {
        let files = [file("parakeet_vocab.json")]
        let repo = try repository(type: "fastconformer_tdt", files: files)
        let blocked: [HuggingFaceCompatibilityStatus] = [.unverified, .tooLarge, .gated, .conversionRequired, .unsupported, .selectionRequired]
        for status in blocked {
            let original = format(.parakeetTDTCoreML, files: files, status: status)
            XCTAssertEqual(ModelRuntimeCompatibility.assess(repository: repo, format: original,
                availableProfiles: available), original)
        }
    }
}
