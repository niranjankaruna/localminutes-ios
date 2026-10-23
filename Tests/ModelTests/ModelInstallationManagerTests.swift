import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesModels

// Nonsense fixture bytes test actual filesystem integrity only. These are not
// ONNX/GGUF models, audio, transcripts, native loading, or inference evidence.
private func modelTestDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private enum ModelFixtureError: Error { case timedOut, networkFailure }

@MainActor
private final class ModelFixture {
    let root: URL
    let source: URL
    let storage: URL
    let bytes: [String: Data]
    let manifest: ModelManifest

    init(revision: String = String(repeating: "a", count: 40), suffix: String = "one") throws {
        let parent = FileManager.default.temporaryDirectory.standardizedFileURL
        let fixtureRoot = parent.appendingPathComponent("localminutes-model-test-\(UUID().uuidString)", isDirectory: true)
        root = fixtureRoot
        source = fixtureRoot.appendingPathComponent("import", isDirectory: true)
        storage = fixtureRoot.appendingPathComponent("persistent-models", isDirectory: true)
        let fixtureBytes = [
            "encoder.onnx": Data("original fixture encoder \(suffix)".utf8),
            "decoder.onnx": Data("original fixture decoder \(suffix)".utf8),
            "joiner.onnx": Data("original fixture joiner \(suffix)".utf8),
            "tokens.txt": Data("fixture-only tokens \(suffix)".utf8)
        ]
        bytes = fixtureBytes
        let names: [(ModelFileRole, String)] = [(.encoder, "encoder.onnx"), (.decoder, "decoder.onnx"),
                                               (.joiner, "joiner.onnx"), (.tokens, "tokens.txt")]
        manifest = ModelManifest(modelID: "fixture-streaming", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/example/original-fixture")!,
            revision: revision, licenseIdentifier: "CC0-1.0",
            licenseNotice: "Original LocalMinutes non-model fixture bytes, dedicated to CC0-1.0.",
            runtimeVersion: "fixture-runtime-1", sampleRate: 16_000, featureDimension: 80,
            artifacts: names.map { role, name in
                let data = fixtureBytes[name]!
                return ModelArtifact(role: role, fileName: name, byteCount: Int64(data.count),
                    sha256: modelTestDigest(data),
                    downloadURL: URL(string: "https://huggingface.co/example/original-fixture/resolve/\(revision)/\(name)")!,
                    digestProvenance: .independentlyDownloaded)
            })
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        for (name, data) in bytes { try data.write(to: source.appendingPathComponent(name)) }
    }

    func manager(availableBytes: Int64 = 100_000_000,
                 downloader: ModelArtifactDownloader? = nil) -> ModelInstallationManager {
        ModelInstallationManager(rootURL: storage, availableBytes: { _ in availableBytes }, downloader: downloader)
    }

