import Foundation
import XCTest
@testable import LocalMinutesModels

final class ModelInstallationIdentityTests: XCTestCase {
    private let revision = String(repeating: "a", count: 40)

    private func identity(_ files: [String], repository: String = "example/model",
                          revision: String? = nil, purpose: ModelPurpose = .summary) -> String {
        ModelInstallationIdentity.make(repositoryID: repository, revision: revision ?? self.revision,
            purpose: purpose, repositoryRelativeFiles: files)
    }

    func testDirectoryVariantsWithTheSameBasenameKeepSeparateStableInstallationIdentities() {
        let q4 = identity(["q4/model.gguf"])
        let f16 = identity(["f16/model.gguf"])
        XCTAssertNotEqual(q4, f16, "Downloading another directory variant must not replace an equipped installation")
        XCTAssertEqual(q4, identity(["q4/model.gguf"]))
        XCTAssertTrue(q4.hasPrefix("hf-"))
        let suffix = q4.dropFirst(3)
        XCTAssertEqual(suffix.utf8.count, 32)
        XCTAssertTrue(suffix.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
    }

    func testIdentityIsOrderIndependentAndSeparatesPurposeRevisionAndRepository() {
        let files = ["stream/encoder.bin", "stream/decoder.bin", "stream/joint.bin", "vocabulary.json"]
        let original = identity(files, purpose: .speechRecognition)
        XCTAssertEqual(original, identity(Array(files.reversed()), purpose: .speechRecognition))
        XCTAssertNotEqual(original, identity(files, purpose: .summary))
        XCTAssertNotEqual(original, identity(files, revision: String(repeating: "b", count: 40), purpose: .speechRecognition))
        XCTAssertNotEqual(original, identity(files, repository: "another/model", purpose: .speechRecognition))
    }

    func testIdentityPreservesExactUnicodePathBytesWhileCanonicalInputOrderDoesNotMatter() {
        // Deliberately byte-distinct paths. Identity must not fold these into
        // the same installation, even though Swift String equality is canonical.
        let composed = "caf\u{00e9}/model.gguf"
        let decomposed = "cafe\u{0301}/model.gguf"
        XCTAssertNotEqual(Data(composed.utf8), Data(decomposed.utf8), "Fixture must be byte-distinct")
        XCTAssertNotEqual(identity([composed]), identity([decomposed]))
        XCTAssertEqual(identity([composed, decomposed]), identity([decomposed, composed]),
                       "Sort canonical-equivalent paths by their exact UTF-8 bytes")
        XCTAssertNotEqual(identity([composed, "vocabulary.json"]), identity([decomposed, "vocabulary.json"]))
    }
}
