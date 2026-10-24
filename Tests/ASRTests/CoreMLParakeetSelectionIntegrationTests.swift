import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
@testable import LocalMinutesTranscription

@MainActor
final class CoreMLParakeetSelectionIntegrationTests: XCTestCase {
    func testActualNativeInstallationEquipsAndReopensWithoutChangingIndependentSummarySlot() async throws {
        let fixture = try CoreMLParakeetFixture.load()
        let root = try CoreMLParakeetFixture.temporaryRoot("equip")
        defer { try? CoreMLParakeetFixture.remove(root, suffix: "equip") }
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
        let native = try await models.importDirectory(fixture.directory, manifest: ParakeetCoreMLModel.manifest)
        // The summary bytes are only an installer/selection boundary fixture;
        // this test does not claim summary inference from a synthetic GGUF.
        let summarySource = root.appendingPathComponent("SummaryImport")
        try FileManager.default.createDirectory(at: summarySource, withIntermediateDirectories: false)
        let summaryBytes = Data("Original public selection-only fixture".utf8)
        let summaryDigest = SHA256.hash(data: summaryBytes).map { String(format: "%02x", $0) }.joined()
        try summaryBytes.write(to: summarySource.appendingPathComponent("selection.gguf"))
        let summary = ModelManifest(modelID: "summary-selection-fixture", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/public-fixtures/summary")!,
            revision: String(repeating: "b", count: 40), licenseIdentifier: "CC0-1.0",
            licenseNotice: "Original synthetic metadata fixture; no model inference claim.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary,
                fileName: "selection.gguf", byteCount: Int64(summaryBytes.count), sha256: summaryDigest,
                downloadURL: URL(string: "https://huggingface.co/public-fixtures/summary/resolve/" + String(repeating: "b", count: 40) + "/selection.gguf")!,
                digestProvenance: .independentlyDownloaded)])
        _ = try await models.importDirectory(summarySource, manifest: summary)
        let selectionRoot = root.appendingPathComponent("Selections")
        let choices = ModelSelectionStore(rootURL: selectionRoot, models: models,
            availableProfiles: [.parakeetTDTCoreML, .llamaGGUF], canChangeSelection: { true })
        let summaryChoice = try await choices.select(manifest: summary, profile: .llamaGGUF, for: .summary)
        var selected: StoredModelSelection?
        do {
            selected = try await choices.select(manifest: native.manifest, profile: .parakeetTDTCoreML,
                                                for: .speechRecognition)
        } catch { XCTFail("An installed exact native model must be equippable through the real selection authority: \(type(of: error))") }
        XCTAssertEqual(selected?.manifest, native.manifest)
        XCTAssertEqual(selected?.installationID, native.installationID)
        XCTAssertEqual(selected?.profile, .parakeetTDTCoreML)
        let reopened = ModelSelectionStore(rootURL: selectionRoot, models: models,
            availableProfiles: [.parakeetTDTCoreML, .llamaGGUF], canChangeSelection: { true })
        let speech = try await reopened.selected(for: .speechRecognition)
        let resolved = try await reopened.resolve(for: .speechRecognition)
        let retainedSummary = try await reopened.selected(for: .summary)
        XCTAssertEqual(speech?.manifest, native.manifest)
        XCTAssertEqual(speech?.installationID, native.installationID)
        XCTAssertEqual(resolved, native)
        XCTAssertEqual(retainedSummary, summaryChoice)
        if selected != nil {
            try await reopened.clear(for: .speechRecognition)
            let unequipped = try await reopened.selected(for: .speechRecognition)
            let independentSummary = try await reopened.selected(for: .summary)
            let installedStillPresent = try await models.current(modelID: native.manifest.modelID)
            XCTAssertNil(unequipped); XCTAssertEqual(independentSummary, summaryChoice)
            XCTAssertEqual(installedStillPresent, native, "Unequip must not erase model or summary data")
        }
    }
}