    var pointerURL: URL { storage.appendingPathComponent(manifest.modelID).appendingPathComponent("current.json") }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) {
        let parent = FileManager.default.temporaryDirectory.standardizedFileURL
        guard root.deletingLastPathComponent().standardizedFileURL == parent,
              root.lastPathComponent.hasPrefix("localminutes-model-test-") else {
            return XCTFail("Unsafe fixture cleanup target", file: file, line: line)
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned model fixture cleanup failed: \(error)", file: file, line: line) }
    }

    func replacing(artifacts: [ModelArtifact]? = nil, modelID: String? = nil,
                   revision: String? = nil, license: String? = nil) -> ModelManifest {
        // A replacement fixture must pin its URLs to its replacement revision.
        // Preserve every behavioral assertion; do not weaken coherent-set validation.
        let replacementArtifacts = artifacts ?? manifest.artifacts.map { artifact in
            guard let revision else { return artifact }
            return ModelArtifact(role: artifact.role, fileName: artifact.fileName,
                byteCount: artifact.byteCount, sha256: artifact.sha256,
                downloadURL: URL(string: artifact.downloadURL.absoluteString.replacingOccurrences(
                    of: "/resolve/\(manifest.revision)/", with: "/resolve/\(revision)/"))!,
                digestProvenance: artifact.digestProvenance)
        }
        return ModelManifest(modelID: modelID ?? manifest.modelID, purpose: manifest.purpose,
            upstreamRepository: manifest.upstreamRepository, revision: revision ?? manifest.revision,
            licenseIdentifier: license ?? manifest.licenseIdentifier, licenseNotice: manifest.licenseNotice,
            runtimeVersion: manifest.runtimeVersion, sampleRate: manifest.sampleRate,
            featureDimension: manifest.featureDimension, artifacts: replacementArtifacts)
    }

    func assertInstalled(_ handle: VerifiedModel, manifest expected: ModelManifest? = nil,
                         file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = expected ?? manifest
        XCTAssertEqual(handle.manifest, expected, file: file, line: line)
        XCTAssertEqual(handle.files.count, expected.artifacts.count, file: file, line: line)
        let expectedDirectory = storage.appendingPathComponent(expected.modelID, isDirectory: true)
            .appendingPathComponent(expected.revision, isDirectory: true)
            .appendingPathComponent(handle.installationID.uuidString, isDirectory: true)
        XCTAssertEqual(handle.directoryURL.standardizedFileURL, expectedDirectory.standardizedFileURL,
                       "Handle must refer to a persistent immutable installation", file: file, line: line)
        for artifact in expected.artifacts {
            let url = try XCTUnwrap(handle.files[artifact.role], file: file, line: line)
            XCTAssertEqual(url.standardizedFileURL,
                expectedDirectory.appendingPathComponent(artifact.fileName).standardizedFileURL, file: file, line: line)
            let actual = try Data(contentsOf: url)
            XCTAssertEqual(Int64(actual.count), artifact.byteCount, file: file, line: line)
            XCTAssertEqual(modelTestDigest(actual), artifact.sha256, file: file, line: line)
        }
        let stored = try JSONDecoder().decode(ModelManifest.self,
            from: Data(contentsOf: handle.directoryURL.appendingPathComponent("manifest.json")))
        XCTAssertEqual(stored, expected, "Attribution and immutable expected digests must survive installation", file: file, line: line)
    }

    func assertNoStaging(file: StaticString = #filePath, line: UInt = #line) throws {
        let staging = storage.appendingPathComponent(".staging", isDirectory: true)
        if FileManager.default.fileExists(atPath: staging.path) {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty,
                          "No partial model may remain after a settled operation", file: file, line: line)
        }
    }
}

