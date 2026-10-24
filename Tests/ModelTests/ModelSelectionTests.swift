import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
@testable import LocalMinutesModels

/// Nonsense bytes establish real installer/selection filesystem contracts only.
/// They do not establish Whisper, ONNX/GGUF loading or inference quality.
@MainActor
final class ModelSelectionTests: XCTestCase {
    func testInstalledSpeechAndSummarySelectionsAreProtectedAtomicAndSurviveReopen() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let speech = try await h.install(.speechRecognition)
        let summary = try await h.install(.summary)
        let selections = h.selections()
        let chosenSpeech = try await selections.select(manifest: speech.manifest, profile: .streamingZipformerONNX, for: .speechRecognition)
        let chosenSummary = try await selections.select(manifest: summary.manifest, profile: .llamaGGUF, for: .summary)
        XCTAssertEqual(chosenSpeech.installationID, speech.installationID)
        XCTAssertEqual(chosenSummary.installationID, summary.installationID)
        let reopened = h.selections()
        let storedSpeech = try await reopened.selected(for: .speechRecognition)
        let storedSummary = try await reopened.selected(for: .summary)
        XCTAssertEqual(storedSpeech, chosenSpeech); XCTAssertEqual(storedSummary, chosenSummary)
        let resolvedSpeech = try await reopened.resolve(for: .speechRecognition)
        let resolvedSummary = try await reopened.resolve(for: .summary)
        XCTAssertEqual(resolvedSpeech, speech); XCTAssertEqual(resolvedSummary, summary)
        for purpose in [ModelPurpose.speechRecognition, .summary] {
            let pointer = h.pointer(purpose)
            XCTAssertTrue(FileManager.default.fileExists(atPath: pointer.path), "Selections must be actual durable JSON files")
            if FileManager.default.fileExists(atPath: pointer.path) {
                let stored = try JSONDecoder().decode(StoredModelSelection.self, from: Data(contentsOf: pointer))
                XCTAssertEqual(stored.manifest.purpose, purpose)
                let mode = try FileManager.default.attributesOfItem(atPath: pointer.path)[.posixPermissions] as? NSNumber
                XCTAssertEqual(mode?.intValue, 0o600)
                XCTAssertEqual(try pointer.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            }
        }
        if FileManager.default.fileExists(atPath: h.selectionRoot.path) {
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: h.selectionRoot.path)),
                Set(["speechRecognition.json", "summary.json"]), "Atomic staging must not leave partial selections")
        }
    }

    func testMissingSelectionFallsBackButUninstalledAndWrongPurposeCannotBeSelected() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let selections = h.selections()
        let oldSpeech = try await selections.selected(for: .speechRecognition)
        let oldSummary = try await selections.resolve(for: .summary)
        XCTAssertNil(oldSpeech); XCTAssertNil(oldSummary)
        await rejects(.notInstalled) {
            _ = try await selections.select(manifest: h.manifest(.summary), profile: .llamaGGUF, for: .summary)
        }
        let speech = try await h.install(.speechRecognition)
        await rejects(.invalidPurpose) {
            _ = try await selections.select(manifest: speech.manifest, profile: .streamingZipformerONNX, for: .summary)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointer(.summary).path))
    }

    func testUnsupportedWhisperEngineAndWrongProfileCannotReplaceApprovedSelection() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let speech = try await h.install(.speechRecognition)
        let selections = h.selections()
        let before = try await selections.select(manifest: speech.manifest, profile: .streamingZipformerONNX, for: .speechRecognition)
        await rejects(.unavailableRuntime) {
            _ = try await selections.select(manifest: speech.manifest, profile: .whisperGGML, for: .speechRecognition)
        }
        await rejects(.invalidPurpose) {
            _ = try await selections.select(manifest: speech.manifest, profile: .llamaGGUF, for: .speechRecognition)
        }
        let after = try await selections.selected(for: .speechRecognition)
        XCTAssertEqual(after, before)
    }

    func testRealActiveHeavyLeasePreventsSelectionChangeAndKeepsLeasedInstallation() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let original = try await h.install(.summary)
        let gate = HeavyModelAdmission()
        let selections = h.selections { gate.snapshot().phase == .idle }
        let before = try await selections.select(manifest: original.manifest, profile: .llamaGGUF, for: .summary)
        let lease = try await h.manager.acquire(modelID: original.manifest.modelID)
        let boundary = SelectionHeavyBoundary()
        let held = try gate.acquire(purpose: .summary, requestID: UUID(), resource: boundary)
        do {
            await rejects(.selectionInUse) {
                _ = try await selections.select(manifest: original.manifest, profile: .llamaGGUF, for: .summary)
            }
            let after = try await selections.selected(for: .summary)
            XCTAssertEqual(after, before)
            XCTAssertEqual(lease.model, original)
            XCTAssertEqual(gate.snapshot().lease, held)
            try await gate.cancelAndDrain(held)
            try await h.manager.release(lease)
        } catch {
            try? await gate.cancelAndDrain(held); try? await h.manager.release(lease); throw error
        }
    }

    func testChangedManifestAndCorruptInstalledBytesFailClosedAfterReopen() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let installed = try await h.install(.summary)
        let selections = h.selections()
        let approved = try await selections.select(manifest: installed.manifest, profile: .llamaGGUF, for: .summary)
        let changed = h.manifest(.summary, notice: "Different unapproved attribution")
        await rejects(.manifestMismatch) {
            _ = try await selections.select(manifest: changed, profile: .llamaGGUF, for: .summary)
        }
        let after = try await selections.selected(for: .summary)
        XCTAssertEqual(after, approved)
        try Data("corrupt".utf8).write(to: try XCTUnwrap(installed.files[.summary]))
        await rejectsAny { _ = try await h.selections().resolve(for: .summary) }
    }

    func testSelectedGGUFIsOneFileAndONNXSelectionResolvesCompleteCoherentSet() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let speech = try await h.install(.speechRecognition), summary = try await h.install(.summary)
        let selections = h.selections()
        _ = try await selections.select(manifest: summary.manifest, profile: .llamaGGUF, for: .summary)
        _ = try await selections.select(manifest: speech.manifest, profile: .streamingZipformerONNX, for: .speechRecognition)
        let selectedSpeech = try await selections.resolve(for: .speechRecognition)
        let selectedSummary = try await selections.resolve(for: .summary)
        XCTAssertEqual(selectedSummary?.files.count, 1)
        XCTAssertEqual(selectedSpeech?.files.count, 4)
        XCTAssertEqual(Set(selectedSpeech?.files.keys.map { $0 } ?? []), Set([.encoder, .decoder, .joiner, .tokens]))
        XCTAssertEqual(selectedSummary?.manifest.artifacts.map(\.fileName), ["chosen-q4.gguf"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: summary.directoryURL.appendingPathComponent("unused-f16.gguf").path))
    }

    func testEquippingSecondSummaryKeepsFirstInstalledAndNeverChangesSpeechChoice() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let speech = try await h.install(.speechRecognition)
        let first = try await h.install(.summary, modelID: "summary-variant-a")
        let second = try await h.install(.summary, modelID: "summary-variant-b")
        let selections = h.selections()
        let speechChoice = try await selections.select(manifest: speech.manifest, profile: .streamingZipformerONNX, for: .speechRecognition)
        _ = try await selections.select(manifest: first.manifest, profile: .llamaGGUF, for: .summary)
        let secondChoice = try await selections.select(manifest: second.manifest, profile: .llamaGGUF, for: .summary)
        let reopened = h.selections()
        let actualSummary = try await reopened.selected(for: .summary)
        let actualSpeech = try await reopened.selected(for: .speechRecognition)
        let stillFirst = try await h.manager.current(modelID: first.manifest.modelID)
        let stillSecond = try await h.manager.current(modelID: second.manifest.modelID)
        XCTAssertEqual(actualSummary, secondChoice); XCTAssertEqual(actualSpeech, speechChoice)
        XCTAssertEqual(stillFirst, first); XCTAssertEqual(stillSecond, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directoryURL.path))
    }

    func testExplicitUnequipAndSelectedRemovalPersistNoSelectionWithoutLegacyFallback() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let installed = try await h.install(.summary)
        let selections = h.selections()
        let legacy = try await selections.hasSelectionRecord(for: .summary)
        XCTAssertFalse(legacy)
        _ = try await selections.select(manifest: installed.manifest, profile: .llamaGGUF, for: .summary)
        try await selections.clear(for: .summary)
        let reopened = h.selections()
        let explicitNone = try await reopened.hasSelectionRecord(for: .summary)
        let empty = try await reopened.selected(for: .summary)
        let stillInstalled = try await h.manager.current(modelID: installed.manifest.modelID)
        XCTAssertTrue(explicitNone, "Explicit unequip must preserve a tombstone distinct from legacy defaults")
        XCTAssertNil(empty); XCTAssertEqual(stillInstalled, installed)
        _ = try await selections.select(manifest: installed.manifest, profile: .llamaGGUF, for: .summary)
        try await selections.removeSelected(for: .summary)
        let removed = try await h.manager.current(modelID: installed.manifest.modelID)
        let removalMarker = try await h.selections().hasSelectionRecord(for: .summary)
        let noneAfterRemoval = try await h.selections().selected(for: .summary)
        XCTAssertNil(removed); XCTAssertTrue(removalMarker); XCTAssertNil(noneAfterRemoval)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directoryURL.path))
    }

    func testSingleWhisperGGMLSpeechArtifactInstallsAndEquipsOnlyWhenEngineIsAvailable() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let bytes = Data("original synthetic whisper model integrity fixture".utf8)
        let revision = String(repeating: "e", count: 40)
        let manifest = ModelManifest(modelID: "any-publisher-whisper-tiny-q5", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/arbitrary-author/whisper-variants")!,
            revision: revision, licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic fixture, no inference claim",
            runtimeVersion: "whisper.cpp-1.7.5", sampleRate: 16_000,
            artifacts: [.init(role: .whisper, fileName: "ggml-tiny.en-q5_1.bin", byteCount: Int64(bytes.count),
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                downloadURL: URL(string: "https://huggingface.co/arbitrary-author/whisper-variants/resolve/\(revision)/ggml-tiny.en-q5_1.bin")!,
                digestProvenance: .independentlyDownloaded)])
        let source = h.root.appendingPathComponent("WhisperImport")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try bytes.write(to: source.appendingPathComponent("ggml-tiny.en-q5_1.bin"))
        let installed: VerifiedModel
        do { installed = try await h.manager.importDirectory(source, manifest: manifest) }
        catch { return XCTFail("One complete pinned Whisper GGML speech artifact must install; native loading is a separate gate") }
        XCTAssertEqual(installed.files.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(installed.files[.whisper])), bytes)
        await rejects(.unavailableRuntime) {
            _ = try await h.selections().select(manifest: manifest, profile: .whisperGGML, for: .speechRecognition)
        }
        let enabled = ModelSelectionStore(rootURL: h.selectionRoot, models: h.manager,
            availableProfiles: [.whisperGGML], canChangeSelection: { true })
        let equipped = try await enabled.select(manifest: manifest, profile: .whisperGGML, for: .speechRecognition)
        let resolved = try await enabled.resolve(for: .speechRecognition)
        XCTAssertEqual(equipped.installationID, installed.installationID)
        XCTAssertEqual(resolved, installed)
        XCTAssertEqual(resolved?.files.count, 1)
    }

    func testSymlinkSelectionPointerAndLinkedStorageRootDoNotTouchOutsideData() async throws {
        let h = try SelectionFixture(); defer { h.remove() }
        let installed = try await h.install(.summary)
        try FileManager.default.createDirectory(at: h.selectionRoot, withIntermediateDirectories: false)
        let outside = h.root.appendingPathComponent("outside.json")
        let original = Data("outside-owned-sentinel".utf8)
        try original.write(to: outside)
        try FileManager.default.createSymbolicLink(at: h.pointer(.summary), withDestinationURL: outside)
        await rejectsAny {
            _ = try await h.selections().select(manifest: installed.manifest, profile: .llamaGGUF, for: .summary)
        }
        await rejectsAny { _ = try await h.selections().selected(for: .summary) }
        XCTAssertEqual(try Data(contentsOf: outside), original)
        let link = h.root.appendingPathComponent("linked-selections")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: h.selectionRoot)
        let linked = ModelSelectionStore(rootURL: link, models: h.manager, availableProfiles: [.llamaGGUF], canChangeSelection: { true })
        await rejectsAny {
            _ = try await linked.select(manifest: installed.manifest, profile: .llamaGGUF, for: .summary)
        }
        XCTAssertEqual(try Data(contentsOf: outside), original)
    }

    private func rejects(_ expected: ModelSelectionError, _ body: @MainActor () async throws -> Void) async {
        do { try await body(); XCTFail("Selection must reject \(expected)") }
        catch { XCTAssertEqual(error as? ModelSelectionError, expected) }
    }
    private func rejectsAny(_ body: @MainActor () async throws -> Void) async {
        do { try await body(); XCTFail("Unsafe or corrupt selection must fail closed") } catch { }
    }
}

