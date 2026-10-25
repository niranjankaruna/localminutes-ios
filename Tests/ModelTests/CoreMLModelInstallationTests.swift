import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
@testable import LocalMinutesModels

/// Tiny nonsense bytes in the actual twenty-one-file bundle layout. These are
/// filesystem/installer checks, never executable Core ML or inference evidence.
@MainActor
final class CoreMLModelInstallationTests: XCTestCase {
    func testNestedAssetImportReopensInventoriesAndLeasesWithoutCollapsingRepeatedRolesOrChangingSources() async throws {
        try await fixture { f in
            let manager = f.manager()
            let other = try await f.installOther(using: manager)
            let before = try f.sourceSnapshot()
            let model: VerifiedModel
            do { model = try await manager.importDirectory(f.source, manifest: f.manifest()) }
            catch { XCTFail("A complete pinned nested Core ML tree must install: \(error)"); return }
            try f.assertInstalled(model)
            XCTAssertTrue(model.files.isEmpty, "Repeated coreMLAsset roles use directoryURL; a flat role dictionary must not lose files or trap")
            let reopened = f.manager()
            let current = try await reopened.current(modelID: model.manifest.modelID)
            XCTAssertEqual(current, model)
            let inventory = try await reopened.installedManifests()
            XCTAssertEqual(Set(inventory.map(\.modelID)), Set([model.manifest.modelID, other.manifest.modelID]))
            let lease = try await reopened.acquire(modelID: model.manifest.modelID)
            XCTAssertEqual(lease.model, model)
            do { try await reopened.remove(modelID: model.manifest.modelID); XCTFail("A native-use lease protects the whole nested installation") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
            try await reopened.release(lease)
            try await reopened.remove(modelID: model.manifest.modelID)
            let removed = try await reopened.current(modelID: model.manifest.modelID)
            let retained = try await reopened.current(modelID: other.manifest.modelID)
            XCTAssertNil(removed); XCTAssertEqual(retained, other)
            XCTAssertEqual(try f.sourceSnapshot(), before)
            try f.assertNoStaging()
        }
    }

    func testNestedDownloadCreatesOwnedParentsVerifiesEveryAssetAndPreservesCurrentAfterLaterFailure() async throws {
        try await fixture { f in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [CoreMLAssetURLProtocol.self]
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 15
            let factory = ModelTransferFactory(appRootURL: f.app, configuration: configuration,
                availableBytes: { _ in 64 * 1_024 * 1_024 })
            let manifest = f.manifest()
            let first = try XCTUnwrap(manifest.artifacts.first)
            let firstBytes = try XCTUnwrap(f.bytes[first.fileName])
            let tag = "\"nested-coreml-reviewed-fixture\""
            // Seed a real protected partial/checkpoint for a nested asset. The
            // real factory and HTTPS data delegate must send its Range/If-Range.
            do {
                let cache = try factory.checkpointDirectory(for: first)
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try PersistentFilePolicy.protectDirectory(cache)
                let prefix = Data(firstBytes.prefix(8))
                try PersistentFilePolicy.writeAtomically(prefix, to: cache.appendingPathComponent("partial.bin"), within: cache)
                let checkpoint = ModelDownloadCheckpoint(downloadURL: first.downloadURL, revision: manifest.revision,
                    fileName: first.fileName, expectedByteCount: first.byteCount, sha256: first.sha256,
                    strongETag: tag, receivedByteCount: 8, partialSHA256: coreMLAssetSHA(prefix))
                try PersistentFilePolicy.writeAtomically(JSONEncoder().encode(checkpoint),
                    to: cache.appendingPathComponent("checkpoint.json"), within: cache)
            } catch { XCTFail("Nested artifact cache identity must be supported by the actual factory: \(error)"); return }
            CoreMLAssetURLProtocol.state.prepare(bytes: f.bytes, resumeURL: first.downloadURL, etag: tag)
            defer { CoreMLAssetURLProtocol.state.clear() }
            let manager = factory.makeManager()
            let model: VerifiedModel
            do { model = try await manager.download(f.manifest()) }
            catch { XCTFail("Nested pinned files must pass through the real installer: \(error)"); return }
            try f.assertInstalled(model)
            let requests = CoreMLAssetURLProtocol.state.requests()
            XCTAssertEqual(requests.compactMap(\.url), manifest.artifacts.map(\.downloadURL))
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=8-")
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "If-Range"), tag)
            let cachePaths = try manifest.artifacts.map { try factory.checkpointDirectory(for: $0) }
            XCTAssertEqual(Set(cachePaths).count, 21)
            for path in cachePaths {
                XCTAssertEqual(path.deletingLastPathComponent(), f.app.appendingPathComponent("DownloadResume", isDirectory: true))
                XCTAssertNotNil(UUID(uuidString: path.lastPathComponent))
            }
            CoreMLAssetURLProtocol.state.fail(at: "Encoder.mlmodelc/weights/weight.bin")
            do { _ = try await manager.download(f.manifest(revision: String(repeating: "b", count: 40))); XCTFail("Partial nested download cannot replace current") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .downloadFailed) }
            let retained = try await manager.current(modelID: model.manifest.modelID)
            XCTAssertEqual(retained, model)
            try f.assertNoStaging()
        }
    }

    func testCorruptExtraSymlinkAndHardlinkAssetsCannotReplaceAnApprovedTreeOrMutateExternalFiles() async throws {
        for fault in ["checksum", "extra", "symlink", "hardlink"] {
            try await fixture { f in
                let manager = f.manager()
                let original: VerifiedModel
                do { original = try await manager.importDirectory(f.source, manifest: f.manifest()) }
                catch { XCTFail("Nested tree setup requires a real approved installation: \(error)"); return }
                let path = "Encoder.mlmodelc/weights/weight.bin"
                let target = f.source.appendingPathComponent(path)
                let outside = f.root.appendingPathComponent("external-retained.bin")
                let retainedBytes = try XCTUnwrap(f.bytes[path])
                try retainedBytes.write(to: outside)
                let expected: ModelInstallationError
                switch fault {
                case "checksum":
                    var bytes = retainedBytes; bytes[bytes.startIndex] ^= 0xff; try bytes.write(to: target)
                    expected = .checksumMismatch(path)
                case "extra":
                    let extra = "Decoder.mlmodelc/unexpected.bin"
                    try Data("Unselected synthetic asset".utf8).write(to: f.source.appendingPathComponent(extra))
                    expected = .unexpectedFile(extra)
                case "symlink":
                    try FileManager.default.removeItem(at: target)
                    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
                    expected = .unsafeFile(path)
                default:
                    try FileManager.default.removeItem(at: target)
                    try FileManager.default.linkItem(at: outside, to: target)
                    expected = .unsafeFile(path)
                }
                let before = try f.sourceSnapshot()
                do { _ = try await manager.importDirectory(f.source, manifest: f.manifest()); XCTFail("A \(fault) nested asset must be refused") }
                catch { XCTAssertEqual(error as? ModelInstallationError, expected) }
                let current = try await manager.current(modelID: original.manifest.modelID)
                XCTAssertEqual(current, original)
                XCTAssertEqual(try Data(contentsOf: outside), retainedBytes)
                XCTAssertEqual(try f.sourceSnapshot(), before)
                try f.assertNoStaging()
            }
        }
    }

    func testNestedManifestRefusesTraversalDuplicatePrefixMixedRolesAndUnboundedInventoryBeforeReadingSources() async throws {
        try await fixture { f in
            let manager = f.manager()
            let base = f.manifest()
            let first = try XCTUnwrap(base.artifacts.first)
            var invalid: [ModelManifest] = []
            for path in ["../escape.bin", "/tmp/escape.bin", "Encoder.mlmodelc/../escape.bin",
                         "Encoder.mlmodelc//weights/weight.bin", "Encoder.mlmodelc\\weights\\weight.bin"] {
                invalid.append(f.manifest(artifacts: [f.changed(first, path: path)] + Array(base.artifacts.dropFirst())))
            }
            invalid.append(f.manifest(artifacts: base.artifacts + [first]))
            invalid.append(f.manifest(artifacts: [f.changed(first, path: "Encoder.mlmodelc")] + base.artifacts))
            invalid.append(f.manifest(artifacts: [f.changed(first, role: .summary)] + Array(base.artifacts.dropFirst())))
            invalid.append(f.manifest(artifacts: (0...256).map { f.changed(first, path: "Encoder.mlmodelc/asset-\($0).bin") }))
            invalid.append(f.manifest(artifacts: [f.changed(first, size: Int64.max)] + Array(base.artifacts.dropFirst())))
            let before = try f.sourceSnapshot()
            for manifest in invalid {
                do { _ = try await manager.importDirectory(f.source, manifest: manifest); XCTFail("Malformed/unbounded relative asset inventory must fail before publication") }
                catch { XCTAssertEqual(error as? ModelInstallationError, .invalidManifest) }
            }
            let installed = try await manager.current(modelID: base.modelID)
            XCTAssertNil(installed)
            XCTAssertEqual(try f.sourceSnapshot(), before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("escape.bin").path))
            try f.assertNoStaging()
        }
    }

    func testFilesFolderSelectionBalancesOneSecurityScopeAndRefusesDeniedOrAliasedRootsWithoutSourceChanges() async throws {
        for mode in ["valid", "denied", "alias"] {
            try await fixture { f in
                let manager = f.manager()
                let importer = ModelFilesImporter(manager: manager, stagingRootURL: f.app.appendingPathComponent("ModelImports"))
                let access = CoreMLFolderSecurityScope(allow: mode != "denied")
                let before = try f.sourceSnapshot()
                var selected = f.source
                if mode == "alias" {
                    selected = f.root.appendingPathComponent("aliased-folder")
                    try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: f.source)
                }
                do {
                    let model = try await importer.importFiles([selected], manifest: f.manifest(), access: access)
                    if mode != "valid" { XCTFail("Denied/aliased selected roots must not install") }
                    else { try f.assertInstalled(model) }
                } catch {
                    if mode == "valid" { XCTFail("One actual selected model folder must install its exact nested assets: \(error)") }
                    else { XCTAssertEqual(error as? ModelFileImportError, mode == "denied" ? .accessDenied : .unsafeSource) }
                }
                XCTAssertEqual(access.attempted(), [selected])
                XCTAssertEqual(access.ended(), mode == "denied" ? [] : [selected])
                XCTAssertEqual(try f.sourceSnapshot(), before)
                let imports = f.app.appendingPathComponent("ModelImports")
                if FileManager.default.fileExists(atPath: imports.path) {
                    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: imports.path).isEmpty)
                }
                try f.assertNoStaging()
            }
        }
    }

    private func fixture(_ body: @MainActor (CoreMLInstallationFixture) async throws -> Void) async throws {
        let f = try CoreMLInstallationFixture()
        do { try await body(f) } catch { try f.remove(); throw error }
        try f.remove()
    }
}