private actor FixtureDownloader {
    let files: [String: Data]
    let failureName: String?
    let heldName: String?
    private(set) var destinations: [URL] = []
    private(set) var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(files: [String: Data], failureName: String? = nil, heldName: String? = nil) {
        self.files = files
        self.failureName = failureName
        self.heldName = heldName
    }

    func download(_ artifact: ModelArtifact, to destination: URL) async throws {
        destinations.append(destination)
        if artifact.fileName == failureName { throw ModelFixtureError.networkFailure }
        if artifact.fileName == heldName {
            waiting = true
            await withCheckedContinuation { continuation = $0 }
            waiting = false
        }
        try Task.checkCancellation()
        guard let data = files[artifact.fileName] else { throw ModelFixtureError.networkFailure }
        try data.write(to: destination)
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

@MainActor
final class ModelInstallationManagerTests: XCTestCase {
    private func expectError(_ expected: ModelInstallationError,
                             file: StaticString = #filePath, line: UInt = #line,
                             _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch let actual as ModelInstallationError { XCTAssertEqual(actual, expected, file: file, line: line) }
        catch { XCTFail("Wrong error category: \(error)", file: file, line: line) }
    }

    private func waitForDownload(_ downloader: FixtureDownloader) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !(await downloader.waiting) {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    func testPinnedSpeechManifestHasOneImmutableCompatibleSetAndHonestDigestProvenance() throws {
        let manifest = StreamingEnglishModel.manifest
        XCTAssertEqual(manifest.revision, "672fbf1b30579d6585301139bb363f42a0ad4a24")
        XCTAssertEqual(manifest.purpose, .speechRecognition)
        XCTAssertEqual(manifest.licenseIdentifier, "Apache-2.0")
        XCTAssertTrue(manifest.licenseNotice.contains("Zengwei"))
        XCTAssertTrue(manifest.licenseNotice.contains("https://www.apache.org/licenses/LICENSE-2.0"))
        XCTAssertEqual(manifest.runtimeVersion, "sherpa-onnx-1.13.8")
        XCTAssertEqual(manifest.sampleRate, 16_000)
        XCTAssertEqual(manifest.featureDimension, 80)
        let expected: [(ModelFileRole, String, Int64, String, ModelDigestProvenance)] = [
            (.encoder, "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 71_083_163,
             "563fde436d16cf7607cf408cd6b30909819d03162652ef389c2450ced3f45ac1", .upstreamReported),
            (.decoder, "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 1_307_236,
             "98da299f471e38bb4e1a8df579b8cc9122d6039576a77e357b3c60f17dd83b02", .upstreamReported),
            (.joiner, "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx", 259_335,
             "d944208d660d67c8d72cd2acaeac971fa5ceb8c80e76c1968148846fedd6e297", .upstreamReported),
            (.tokens, "tokens.txt", 5_048,
             "49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb", .independentlyDownloaded)
        ]
        XCTAssertEqual(manifest.artifacts.count, expected.count)
        for (role, name, size, digest, provenance) in expected {
            let artifact = try XCTUnwrap(manifest.artifacts.first { $0.role == role })
            XCTAssertEqual(artifact.fileName, name)
            XCTAssertEqual(artifact.byteCount, size)
            XCTAssertEqual(artifact.sha256, digest)
            XCTAssertEqual(artifact.digestProvenance, provenance)
            XCTAssertEqual(artifact.downloadURL.scheme, "https")
            XCTAssertEqual(artifact.downloadURL.host, "huggingface.co")
            XCTAssertTrue(artifact.downloadURL.path.contains("/resolve/\(manifest.revision)/"))
        }
        let roundTrip = try JSONDecoder().decode(ModelManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(roundTrip, manifest)
    }

    func testValidLocalImportCopiesHashesAndPersistsLicenseWithoutChangingSource() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let installed = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        try h.assertInstalled(installed)
        for (name, bytes) in h.bytes {
            XCTAssertEqual(try Data(contentsOf: h.source.appendingPathComponent(name)), bytes)
        }
        try h.assertNoStaging()
    }

    func testReopenedManagerReturnsTheSameVerifiedPersistentInstallation() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let first = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        let restored = try await h.manager().current(modelID: h.manifest.modelID)
        XCTAssertEqual(restored, first)
        try h.assertInstalled(try XCTUnwrap(restored))
    }

    func testMissingRequiredFileIsRejectedWithoutPublishingAPointer() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        try FileManager.default.removeItem(at: h.source.appendingPathComponent("encoder.onnx"))
        await expectError(.missingFile("encoder.onnx")) {
            _ = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointerURL.path))
        try h.assertNoStaging()
    }

    func testTruncatedRequiredFileIsRejectedBeforePublishing() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        try Data(h.bytes["decoder.onnx"]!.dropLast()).write(to: h.source.appendingPathComponent("decoder.onnx"))
        await expectError(.sizeMismatch("decoder.onnx")) {
            _ = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointerURL.path))
        try h.assertNoStaging()
    }

    func testSameSizeCorruptionFailsActualSHA256Verification() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let original = h.bytes["joiner.onnx"]!
        let corrupt = Data(repeating: 0x78, count: original.count)
        XCTAssertEqual(corrupt.count, original.count)
        XCTAssertNotEqual(modelTestDigest(corrupt), modelTestDigest(original))
        try corrupt.write(to: h.source.appendingPathComponent("joiner.onnx"))
        await expectError(.checksumMismatch("joiner.onnx")) {
            _ = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        }
        try h.assertNoStaging()
    }

    func testUnexpectedFileCannotBeImportedAlongsideModelWeights() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        try Data("private-content-must-not-copy".utf8).write(to: h.source.appendingPathComponent("meeting.txt"))
        await expectError(.unexpectedFile("meeting.txt")) {
            _ = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointerURL.path))
    }

    func testSymlinkedRequiredFileIsRejectedWithoutReadingOutsideImport() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let outside = h.root.appendingPathComponent("outside.onnx")
        try h.bytes["encoder.onnx"]!.write(to: outside)
        let encoder = h.source.appendingPathComponent("encoder.onnx")
        try FileManager.default.removeItem(at: encoder)
        try FileManager.default.createSymbolicLink(at: encoder, withDestinationURL: outside)
        await expectError(.unsafeFile("encoder.onnx")) {
            _ = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        }
        XCTAssertEqual(try Data(contentsOf: outside), h.bytes["encoder.onnx"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointerURL.path))
    }

    func testUnsafeModelAndArtifactNamesCannotEscapePersistentRoot() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        for unsafeID in ["../outside", "/absolute", "a/b", "a\\b", "", ".", ".."] {
            let manifest = h.replacing(modelID: unsafeID)
            await expectError(.invalidManifest) {
                _ = try await h.manager().importDirectory(h.source, manifest: manifest)
            }
        }
        let valid = h.manifest.artifacts[0]
        for unsafeName in ["../encoder.onnx", "/encoder.onnx", "nested/encoder.onnx", "nested\\encoder.onnx", "manifest.json"] {
            let invalid = ModelArtifact(role: valid.role, fileName: unsafeName, byteCount: valid.byteCount,
                sha256: valid.sha256, downloadURL: valid.downloadURL, digestProvenance: valid.digestProvenance)
            let manifest = h.replacing(artifacts: [invalid] + Array(h.manifest.artifacts.dropFirst()))
            await expectError(.invalidManifest) {
                _ = try await h.manager().importDirectory(h.source, manifest: manifest)
            }
        }
        try h.assertNoStaging()
    }

    func testUnpinnedRevisionMissingLicenseAndMalformedDigestAreRejected() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        for invalid in [h.replacing(revision: "latest"), h.replacing(revision: "main"), h.replacing(license: "")] {
            await expectError(.invalidManifest) {
                _ = try await h.manager().importDirectory(h.source, manifest: invalid)
            }
        }
        let valid = h.manifest.artifacts[0]
        let malformed = ModelArtifact(role: valid.role, fileName: valid.fileName, byteCount: valid.byteCount,
            sha256: "replace-with-checksum", downloadURL: valid.downloadURL, digestProvenance: valid.digestProvenance)
        await expectError(.invalidManifest) {
            _ = try await h.manager().importDirectory(h.source,
                manifest: h.replacing(artifacts: [malformed] + Array(h.manifest.artifacts.dropFirst())))
        }
    }

    func testDuplicateRolesAndDuplicateNamesCannotCreateAmbiguousVerifiedHandle() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let first = h.manifest.artifacts[0]
        let duplicateRole = ModelArtifact(role: first.role, fileName: "other.onnx", byteCount: first.byteCount,
            sha256: first.sha256, downloadURL: first.downloadURL, digestProvenance: first.digestProvenance)
        let duplicateName = ModelArtifact(role: .summary, fileName: first.fileName, byteCount: first.byteCount,
            sha256: first.sha256, downloadURL: first.downloadURL, digestProvenance: first.digestProvenance)
        for duplicate in [duplicateRole, duplicateName] {
            await expectError(.invalidManifest) {
                _ = try await h.manager().importDirectory(h.source,
                    manifest: h.replacing(artifacts: h.manifest.artifacts + [duplicate]))
            }
        }
    }

    func testInsufficientDiskSpaceDoesNotCreatePartialInstallation() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let required = h.manifest.artifacts.reduce(Int64(0)) { $0 + $1.byteCount }
        await expectError(.insufficientSpace) {
            _ = try await h.manager(availableBytes: required - 1).importDirectory(h.source, manifest: h.manifest)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.pointerURL.path))
        try h.assertNoStaging()
    }

    func testDownloadBoundaryWritesOnlyOwnedStagingAndProducesVerifiedFiles() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let source = FixtureDownloader(files: h.bytes)
        let manager = h.manager(downloader: { artifact, destination in
            try await source.download(artifact, to: destination)
        })
        let installed = try await manager.download(h.manifest)
        try h.assertInstalled(installed)
        let destinations = await source.destinations
        XCTAssertEqual(destinations.count, h.manifest.artifacts.count)
        for destination in destinations {
            XCTAssertTrue(destination.standardizedFileURL.path.hasPrefix(
                h.storage.appendingPathComponent(".staging", isDirectory: true).path + "/"))
        }
        try h.assertNoStaging()
    }

    func testDownloadFailurePreservesPreviousPointerAndCleansPartialFiles() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let first = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        let previousPointer = try Data(contentsOf: h.pointerURL)
        let source = FixtureDownloader(files: h.bytes, failureName: "joiner.onnx")
        let replacementManifest = h.replacing(revision: String(repeating: "b", count: 40))
        let manager = h.manager(downloader: { artifact, destination in
            try await source.download(artifact, to: destination)
        })
        await expectError(.downloadFailed) { _ = try await manager.download(replacementManifest) }
        XCTAssertEqual(try Data(contentsOf: h.pointerURL), previousPointer)
        let stillCurrent = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertEqual(stillCurrent, first)
        try h.assertInstalled(first)
        try h.assertNoStaging()
    }

    func testCancelledReplacementLeavesPreviousUsableInstallationAndNoStaging() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let first = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        let pointerBefore = try Data(contentsOf: h.pointerURL)
        let source = FixtureDownloader(files: h.bytes, heldName: "decoder.onnx")
        let replacementManifest = h.replacing(revision: String(repeating: "b", count: 40))
        let manager = h.manager(downloader: { artifact, destination in
            try await source.download(artifact, to: destination)
        })
        let task = Task { try await manager.download(replacementManifest) }
        let waiting = await waitForDownload(source)
        XCTAssertTrue(waiting, "Downloader boundary must be held after staging begins")
        task.cancel()
        await source.release()
        do { _ = try await task.value; XCTFail("Cancelled replacement must not publish success") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation must remain distinguishable from failure: \(error)") }
        XCTAssertEqual(try Data(contentsOf: h.pointerURL), pointerBefore)
        let current = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertEqual(current, first)
        try h.assertInstalled(first)
        try h.assertNoStaging()
    }

    func testInProgressReplacementKeepsCurrentReadableUntilVerifiedAtomicPublication() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let first = try await h.manager().importDirectory(h.source, manifest: h.manifest)
        let replacementManifest = h.replacing(revision: String(repeating: "b", count: 40))
        let source = FixtureDownloader(files: h.bytes, heldName: "tokens.txt")
        let manager = h.manager(downloader: { artifact, destination in
            try await source.download(artifact, to: destination)
        })
        let operation = Task { try await manager.download(replacementManifest) }
        let waiting = await waitForDownload(source)
        XCTAssertTrue(waiting)
        let during = try await h.manager().current(modelID: h.manifest.modelID)
        XCTAssertEqual(during, first, "Partial replacement must never become current")
        await source.release()
        let replacement = try await operation.value
        XCTAssertNotEqual(replacement.installationID, first.installationID)
        try h.assertInstalled(replacement, manifest: replacementManifest)
        let after = try await h.manager().current(modelID: h.manifest.modelID)
        XCTAssertEqual(after, replacement)
        try h.assertInstalled(first)
        try h.assertNoStaging()
    }

    func testFailedImportCannotReplacePreviousUsableModel() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        let first = try await manager.importDirectory(h.source, manifest: h.manifest)
        let pointerBefore = try Data(contentsOf: h.pointerURL)
        try Data("corrupt".utf8).write(to: h.source.appendingPathComponent("tokens.txt"))
        await expectError(.sizeMismatch("tokens.txt")) {
            _ = try await manager.importDirectory(h.source,
                manifest: h.replacing(revision: String(repeating: "b", count: 40)))
        }
        XCTAssertEqual(try Data(contentsOf: h.pointerURL), pointerBefore)
        let after = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertEqual(after, first)
        try h.assertInstalled(first)
        try h.assertNoStaging()
    }

    func testInstalledModelIsRehashedBeforeItCanBeLeased() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        let installed = try await manager.importDirectory(h.source, manifest: h.manifest)
        let encoder = try XCTUnwrap(installed.files[.encoder])
        try Data(repeating: 0, count: h.bytes["encoder.onnx"]!.count).write(to: encoder)
        await expectError(.checksumMismatch("encoder.onnx")) {
            _ = try await manager.acquire(modelID: h.manifest.modelID)
        }
        await expectError(.checksumMismatch("encoder.onnx")) {
            _ = try await manager.current(modelID: h.manifest.modelID)
        }
    }

    func testLeasePreventsDeletionUntilTheExactLeaseIsReleased() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        let installed = try await manager.importDirectory(h.source, manifest: h.manifest)
        let first = try await manager.acquire(modelID: h.manifest.modelID)
        let second = try await manager.acquire(modelID: h.manifest.modelID)
        XCTAssertEqual(first.model, installed)
        XCTAssertEqual(second.model, installed)
        XCTAssertNotEqual(first.token, second.token)
        await expectError(.modelInUse) { try await manager.remove(modelID: h.manifest.modelID) }
        try await manager.release(first)
        await expectError(.modelInUse) { try await manager.remove(modelID: h.manifest.modelID) }
        await expectError(.invalidLease) { try await manager.release(first) }
        try await manager.release(second)
        try await manager.remove(modelID: h.manifest.modelID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directoryURL.path))
        let current = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertNil(current)
    }

    func testReplacementCannotDeleteFilesStillReferencedByAnOlderLease() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        _ = try await manager.importDirectory(h.source, manifest: h.manifest)
        let oldLease = try await manager.acquire(modelID: h.manifest.modelID)
        let replacementManifest = h.replacing(revision: String(repeating: "b", count: 40))
        let replacement = try await manager.importDirectory(h.source, manifest: replacementManifest)
        try h.assertInstalled(oldLease.model)
        try h.assertInstalled(replacement, manifest: replacementManifest)
        await expectError(.modelInUse) { try await manager.remove(modelID: h.manifest.modelID) }
        try await manager.release(oldLease)
        try await manager.remove(modelID: h.manifest.modelID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLease.model.directoryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: replacement.directoryURL.path))
    }

    func testDeletingUnusedModelPreservesMeetingFilesOutsideModelRoot() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let meetings = h.root.appendingPathComponent("meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: false)
        let sentinel = meetings.appendingPathComponent("original-test-note.txt")
        let content = Data("fixture note is independent of models".utf8)
        try content.write(to: sentinel)
        let manager = h.manager()
        _ = try await manager.importDirectory(h.source, manifest: h.manifest)
        try await manager.remove(modelID: h.manifest.modelID)
        XCTAssertEqual(try Data(contentsOf: sentinel), content)
        let current = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertNil(current)
    }

    func testMissingModelCannotProduceAVerifiedLease() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        let current = try await manager.current(modelID: h.manifest.modelID)
        XCTAssertNil(current)
        await expectError(.modelMissing) { _ = try await manager.acquire(modelID: h.manifest.modelID) }
    }

    func testCorruptSelectionPointerIsRejectedWithoutReadingAnOutsideModel() async throws {
        let h = try ModelFixture(); defer { h.cleanup() }
        let manager = h.manager()
        _ = try await manager.importDirectory(h.source, manifest: h.manifest)
        try Data("{\"schemaVersion\":1,\"revision\":\"../outside\",\"installationID\":\"../outside\"}".utf8)
            .write(to: h.pointerURL, options: .atomic)
        await expectError(.invalidInstallation) { _ = try await manager.current(modelID: h.manifest.modelID) }
    }
}
