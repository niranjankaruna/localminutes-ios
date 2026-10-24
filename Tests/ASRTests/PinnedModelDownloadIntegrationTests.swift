import CryptoKit
import Foundation
import XCTest
import LocalMinutesModels
import LocalMinutesTranscription

/// Mandatory production-adapter integration. This always downloads the actual
/// four pinned speech artifacts; there is no opt-in flag, cache substitute,
/// URLProtocol double, mocked inference, or skipped network result.
@MainActor
final class PinnedModelDownloadIntegrationTests: XCTestCase {
    func testActualPinnedHTTPSDownloadInstallsReopensImportsAndRecognizesUnderLease() async throws {
        let parent = FileManager.default.temporaryDirectory.standardizedFileURL
        let id = UUID()
        let root = parent.appendingPathComponent("localminutes-pinned-download-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer {
            // Remove only this invocation's exact UUID-owned temporary tree.
            if root.deletingLastPathComponent().standardizedFileURL.path == parent.path,
               root.lastPathComponent == "localminutes-pinned-download-\(id.uuidString)" {
                do { try FileManager.default.removeItem(at: root) }
                catch { XCTFail("Owned integration fixture cleanup failed") }
            } else { XCTFail("Unsafe integration fixture cleanup target") }
        }

        let manifest = StreamingEnglishModel.manifest
        XCTAssertEqual(manifest.revision, "672fbf1b30579d6585301139bb363f42a0ad4a24")
        XCTAssertEqual(manifest.artifacts.count, 4)
        XCTAssertEqual(manifest.artifacts.reduce(Int64(0)) { $0 + $1.byteCount }, 72_654_782)
        let storage = root.appendingPathComponent("Models", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 75
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        // Match the production app's reviewed distribution hosts. A new real
        // redirect must fail this gate before any allowlist change is made.
        let transport = HTTPSModelTransport(stagingRootURL: storage.appendingPathComponent(".staging"),
            allowedHosts: ["huggingface.co", "us.aws.cdn.hf.co", "cdn-lfs.huggingface.co",
                           "cdn-lfs-us-1.hf.co", "cas-bridge.xethub.hf.co"],
            configuration: configuration)
        let manager = ModelInstallationManager(rootURL: storage,
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) },
            downloader: { artifact, destination in try await transport.download(artifact, to: destination) })

        let downloaded: VerifiedModel
        do { downloaded = try await manager.download(manifest) }
        catch {
            XCTFail("Actual pinned production HTTPS download/install failed: \(error)")
            throw error
        }
        try assertVerifiedFiles(downloaded, manifest: manifest, storage: storage)
        let staging = storage.appendingPathComponent(".staging", isDirectory: true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)