private func coreMLAssetSHA(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

private final class CoreMLAssetHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [String: Data] = [:]
    private var resumeURL: URL?
    private var etag = ""
    private var fault: String?
    private var seen: [URLRequest] = []
    func prepare(bytes: [String: Data], resumeURL: URL, etag: String) {
        lock.withLock { self.bytes = bytes; self.resumeURL = resumeURL; self.etag = etag; fault = nil; seen = [] }
    }
    func clear() { lock.withLock { bytes = [:]; resumeURL = nil; fault = nil; seen = [] } }
    func fail(at path: String) { lock.withLock { fault = path } }
    func requests() -> [URLRequest] { lock.withLock { seen } }
    func response(for request: URLRequest) -> (Int, [String: String], Data)? {
        lock.withLock {
            seen.append(request)
            guard let url = request.url,
                  let path = bytes.keys.first(where: { url.path.hasSuffix("/" + $0) }),
                  path != fault, let data = bytes[path] else { return nil }
            let resumed = url == resumeURL && request.value(forHTTPHeaderField: "Range") == "bytes=8-"
                && request.value(forHTTPHeaderField: "If-Range") == etag
            let offset = resumed ? 8 : 0
            let body = Data(data.dropFirst(offset))
            var headers = ["Content-Length": String(body.count), "ETag": etag]
            if resumed { headers["Content-Range"] = "bytes 8-\(data.count - 1)/\(data.count)" }
            return (resumed ? 206 : 200, headers, body)
        }
    }
}

