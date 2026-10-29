#if os(iOS)
import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutes

/// Real persisted selections, verified installer and fresh app services. The
/// synthetic artifact deliberately fails GGUF validation before native loading;
/// these tests prove routing, never successful model inference.
@MainActor
final class NativeSummarySelectionStartupTests: XCTestCase {
    private var openedStores: [SQLiteMeetingStore] = []

    func testStartupRestoresSpeechWithoutOpeningModelSettings() async throws {
        try await fixture { root, original in
            let selected = try await self.installSpeech(in: original, root: root)
            try await original.store.close()
            let reopened = try self.reopen(root)
            XCTAssertFalse(reopened.speechSelectionChecked)
            await reopened.initialize()
            XCTAssertTrue(reopened.speechSelectionChecked)
            XCTAssertTrue(reopened.speechInstalled)
            await reopened.modelBrowser.refresh()
            XCTAssertEqual(reopened.modelBrowser.equippedSpeechID, selected.modelID)
        }
    }

    func testStartupHonorsExplicitSpeechUnequipAndMissingInstallation() async throws {
        for removed in [false, true] {
            try await fixture { root, original in
                let selected = try await self.installSpeech(in: original, root: root)
                if removed { try await original.models.remove(modelID: selected.modelID) }
                else { try await original.modelSelections.clear(for: .speechRecognition) }
                try await original.store.close()
                let reopened = try self.reopen(root)
                await reopened.initialize()
                XCTAssertTrue(reopened.speechSelectionChecked)
                XCTAssertFalse(reopened.speechInstalled)
                XCTAssertEqual(reopened.modelError != nil, removed)
            }
        }
    }

    func testBrokenSummarySelectionDoesNotHideInstalledSpeech() async throws {
        try await fixture { root, services in
            _ = try await self.installSpeech(in: services, root: root)
            try await services.modelSelections.clear(for: .summary)
            try Data("invalid selection".utf8).write(to: root.appendingPathComponent("ModelSelections/summary.json"))
            await services.initialize()
            XCTAssertTrue(services.speechInstalled)
            await services.refreshModels()
            XCTAssertTrue(services.speechInstalled)
            XCTAssertFalse(services.summaryInstalled)
        }
    }