        let reopened = ModelInstallationManager(rootURL: storage,
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        let persisted = try await reopened.current(modelID: manifest.modelID)
        XCTAssertEqual(persisted, downloaded, "A fresh authority must rehash/reopen the actual installed selection")
        let lease = try await manager.acquire(modelID: manifest.modelID)
        XCTAssertEqual(lease.model, downloaded)
        var recognizer: CPUStreamingRecognizer?
        do {
            do {
                try await manager.remove(modelID: manifest.modelID)
                XCTFail("The actual installed model was deleted while its inference lease was held")
            } catch {
                XCTAssertEqual(error as? ModelInstallationError, .modelInUse)
            }

            // Exercise Files-style local import with the exact network bytes.
            // Installed manifest.json is not an external weight artifact.
            let source = root.appendingPathComponent("ImportSource", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            for artifact in manifest.artifacts {
                let file = try XCTUnwrap(lease.model.files[artifact.role])
                try FileManager.default.copyItem(at: file, to: source.appendingPathComponent(artifact.fileName))
            }
            let importedStorage = root.appendingPathComponent("ImportedModels", isDirectory: true)
            let importer = ModelInstallationManager(rootURL: importedStorage,
                availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
            let imported = try await importer.importDirectory(source, manifest: manifest)
            try assertVerifiedFiles(imported, manifest: manifest, storage: importedStorage)
            XCTAssertNotEqual(imported.installationID, downloaded.installationID)
            let importedReopen = ModelInstallationManager(rootURL: importedStorage,
                availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
            let importedCurrent = try await importedReopen.current(modelID: manifest.modelID)
            XCTAssertEqual(importedCurrent, imported)
            let originalCurrent = try await manager.current(modelID: manifest.modelID)
            XCTAssertEqual(originalCurrent, downloaded,
                           "Import elsewhere must not retarget or modify the held installation")

            let files = StreamingASRModelFiles(
                encoder: try XCTUnwrap(lease.model.files[.encoder]),
                decoder: try XCTUnwrap(lease.model.files[.decoder]),
                joiner: try XCTUnwrap(lease.model.files[.joiner]),
                tokens: try XCTUnwrap(lease.model.files[.tokens]),
                revision: lease.model.manifest.revision,
                runtimeVersion: lease.model.manifest.runtimeVersion)
            let native = CPUStreamingRecognizer(files: files)
            recognizer = native
            try await native.load()
            let ready = await native.snapshot()
            XCTAssertEqual(ready.phase, .ready)
            XCTAssertEqual(ready.provider, .cpu)
            XCTAssertEqual(ready.modelRevision, manifest.revision)
            XCTAssertEqual(ready.runtimeVersion, "1.13.8")
            let speech = try NativeASRFixture.load()
            try await native.start(epochID: UUID())
            for offset in stride(from: 0, to: speech.samples.count, by: 3_200) {
                _ = try await native.accept(samples: Array(speech.samples[offset..<min(offset + 3_200, speech.samples.count)]),
                                            sourceStartSample: Int64(offset))
            }
            let final = try await native.finish()
            let actualWords = final.text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            let expectedWords = NativeASRFixture.reference.lowercased().split(separator: " ").map(String.init)
            XCTAssertEqual(actualWords, expectedWords,
                           "The just-downloaded leased bytes must run actual CPU inference on licensed speech")
            XCTAssertTrue(final.isFinal)
            let finished = await native.snapshot()
            XCTAssertEqual(finished.acceptedSampleCount, Int64(speech.samples.count))
            await native.unload()
            recognizer = nil
            try await manager.release(lease)
        } catch {
            if let recognizer { await recognizer.unload() }
            try? await manager.release(lease)
            throw error
        }
        try await manager.remove(modelID: manifest.modelID)
        let removed = try await manager.current(modelID: manifest.modelID)
        XCTAssertNil(removed)
        let independentlyImported = try await importedSelection(in: root, manifest: manifest)
        XCTAssertNotNil(independentlyImported, "Deleting one model authority must preserve the independent import")
    }

    private func importedSelection(in root: URL, manifest: ModelManifest) async throws -> VerifiedModel? {
        let importer = ModelInstallationManager(rootURL: root.appendingPathComponent("ImportedModels", isDirectory: true),
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        return try await importer.current(modelID: manifest.modelID)
    }

    private func assertVerifiedFiles(_ model: VerifiedModel, manifest: ModelManifest, storage: URL,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(model.manifest, manifest, file: file, line: line)
        XCTAssertEqual(Set(model.files.keys), [.encoder, .decoder, .joiner, .tokens], file: file, line: line)
        let expected = storage.appendingPathComponent(manifest.modelID, isDirectory: true)
            .appendingPathComponent(manifest.revision, isDirectory: true)
            .appendingPathComponent(model.installationID.uuidString, isDirectory: true)
        XCTAssertEqual(model.directoryURL.standardizedFileURL.path, expected.standardizedFileURL.path,
                       file: file, line: line)
        for artifact in manifest.artifacts {
            let url = try XCTUnwrap(model.files[artifact.role], file: file, line: line)
            XCTAssertEqual(url.standardizedFileURL.path, expected.appendingPathComponent(artifact.fileName).path,
                           file: file, line: line)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            XCTAssertEqual(values.isRegularFile, true, file: file, line: line)
            XCTAssertNotEqual(values.isSymbolicLink, true, file: file, line: line)
            XCTAssertEqual(values.fileSize.map(Int64.init), artifact.byteCount, file: file, line: line)
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            var hasher = SHA256()
            var consumed: Int64 = 0
            while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty {
                consumed += Int64(bytes.count)
                hasher.update(data: bytes)
            }
            XCTAssertEqual(consumed, artifact.byteCount, file: file, line: line)
            XCTAssertEqual(hasher.finalize().map { String(format: "%02x", $0) }.joined(), artifact.sha256,
                           "Independent CryptoKit digest of actual network/imported bytes", file: file, line: line)
        }
        let metadata = try JSONDecoder().decode(ModelManifest.self,
            from: Data(contentsOf: expected.appendingPathComponent("manifest.json")))
        XCTAssertEqual(metadata, manifest, "Pinned revision, licenses and runtime metadata survive publication",
                       file: file, line: line)
    }
}