private final class CoreMLAssetURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = CoreMLAssetHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (status, headers, bytes) = Self.state.response(for: request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class CoreMLFolderSecurityScope: ModelFileSecurityScope, @unchecked Sendable {
    private let lock = NSLock()
    private let allow: Bool
    private var attempts: [URL] = [], ends: [URL] = []
    init(allow: Bool) { self.allow = allow }
    func begin(_ url: URL) -> Bool { lock.withLock { attempts.append(url); return allow } }
    func end(_ url: URL) { lock.withLock { ends.append(url) } }
    func attempted() -> [URL] { lock.withLock { attempts } }
    func ended() -> [URL] { lock.withLock { ends } }
}

private struct CoreMLSourceEntry: Equatable {
    let bytes: Data?
    let link: String?
    let permissions: Int
}

@MainActor
private final class CoreMLInstallationFixture {
    let root: URL, app: URL, source: URL, storage: URL
    let bytes: [String: Data]
    let revision = String(repeating: "a", count: 40)
    init() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-coreml-install-\(UUID().uuidString)", isDirectory: true)
        let application = fixtureRoot.appendingPathComponent("Application", isDirectory: true)
        root = fixtureRoot; app = application
        source = fixtureRoot.appendingPathComponent("FilesSelection", isDirectory: true)
        storage = application.appendingPathComponent("Models", isDirectory: true)
        var fixture: [String: Data] = [:]
        for bundle in ["Decoder", "Encoder", "JointDecision", "Preprocessor"] {
            for path in ["analytics/coremldata.bin", "coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"] {
                let name = bundle + ".mlmodelc/" + path
                fixture[name] = Data("Synthetic integrity-only nested asset: \(name)".utf8)
            }
        }
        fixture["parakeet_vocab.json"] = Data("{\"synthetic\":\"storage fixture, not vocabulary\"}".utf8)
        bytes = fixture
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        for (path, data) in bytes {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
    }
    func manager(downloader: ModelArtifactDownloader? = nil) -> ModelInstallationManager {
        .init(rootURL: storage, availableBytes: { _ in 64 * 1_024 * 1_024 }, downloader: downloader)
    }
    func manifest(revision: String? = nil, artifacts: [ModelArtifact]? = nil) -> ModelManifest {
        let pin = revision ?? self.revision
        return .init(modelID: "synthetic-coreml-parakeet-assets", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/example/coreml-assets")!, revision: pin,
            licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic bytes; no model/inference claim.",
            runtimeVersion: "coreml-parakeet-tdt-v2-fluid-c79c4106", sampleRate: 16_000, featureDimension: 128,
            artifacts: artifacts ?? bytes.keys.sorted().map { path in
                let data = bytes[path]!
                return .init(role: .coreMLAsset, fileName: path, byteCount: Int64(data.count), sha256: coreMLAssetSHA(data),
                    downloadURL: URL(string: "https://huggingface.co/example/coreml-assets/resolve/\(pin)/\(path)")!,
                    digestProvenance: .independentlyDownloaded)
            })
    }
    func changed(_ artifact: ModelArtifact, path: String? = nil, role: ModelFileRole? = nil, size: Int64? = nil) -> ModelArtifact {
        .init(role: role ?? artifact.role, fileName: path ?? artifact.fileName, byteCount: size ?? artifact.byteCount,
            sha256: artifact.sha256, downloadURL: artifact.downloadURL, digestProvenance: artifact.digestProvenance)
    }
    func installOther(using manager: ModelInstallationManager) async throws -> VerifiedModel {
        let folder = root.appendingPathComponent("OtherOriginalModel", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let data = Data("GGUF other synthetic integrity-only bytes".utf8)
        try data.write(to: folder.appendingPathComponent("other.gguf"))
        let manifest = ModelManifest(modelID: "retained-other-model", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/example/coreml-assets")!, revision: revision,
            licenseIdentifier: "CC0-1.0", licenseNotice: "Original integrity fixture.", runtimeVersion: "llama.cpp-b5046",
            artifacts: [.init(role: .summary, fileName: "other.gguf", byteCount: Int64(data.count), sha256: coreMLAssetSHA(data),
                downloadURL: URL(string: "https://huggingface.co/example/coreml-assets/resolve/\(revision)/other.gguf")!,
                digestProvenance: .independentlyDownloaded)])
        return try await manager.importDirectory(folder, manifest: manifest)
    }
    func assertInstalled(_ model: VerifiedModel) throws {
        XCTAssertEqual(model.manifest, manifest())
        XCTAssertEqual(model.manifest.artifacts.count, 21)
        let expected = storage.appendingPathComponent(model.manifest.modelID).appendingPathComponent(revision)
            .appendingPathComponent(model.installationID.uuidString)
        XCTAssertEqual(model.directoryURL, expected)
        for (path, data) in bytes {
            let target = model.directoryURL.appendingPathComponent(path)
            XCTAssertEqual(try Data(contentsOf: target), data)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        let stored = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: model.directoryURL.appendingPathComponent("manifest.json")))
        XCTAssertEqual(stored, model.manifest)
    }
    func sourceSnapshot() throws -> [String: CoreMLSourceEntry] {
        var result: [String: CoreMLSourceEntry] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: source.path) {
            let item = source.appendingPathComponent(path)
            let metadata = try FileManager.default.attributesOfItem(atPath: item.path)
            let type = metadata[.type] as? FileAttributeType
            result[path] = .init(bytes: type == .typeRegular ? try Data(contentsOf: item) : nil,
                link: type == .typeSymbolicLink ? try FileManager.default.destinationOfSymbolicLink(atPath: item.path) : nil,
                permissions: (metadata[.posixPermissions] as? NSNumber)?.intValue ?? -1)
        }
        return result
    }
    func assertNoStaging() throws {
        let staging = storage.appendingPathComponent(".staging")
        if FileManager.default.fileExists(atPath: staging.path) { XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty) }
    }
    func remove() throws {
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-coreml-install-"), root.resolvingSymlinksInPath() == root else {
            return XCTFail("Refuse cleanup outside owned synthetic asset fixture")
        }
        try FileManager.default.removeItem(at: root)
    }
}