@MainActor
private final class SelectionFixture {
    let root: URL
    let selectionRoot: URL
    let manager: ModelInstallationManager
    private let source: URL
    private let revision = String(repeating: "d", count: 40)

    init() throws {
        root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("localminutes-selection-\(UUID().uuidString)", isDirectory: true)
        selectionRoot = root.appendingPathComponent("Selections", isDirectory: true)
        source = root.appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        manager = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in 100_000_000 })
    }
    func manifest(_ purpose: ModelPurpose, notice: String = "Original synthetic bytes, CC0-1.0", modelID: String? = nil) -> ModelManifest {
        let roles: [(ModelFileRole, String)] = purpose == .summary ? [(.summary, "chosen-q4.gguf")]
            : [(.encoder, "encoder.onnx"), (.decoder, "decoder.onnx"), (.joiner, "joiner.onnx"), (.tokens, "tokens.txt")]
        return ModelManifest(modelID: modelID ?? (purpose == .summary ? "any-publisher-summary" : "any-publisher-speech"),
            purpose: purpose, upstreamRepository: URL(string: "https://huggingface.co/arbitrary-author/arbitrary-model")!,
            revision: revision, licenseIdentifier: "CC0-1.0", licenseNotice: notice,
            runtimeVersion: purpose == .summary ? "llama.cpp-b5046" : "sherpa-onnx-1.13.8",
            sampleRate: purpose == .summary ? nil : 16_000, featureDimension: purpose == .summary ? nil : 80,
            artifacts: roles.map { role, name in
                let data = Data("synthetic selection bytes: \(name)".utf8)
                return ModelArtifact(role: role, fileName: name, byteCount: Int64(data.count),
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    downloadURL: URL(string: "https://huggingface.co/arbitrary-author/arbitrary-model/resolve/\(revision)/\(name)")!,
                    digestProvenance: .independentlyDownloaded)
            })
    }
    func install(_ purpose: ModelPurpose, modelID: String? = nil) async throws -> VerifiedModel {
        let manifest = manifest(purpose, modelID: modelID)
        let directory = source.appendingPathComponent(manifest.modelID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for artifact in manifest.artifacts {
            try Data("synthetic selection bytes: \(artifact.fileName)".utf8).write(to: directory.appendingPathComponent(artifact.fileName))
        }
        return try await manager.importDirectory(directory, manifest: manifest)
    }
    func selections(_ canChange: @escaping @MainActor () -> Bool = { true }) -> ModelSelectionStore {
        ModelSelectionStore(rootURL: selectionRoot, models: manager,
            availableProfiles: [.streamingZipformerONNX, .llamaGGUF], canChangeSelection: canChange)
    }
    func pointer(_ purpose: ModelPurpose) -> URL { selectionRoot.appendingPathComponent(purpose.rawValue + ".json") }
    func remove() {
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-selection-") else { return XCTFail("Unsafe fixture cleanup") }
        do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Owned fixture cleanup failed") }
    }
}

@MainActor
private final class SelectionHeavyBoundary: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}
