#if os(iOS)
import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutes

/// Real app controller, installer and selection store. Synthetic bytes exercise
/// ownership and deletion without loading a model or using the network.
@MainActor
final class NativeModelCatalogControllerTests: XCTestCase {
    func testCancelledRefreshPreservesInstalledModelsWithoutReportingAnOperationFailure() async throws {
        try await fixture { root, services in
            let model = try await self.install("refresh", in: services, root: root)
            let controller = services.modelBrowser
            await controller.refresh()
            XCTAssertEqual(controller.installed, [model.manifest])
            XCTAssertNil(controller.errorMessage)

            // The main actor cannot start this task before the synchronous cancel.
            // The real installer's inventory scan observes the cancelled task.
            let refresh = Task { await controller.refresh() }
            refresh.cancel()
            await refresh.value

            XCTAssertEqual(controller.installed, [model.manifest])
            XCTAssertNil(controller.errorMessage)
            await controller.refresh()
            XCTAssertEqual(controller.installed, [model.manifest])
            XCTAssertNil(controller.errorMessage)
        }
    }

    func testFirstDefaultSummaryDownloadPersistsUnequippedSelectionBeforeTransfer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogFailFastURLProtocol.self]
        try await fixture(modelConfiguration: configuration) { _, services in
            let controller = services.modelBrowser
            let variant = try XCTUnwrap(controller.families(for: .summary)
                .flatMap(\.variants).first { $0.manifest.modelID == LocalMinutesServices.summaryManifest.modelID })
            let hadSelection = try await services.modelSelections.hasSelectionRecord(for: .summary)
            XCTAssertFalse(hadSelection)
            XCTAssertTrue(controller.canDownload(variant))

            // This is the production download path for the real pinned default;
            // the scoped transport fails immediately without downloading weights.
            controller.download(variant)
            XCTAssertTrue(controller.isWorking)
            XCTAssertEqual(controller.transferManifest, variant.manifest)
            for _ in 0..<500 {
                if !controller.isWorking { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard !controller.isWorking else {
                controller.cancelDownload()
                XCTFail("The fail-fast model transfer did not settle within five seconds.")
                return
            }
            await services.refreshModels()
            await controller.refresh()
            let hasSelection = try await services.modelSelections.hasSelectionRecord(for: .summary)
            let selected = try await services.modelSelections.selected(for: .summary)
            let installed = try await services.models.current(modelID: variant.manifest.modelID)
            XCTAssertTrue(hasSelection, "A first download must disable implicit default selection before transfer begins.")
            XCTAssertNil(selected, "Downloading must never implicitly equip the default model.")
            XCTAssertNil(controller.equippedSummaryID)
            XCTAssertNil(services.intelligence)
            XCTAssertNil(installed)
            XCTAssertNotNil(controller.errorMessage)
        }
    }

    func testRemovingUnselectedVariantDeletesItsBytesAndCachePreservingOtherSelectionAndMeetings() async throws {
        try await fixture { root, services in
            let first = try await self.install("first", in: services, root: root)
            let second = try await self.install("second", in: services, root: root)
            _ = try await services.modelSelections.select(manifest: second.manifest, profile: .llamaGGUF, for: .summary)
            let cache = try self.makePartial(first.manifest, services: services)
            let meetingID = UUID()
            try await services.store.createMeeting(.init(id: meetingID, title: "Preserved meeting",
                createdAt: Date(), recordingState: .completed, capturedSampleCount: 0))
            let controller = services.modelBrowser
            await controller.refresh()
            await controller.remove(first.manifest)
            XCTAssertNil(controller.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: first.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
            let remaining = try await services.models.current(modelID: second.manifest.modelID)
            XCTAssertNotNil(remaining)
            let selected = try await services.modelSelections.selected(for: .summary)
            XCTAssertEqual(selected?.manifest, second.manifest)
            let meeting = try await services.store.meeting(id: meetingID)
            XCTAssertNotNil(meeting)
        }
    }

    func testRemovingEquippedVariantDeletesEveryInstallAndPersistsExplicitUnequip() async throws {
        try await fixture { root, services in
            let original = try await self.install("selected", in: services, root: root)
            let replacement = try await self.install("selected", in: services, root: root)
            _ = try await services.modelSelections.select(manifest: replacement.manifest, profile: .llamaGGUF, for: .summary)
            let cache = try self.makePartial(replacement.manifest, services: services)
            let controller = services.modelBrowser
            await controller.refresh()
            XCTAssertTrue(controller.isEquipped(replacement.manifest))
            await controller.remove(replacement.manifest)
            XCTAssertNil(controller.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: original.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: replacement.directoryURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
            XCTAssertNil(controller.equippedSummaryID)
            let selected = try await services.modelSelections.selected(for: .summary)
            let hasRecord = try await services.modelSelections.hasSelectionRecord(for: .summary)
            XCTAssertNil(selected)
            XCTAssertTrue(hasRecord, "Deletion must not restore the default model on the next launch.")
            XCTAssertTrue(controller.installed.isEmpty)
        }
    }

    func testRemovingPausedDownloadFreesCacheWithoutAnInstalledModel() async throws {
        try await fixture { _, services in
            let manifest = self.manifest("partial")
            let cache = try self.makePartial(manifest, services: services)
            await services.modelBrowser.refresh()
            await services.modelBrowser.remove(manifest)
            XCTAssertNil(services.modelBrowser.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
            let installed = try await services.models.current(modelID: manifest.modelID)
            XCTAssertNil(installed)
        }
    }

    func testLeasePreventsDeletingModelBytesAndReportsTheFailure() async throws {
        try await fixture { root, services in
            let installed = try await self.install("leased", in: services, root: root)
            let lease = try await services.models.acquire(modelID: installed.manifest.modelID)
            await services.modelBrowser.refresh()
            await services.modelBrowser.remove(installed.manifest)
            XCTAssertNotNil(services.modelBrowser.errorMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: installed.directoryURL.path))
            let current = try await services.models.current(modelID: installed.manifest.modelID)
            XCTAssertNotNil(current)
            try await services.models.release(lease)
        }
    }

    func testLegacyIdentityMatchesPinnedBytesAcrossRuntimeAndProvenanceUpdates() async throws {
        try await fixture { root, services in
            let installed = try await self.install("legacy", in: services, root: root)
            let old = installed.manifest
            let candidate = ModelManifest(modelID: "catalogue-replacement-id", purpose: .summary,
                upstreamRepository: old.upstreamRepository, revision: old.revision,
                licenseIdentifier: old.licenseIdentifier, licenseNotice: old.licenseNotice,
                runtimeVersion: "llama.cpp-b11900", artifacts: old.artifacts.map {
                    .init(role: $0.role, fileName: $0.fileName, byteCount: $0.byteCount, sha256: $0.sha256,
                          downloadURL: $0.downloadURL, digestProvenance: .upstreamReported)
                })
            await services.modelBrowser.refresh()
            XCTAssertEqual(services.modelBrowser.installedManifest(for: candidate), old)
            await services.modelBrowser.remove(candidate)
            XCTAssertNil(services.modelBrowser.errorMessage)
            XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directoryURL.path))
        }
    }

    func testAnArbitraryRepositoryCannotBeDownloadedThroughTheCatalogueController() async throws {
        try await fixture { _, services in
            let manifest = self.manifest("not-in-catalogue")
            let variant = ModelCatalogVariant(id: manifest.modelID, title: "Not offered",
                detail: "Synthetic fixture", manifest: manifest, profile: .llamaGGUF)
            XCTAssertFalse(services.modelBrowser.canDownload(variant))
            services.modelBrowser.download(variant)
            XCTAssertFalse(services.modelBrowser.isWorking)
            XCTAssertNil(services.modelBrowser.transferManifest)
        }
    }

    private func manifest(_ name: String) -> ModelManifest {
        let data = Data("Synthetic catalogue deletion fixture \(name).".utf8)
        let repository = URL(string: "https://huggingface.co/example/catalogue-\(name)")!
        let revision = String(repeating: "a", count: 40)
        return ModelManifest(modelID: "catalogue-test-\(name)", purpose: .summary,
            upstreamRepository: repository, revision: revision, licenseIdentifier: "MIT",
            licenseNotice: "Synthetic test data. Not inference weights.", runtimeVersion: "llama.cpp-b5046",
            artifacts: [.init(role: .summary, fileName: "test.gguf", byteCount: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                downloadURL: repository.appendingPathComponent("resolve/\(revision)/test.gguf"),
                digestProvenance: .independentlyDownloaded)])
    }

    private func install(_ name: String, in services: LocalMinutesServices, root: URL) async throws -> VerifiedModel {
        let source = root.appendingPathComponent("input-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("Synthetic catalogue deletion fixture \(name).".utf8).write(to: source.appendingPathComponent("test.gguf"))
        return try await services.models.importDirectory(source, manifest: manifest(name))
    }

    private func makePartial(_ manifest: ModelManifest, services: LocalMinutesServices) throws -> URL {
        let checkpoint = try services.transferFactory.checkpointDirectory(for: manifest.artifacts[0])
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
        try Data("Partial download fixture".utf8).write(to: checkpoint.appendingPathComponent("partial.bin"))
        return checkpoint
    }

    private func fixture(modelConfiguration: URLSessionConfiguration = .ephemeral,
                         _ body: @MainActor (URL, LocalMinutesServices) async throws -> Void) async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("model-catalogue-\(UUID().uuidString)", isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root, modelConfiguration: modelConfiguration)
        do { try await body(root, services) }
        catch {
            try? await services.store.close()
            try? removeOwned(root, parent: parent)
            throw error
        }
        try await services.store.close()
        try removeOwned(root, parent: parent)
    }

    private func removeOwned(_ root: URL, parent: URL) throws {
        let prefix = "model-catalogue-"
        guard root.deletingLastPathComponent() == parent,
              root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refusing cleanup outside the owned catalogue fixture.")
            return
        }
        try FileManager.default.removeItem(at: root)
    }
}

/// Attached only to this test's URLSession configuration. Every request fails
/// synchronously; no mutable global protocol state or real network is involved.
private final class CatalogFailFastURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
#endif