    private func installSpeech(in services: LocalMinutesServices, root: URL) async throws -> ModelManifest {
        let names = ["Encoder", "Decoder", "JointDecision", "Preprocessor"].flatMap { bundle in
            ["coremldata.bin", "metadata.json", "model.mil"].map { bundle + ".mlmodelc/" + $0 }
        } + ["parakeet_vocab.json"]
        let input = root.appendingPathComponent("SpeechInput")
        let revision = String(repeating: "d", count: 40)
        let repository = URL(string: "https://huggingface.co/example/speech-startup")!
        let artifacts = try names.map { name -> ModelArtifact in
            let bytes = Data("Synthetic speech selection fixture: \(name)".utf8)
            let file = input.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file)
            return .init(role: .coreMLAsset, fileName: name, byteCount: Int64(bytes.count),
                sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                downloadURL: repository.appendingPathComponent("resolve/\(revision)/\(name)"),
                digestProvenance: .independentlyDownloaded)
        }
        let manifest = ModelManifest(modelID: "speech-startup-test", purpose: .speechRecognition,
            upstreamRepository: repository, revision: revision, licenseIdentifier: "CC0-1.0",
            licenseNotice: "Synthetic installation fixture, not an inference model.",
            runtimeVersion: ParakeetModelPack.runtimeVersion, sampleRate: 16_000, featureDimension: 128,
            artifacts: artifacts, parakeetConfiguration: .init(decoderContract: "parakeet-tdt-v2"))
        _ = try await services.models.importDirectory(input, manifest: manifest)
        _ = try await services.modelSelections.select(manifest: manifest, profile: .parakeetTDTCoreML, for: .speechRecognition)
        return manifest
    }
    func testRetiredSystemSelectionReopensAsUnequippedWithoutBlockingStartup() async throws {
        try await fixture { root, original in
            try await original.modelSelections.clear(for: .summary)
            let pointer = root.appendingPathComponent("ModelSelections/summary.json")
            try Data(#"{"schemaVersion":1,"purpose":"summary","provider":"apple-intelligence-on-device"}"#.utf8).write(to: pointer)
            try await original.store.close()
            let reopened = try self.reopen(root)
            await reopened.initialize()
            await reopened.modelBrowser.refresh()
            XCTAssertEqual(reopened.startup.state, .ready)
            XCTAssertNil(reopened.intelligence)
            XCTAssertFalse(reopened.summaryInstalled)
            XCTAssertNil(reopened.modelError)
            XCTAssertNil(reopened.modelBrowser.equippedSummaryID)
        }
    }

    func testFreshServicesInitializeBindsPersistedAlternativeSummaryInsteadOfDefaultPhi() async throws {
        try await fixture { root, original in
            let selected = try await self.installAndSelect(in: original, root: root)
            try await original.store.close()
            let reopened = try self.reopen(root)
            await reopened.initialize()
            XCTAssertEqual(reopened.startup.state, .ready)
            XCTAssertEqual(try self.boundManifest(reopened.intelligence), selected,
                "Startup must bind the real generation session to the verified persisted selection")
            try await reopened.store.close()
        }
    }

    func testFreshServicesInitializeHonorsExplicitlyClearedSummarySelection() async throws {
        try await fixture { root, original in
            _ = try await self.installAndSelect(in: original, root: root)
            try await original.modelSelections.clear(for: .summary)
            try await original.store.close()
            let reopened = try self.reopen(root)
            await reopened.initialize()
            XCTAssertEqual(reopened.startup.state, .ready)
            XCTAssertNil(reopened.intelligence,
                "An explicit persisted unequip must not resurrect the default Phi generation session")
            try await reopened.store.close()
        }
    }

    func testFreshServicesWithoutSelectionRecordRetainsLegacyDefaultPhiBinding() async throws {
        try await fixture { _, services in
            let hasSelection = try await services.modelSelections.hasSelectionRecord(for: .summary)
            XCTAssertFalse(hasSelection)
            await services.initialize()
            XCTAssertEqual(try self.boundManifest(services.intelligence), LocalMinutesServices.summaryManifest,
                "Absent selection metadata retains the default model and its truthful missing-installation flow")
        }
    }

    func testProductionControllerFirstRequestUsesRestoredSelectionRatherThanCapturingDefaultBeforeStartup() async throws {
        try await fixture { root, original in
            let selected = try await self.installAndSelect(in: original, root: root)
            let meetingID = UUID()
            try await original.store.createMeeting(.init(id: meetingID, title: "Synthetic routing fixture",
                createdAt: Date(timeIntervalSince1970: 1), recordingState: .completed, capturedSampleCount: 16_000))
            try await original.store.appendFinalizedSegments([.init(id: UUID(), meetingID: meetingID,
                sequence: 0, startSample: 0, endSample: 16_000,
                text: "Synthetic source for routing only.", modelRevision: "synthetic-asr")], to: meetingID)
            try await original.store.close()
            let reopened = try self.reopen(root)
            let controller = MeetingIntelligenceController(services: reopened, meetingID: meetingID)
            // No manual refresh or initialization: use the real first-button path.
            controller.generateSummary()
            for _ in 0..<500 {
                if !controller.isRunning { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(controller.isRunning, "Integrity rejection must settle without inference")
            XCTAssertFalse(controller.modelRequired,
                "The selected installed artifact must reach integrity validation; absent default Phi must never be acquired")
            XCTAssertNotNil(controller.errorMessage,
                "Synthetic non-GGUF bytes must fail closed, never produce generated content")
            XCTAssertNil(controller.summary)
            XCTAssertEqual(try self.boundManifest(reopened.intelligence), selected)
            XCTAssertNil(reopened.heavyAdmission?.snapshot().lease)
            try await reopened.store.close()
        }
    }

    func testProductionControllerWithRestoredUnequipShowsModelRequiredWithoutResurrectingPhi() async throws {
        try await fixture { root, original in
            try await original.modelSelections.clear(for: .summary)
            let meetingID = UUID()
            try await original.store.createMeeting(.init(id: meetingID, title: "Synthetic unequipped fixture",
                createdAt: Date(timeIntervalSince1970: 1), recordingState: .completed, capturedSampleCount: 0))
            try await original.store.close()
            let reopened = try self.reopen(root)
            let controller = MeetingIntelligenceController(services: reopened, meetingID: meetingID)
            controller.generateSummary()
            for _ in 0..<500 {
                if !controller.isRunning { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(controller.isRunning)
            XCTAssertTrue(controller.modelRequired,
                "An explicitly unequipped summary needs the download/equip guidance on the real controller path")
            XCTAssertNil(reopened.intelligence)
            XCTAssertNil(controller.summary)
            XCTAssertNil(reopened.heavyAdmission?.snapshot().lease)
        }
    }

    /// Observe the actual private dependency without adding a production test
    /// setter or replacing the production session/runtime with a fake.
    private func boundManifest(_ session: IntelligenceSession?) throws -> ModelManifest {
        let session = try XCTUnwrap(session, "An equipped/default selection needs a generation session")
        return try XCTUnwrap(Mirror(reflecting: session).children.first(where: { $0.label == "manifest" })?.value as? ModelManifest,
            "Inspect the manifest actually retained by IntelligenceSession, not the selection file")
    }

    private func installAndSelect(in services: LocalMinutesServices, root: URL) async throws -> ModelManifest {
        let bytes = Data("Synthetic routing artifact: intentionally not a GGUF model.".utf8)
        let input = root.appendingPathComponent("SyntheticRoutingInput", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try bytes.write(to: input.appendingPathComponent("routing.gguf"))
        let revision = String(repeating: "c", count: 40)
        let repository = URL(string: "https://huggingface.co/example/summary-startup-routing")!
        let manifest = ModelManifest(modelID: "native-summary-startup-routing", purpose: .summary,
            upstreamRepository: repository, revision: revision, licenseIdentifier: "MIT",
            licenseNotice: "Original synthetic routing fixture; not an inference model.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary, fileName: "routing.gguf",
                byteCount: Int64(bytes.count), sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                downloadURL: repository.appendingPathComponent("resolve/\(revision)/routing.gguf"),
                digestProvenance: .upstreamReported)])
        _ = try await services.models.importDirectory(input, manifest: manifest)
        _ = try await services.modelSelections.select(manifest: manifest, profile: .llamaGGUF, for: .summary)
        return manifest
    }

    private func fixture(_ body: @MainActor (URL, LocalMinutesServices) async throws -> Void) async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = parent.appendingPathComponent("localminutes-summary-startup-\(UUID().uuidString)", isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root)
        openedStores = [services.store]
        do { try await body(root, services) }
        catch {
            for store in openedStores { try? await store.close() }
            openedStores = []
            try? removeOwnedRoot(root, parent: parent)
            throw error
        }
        for store in openedStores { try? await store.close() }
        openedStores = []
        try removeOwnedRoot(root, parent: parent)
    }

    private func reopen(_ root: URL) throws -> LocalMinutesServices {
        let services = try LocalMinutesServices(rootURL: root)
        openedStores.append(services.store)
        return services
    }

    private func removeOwnedRoot(_ root: URL, parent: URL) throws {
        let prefix = "localminutes-summary-startup-"
        guard root.deletingLastPathComponent() == parent,
              root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside the owned routing fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
