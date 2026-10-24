import CryptoKit
import Dispatch
import Foundation
import XCTest
@testable import LocalMinutesModels

private struct TransferResponse: Sendable {
    let status: Int
    let headers: [String: String]
    let bytes: Data
    let interrupted: Bool
}
private final class TransferHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var response: TransferResponse?
    private var captured: [URLRequest] = []
    private var disconnectID: UUID?
    private var disconnectCallback: (@Sendable () -> Void)?
    func reset(_ response: TransferResponse) {
        lock.withLock { self.response = response; captured = []; disconnectID = nil; disconnectCallback = nil }
    }
    func begin(_ request: URLRequest) -> TransferResponse? { lock.withLock { captured.append(request); return response } }
    var requests: [URLRequest] { lock.withLock { captured } }
    var canDisconnect: Bool { lock.withLock { disconnectCallback != nil } }
    func holdDisconnect(id: UUID, _ callback: @escaping @Sendable () -> Void) {
        lock.withLock { disconnectID = id; disconnectCallback = callback }
    }
    func clearDisconnect(id: UUID) {
        lock.withLock { if disconnectID == id { disconnectID = nil; disconnectCallback = nil } }
    }
    func disconnect() {
        let callback = lock.withLock { () -> (@Sendable () -> Void)? in
            let callback = disconnectCallback; disconnectCallback = nil; disconnectID = nil
            return callback
        }
        callback?()
    }
}
private final class TransferHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let state = TransferHTTPState()
    private let lock = NSLock()
    private let connectionID = UUID()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let response = Self.state.begin(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        DispatchQueue.global().async { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }), let url = self.request.url,
                  let http = HTTPURLResponse(url: url, statusCode: response.status,
                    httpVersion: "HTTP/1.1", headerFields: response.headers) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.bytes)
            if response.interrupted {
                // Do not assume didLoad means Foundation delivered the body.
                // The test disconnects only after observing real durable bytes.
                Self.state.holdDisconnect(id: self.connectionID) { [weak self] in self?.disconnect() }
            }
            else { self.client?.urlProtocolDidFinishLoading(self) }
        }
    }
    private func disconnect() {
        guard !lock.withLock({ stopped }) else { return }
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    }
    override func stopLoading() {
        lock.withLock { stopped = true }
        Self.state.clearDisconnect(id: connectionID)
    }
}

private final class FileScopeProbe: ModelFileSecurityScope, @unchecked Sendable {
    private let lock = NSLock()
    private let denied: URL?
    private let cancelAfterFirstGrant: Bool
    private var attempts: [URL] = []
    private var granted: [URL] = []
    private var ended: [URL] = []
    private var cancelled = false
    init(denied: URL? = nil, cancelAfterFirstGrant: Bool = false) {
        self.denied = denied; self.cancelAfterFirstGrant = cancelAfterFirstGrant
    }
    func begin(_ url: URL) -> Bool {
        let result = lock.withLock { () -> (Bool, Bool) in
            attempts.append(url)
            guard url != denied else { return (false, false) }
            granted.append(url)
            return (true, cancelAfterFirstGrant && granted.count == 1)
        }
        if result.1 {
            withUnsafeCurrentTask { task in
                if let task { task.cancel(); lock.withLock { cancelled = true } }
            }
        }
        return result.0
    }
    func end(_ url: URL) { lock.withLock { ended.append(url) } }
    var begins: [URL] { lock.withLock { granted } }
    var ends: [URL] { lock.withLock { ended } }
    var attemptCount: Int { lock.withLock { attempts.count } }
    var cancelledCurrentTask: Bool { lock.withLock { cancelled } }
}

@MainActor
final class ModelTransferIntegrationTests: XCTestCase {
    func testFilesImportWithoutDirectoryURLHintLeavesNoOwnedSourceCopiesAfterSuccessfulInstall() async throws {
        try await fixture { f in
            let manager = f.factory().makeManager()
            let path = f.app.appendingPathComponent("ModelImports", isDirectory: true)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            let noHint = URL(fileURLWithPath: path.path, isDirectory: false)
            let importer = ModelFilesImporter(manager: manager, stagingRootURL: noHint)
            let access = FileScopeProbe()
            let before = try f.sourceSnapshot()
            let model = try await importer.importFiles(f.files, manifest: f.speechManifest, access: access)
            XCTAssertEqual(model.manifest, f.speechManifest)
            XCTAssertEqual(try f.importOperations(), [], "Directory URL spelling cannot retain potentially multi-GB source copies")
            XCTAssertEqual(try f.sourceSnapshot(), before)
            assertBalanced(access)
        }
    }

    func testRemovingModelPurgesInterruptedProgressWithoutErasingAnotherPinAndRefusesCacheLinks() async throws {
        try await fixture { f in
            let factory = f.factory()
            let manager = factory.makeManager()
            TransferHTTPProtocol.state.reset(.init(status: 200,
                headers: ["Content-Length": "\(f.downloadBytes.count)", "ETag": "\"complete-v1\""],
                bytes: f.downloadBytes, interrupted: false))
            _ = try await manager.download(f.downloadManifest)
            let cached = try factory.checkpointDirectory(for: f.artifact)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cached.appendingPathComponent("partial.bin").path),
                "A completed verified download releases its duplicate progress bytes")
            // An interrupted retry can coexist with the still-approved install.
            // Seed that owned fixture explicitly; completed downloads must not
            // retain a second full model solely to satisfy a cleanup test.
            try FileManager.default.createDirectory(at: cached, withIntermediateDirectories: true)
            let prefix = Data(f.downloadBytes.prefix(1_024))
            try prefix.write(to: cached.appendingPathComponent("partial.bin"))
            let checkpoint = ModelDownloadCheckpoint(downloadURL: f.artifact.downloadURL,
                revision: f.downloadManifest.revision, fileName: f.artifact.fileName,
                expectedByteCount: f.artifact.byteCount, sha256: f.artifact.sha256,
                strongETag: "\"interrupted-retry\"", receivedByteCount: Int64(prefix.count),
                partialSHA256: transferDigest(prefix))
            try JSONEncoder().encode(checkpoint).write(to: cached.appendingPathComponent("checkpoint.json"))
            let other = try factory.checkpointDirectory(for: f.changedArtifact(name: "different.gguf"))
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
            let sentinel = other.appendingPathComponent("partial.bin")
            try Data("Other model download".utf8).write(to: sentinel)
            try await manager.remove(modelID: f.downloadManifest.modelID)
            try factory.discardProgress(for: f.downloadManifest)
            XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path), "Remove must free retained weights as well as the installation")
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("Other model download".utf8))
            // Independent unsafe cache after the success path must fail closed.
            if FileManager.default.fileExists(atPath: cached.path) { try FileManager.default.removeItem(at: cached) }
            try FileManager.default.createSymbolicLink(at: cached, withDestinationURL: other)
            XCTAssertThrowsError(try factory.discardProgress(for: f.downloadManifest))
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("Other model download".utf8))
            let removed = try await manager.current(modelID: f.downloadManifest.modelID)
            XCTAssertNil(removed)
        }
    }

    func testResumeCacheIsStableOwnedAndDistinctForEveryArtifactPinAcrossFactoryReopen() async throws {
        try await fixture { f in
            let first = f.factory()
            let path = try first.checkpointDirectory(for: f.artifact)
            XCTAssertEqual(path, try f.factory().checkpointDirectory(for: f.artifact))
            XCTAssertEqual(path.deletingLastPathComponent(), f.app.appendingPathComponent("DownloadResume", isDirectory: true))
            XCTAssertNotNil(UUID(uuidString: path.lastPathComponent))
            XCTAssertFalse(path.path.hasPrefix(f.app.appendingPathComponent("Models").path + "/"))
            let variants = [
                f.changedArtifact(revision: String(repeating: "c", count: 40)),
                f.changedArtifact(sha: String(repeating: "d", count: 64)),
                f.changedArtifact(size: f.artifact.byteCount + 1),
                f.changedArtifact(name: "another.gguf"),
                f.changedArtifact(repository: "another-publisher/model")
            ]
            let all = try variants.map { try first.checkpointDirectory(for: $0) }
            XCTAssertFalse(all.contains(path))
            XCTAssertEqual(Set(all).count, variants.count)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), "A cache-location calculation must not download or install files")
        }
    }

    func testActualFactoryManagerResumesInterruptedTransferAfterFactoryAndManagerReopen() async throws {
        try await fixture { f in
            let firstFactory = f.factory()
            let first = firstFactory.makeManager()
            let etag = "\"integration-v1\""
            TransferHTTPProtocol.state.reset(.init(status: 200,
                headers: ["Content-Length": "\(f.downloadBytes.count)", "ETag": etag],
                bytes: Data(f.downloadBytes.prefix(1_024)), interrupted: true))
            let location = try firstFactory.checkpointDirectory(for: f.artifact)
            let partial = location.appendingPathComponent("partial.bin")
            let firstDownload = Task { try await first.download(f.downloadManifest) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            var durable = false
            while ContinuousClock.now < deadline {
                let point = try? JSONDecoder().decode(ModelDownloadCheckpoint.self,
                    from: Data(contentsOf: location.appendingPathComponent("checkpoint.json")))
                if TransferHTTPProtocol.state.canDisconnect,
                   (try? Data(contentsOf: partial)) == Data(f.downloadBytes.prefix(1_024)),
                   point?.receivedByteCount == 1_024,
                   point?.partialSHA256 == transferDigest(Data(f.downloadBytes.prefix(1_024))) {
                    durable = true; break
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
            XCTAssertTrue(durable, "The actual transport must durably accept1024bytes before this fixture disconnects")
            guard durable else {
                firstDownload.cancel(); TransferHTTPProtocol.state.disconnect()
                _ = try? await firstDownload.value
                return
            }
            TransferHTTPProtocol.state.disconnect()
            do { _ = try await firstDownload.value; XCTFail("Interrupted HTTP must not publish an installation") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .downloadFailed) }
            let activeBefore = try await first.current(modelID: f.downloadManifest.modelID)
            XCTAssertNil(activeBefore)
            XCTAssertEqual(try? Data(contentsOf: partial), Data(f.downloadBytes.prefix(1_024)))
            let checkpoint = try? JSONDecoder().decode(ModelDownloadCheckpoint.self,
                from: Data(contentsOf: location.appendingPathComponent("checkpoint.json")))
            XCTAssertEqual(checkpoint?.receivedByteCount, 1_024)
            TransferHTTPProtocol.state.reset(.init(status: 206, headers: ["Content-Length": "3072",
                "Content-Range": "bytes 1024-4095/4096", "ETag": etag],
                bytes: Data(f.downloadBytes.dropFirst(1_024)), interrupted: false))
            let reopened = f.factory().makeManager()
            let installed = try await reopened.download(f.downloadManifest)
            XCTAssertEqual(installed.manifest, f.downloadManifest)
            let file = try XCTUnwrap(installed.files[.summary])
            XCTAssertEqual(try Data(contentsOf: file), f.downloadBytes)
            XCTAssertEqual(transferDigest(try Data(contentsOf: file)), f.artifact.sha256)
            XCTAssertEqual(TransferHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=1024-")
            XCTAssertEqual(TransferHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "If-Range"), etag)
            let active = try await reopened.current(modelID: f.downloadManifest.modelID)
            XCTAssertEqual(active, installed)
        }
    }

    func testSecurityScopedFilesUseActualManagerChecksAndPreserveSourceBytesAndPermissions() async throws {
        try await fixture { f in
            let manager = f.factory().makeManager()
            let access = FileScopeProbe()
            let importer = ModelFilesImporter(manager: manager, stagingRootURL: f.app.appendingPathComponent("ModelImports"))
            let before = try f.sourceSnapshot()
            // Unselected siblings are not part of a Files selection and must
            // not be copied by treating a selected file's parent as the import.
            let sibling = f.external.appendingPathComponent("README.txt")
            try Data("Original unselected public fixture".utf8).write(to: sibling)
            let installed = try await importer.importFiles(f.files, manifest: f.speechManifest, access: access)
            XCTAssertEqual(installed.manifest, f.speechManifest)
            XCTAssertEqual(Set(access.begins), Set(f.files))
            XCTAssertEqual(access.begins.count, f.files.count)
            assertBalanced(access)
            for artifact in f.speechManifest.artifacts {
                let owned = try XCTUnwrap(installed.files[artifact.role])
                XCTAssertEqual(transferDigest(try Data(contentsOf: owned)), artifact.sha256)
            }
            let active = try await manager.current(modelID: f.speechManifest.modelID)
            XCTAssertEqual(active, installed)
            XCTAssertEqual(try f.sourceSnapshot(), before)
            XCTAssertEqual(try Data(contentsOf: sibling), Data("Original unselected public fixture".utf8))
            XCTAssertEqual(try f.importOperations(), [], "No source copies remain after the manager settles")
        }
    }

    func testExtraDuplicateWrongBasenameOrCorruptSelectionCannotReplaceAnApprovedInstallation() async throws {
        for fault in ["extra", "duplicate", "wrong", "corrupt"] {
            try await fixture { f in
                let manager = f.factory().makeManager()
                let original = try await manager.importDirectory(f.external, manifest: f.speechManifest)
                let importer = ModelFilesImporter(manager: manager, stagingRootURL: f.app.appendingPathComponent("ModelImports"))
                let access = FileScopeProbe()
                var selected = f.files
                switch fault {
                case "extra":
                    let extra = f.external.appendingPathComponent("extra.bin")
                    try Data("Original extra fixture".utf8).write(to: extra); selected.append(extra)
                case "duplicate":
                    let other = f.root.appendingPathComponent("OtherSelection", isDirectory: true)
                    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
                    let duplicate = other.appendingPathComponent(f.files[0].lastPathComponent)
                    try FileManager.default.copyItem(at: f.files[0], to: duplicate); selected[1] = duplicate
                case "wrong":
                    let wrong = f.external.appendingPathComponent("wrong-encoder.onnx")
                    try FileManager.default.copyItem(at: f.files[0], to: wrong); selected[0] = wrong
                default:
                    var corrupted = try Data(contentsOf: selected[0])
                    corrupted[corrupted.startIndex] ^= 0xff
                    try corrupted.write(to: selected[0])
                }
                let before = try f.sourceSnapshot()
                do { _ = try await importer.importFiles(selected, manifest: f.speechManifest, access: access); XCTFail("Invalid Files selection must not publish") }
                catch {
                    if fault == "corrupt" { XCTAssertEqual(error as? ModelInstallationError, .checksumMismatch(f.files[0].lastPathComponent)) }
                    else { XCTAssertEqual(error as? ModelFileImportError, .invalidSelection) }
                }
                assertBalanced(access)
                let retained = try await manager.current(modelID: f.speechManifest.modelID)
                XCTAssertEqual(retained, original)
                XCTAssertEqual(try f.sourceSnapshot(), before)
                XCTAssertEqual(try f.importOperations(), [])
            }
        }
    }

    func testDeniedOrCancelledSecurityAccessEndsEveryPriorGrantWithoutAnActiveInstall() async throws {
        for cancel in [false, true] {
            try await fixture { f in
                let manager = f.factory().makeManager()
                let importer = ModelFilesImporter(manager: manager, stagingRootURL: f.app.appendingPathComponent("ModelImports"))
                let access = FileScopeProbe(denied: cancel ? nil : f.files[1], cancelAfterFirstGrant: cancel)
                let before = try f.sourceSnapshot()
                let pending = Task { @MainActor in
                    try await importer.importFiles(f.files, manifest: f.speechManifest, access: access)
                }
                do { _ = try await pending.value; XCTFail("Denied/cancelled Files access must not report installation") }
                catch {
                    if cancel { XCTAssertTrue(error is CancellationError) }
                    else { XCTAssertEqual(error as? ModelFileImportError, .accessDenied) }
                }
                XCTAssertEqual(access.begins.count, 1)
                assertBalanced(access)
                if cancel { XCTAssertTrue(access.cancelledCurrentTask) }
                else { XCTAssertEqual(access.attemptCount, 2) }
                let active = try await manager.current(modelID: f.speechManifest.modelID)
                XCTAssertNil(active)
                XCTAssertEqual(try f.sourceSnapshot(), before)
                XCTAssertEqual(try f.importOperations(), [])
            }
        }
    }

    private func assertBalanced(_ access: FileScopeProbe, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(access.ends.count, access.begins.count, file: file, line: line)
        XCTAssertEqual(Dictionary(grouping: access.ends, by: { $0 }).mapValues(\.count),
            Dictionary(grouping: access.begins, by: { $0 }).mapValues(\.count), file: file, line: line)
        XCTAssertTrue(Dictionary(grouping: access.ends, by: { $0 }).values.allSatisfy { $0.count == 1 }, file: file, line: line)
    }
    private func fixture(_ body: (TransferFixture) async throws -> Void) async throws {
        let f = try TransferFixture()
        do { try await body(f) }
        catch { try f.remove(); throw error }
        try f.remove()
    }
}

private func transferDigest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
private struct TransferSourceSnapshot: Equatable { let bytes: Data; let permissions: Int }
private enum TransferFixtureError: Error { case unsafeCleanup }

private final class TransferFixture {
    let root: URL
    let app: URL
    let external: URL
    let names = ["encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"]
    let downloadBytes = Data((0..<4_096).map { UInt8($0 % 251) })
    let revision = String(repeating: "a", count: 40)
    var files: [URL] { names.map { external.appendingPathComponent($0) } }
    var artifact: ModelArtifact { changedArtifact() }
    var downloadManifest: ModelManifest {
        .init(modelID: "transfer-download", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/example/model")!, revision: revision,
            licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic bytes; no inference claim.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [artifact])
    }
    var speechManifest: ModelManifest {
        let roles: [ModelFileRole] = [.encoder, .decoder, .joiner, .tokens]
        return ModelManifest(modelID: "files-import", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/example/model")!, revision: revision,
            licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic Files fixtures; installer integrity only.",
            runtimeVersion: "sherpa-onnx-1.13.8", sampleRate: 16_000, featureDimension: 80,
            artifacts: names.enumerated().map { index, name in
                let bytes = Data("Original \(name) fixture bytes".utf8)
                return .init(role: roles[index], fileName: name, byteCount: Int64(bytes.count), sha256: transferDigest(bytes),
                    downloadURL: URL(string: "https://huggingface.co/example/model/resolve/\(revision)/\(name)")!,
                    digestProvenance: .independentlyDownloaded)
            })
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("LocalMinutesTransfer-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("App", isDirectory: true)
        external = root.appendingPathComponent("ExternalFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        for name in names {
            let file = external.appendingPathComponent(name)
            try Data("Original \(name) fixture bytes".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        }
    }
    func factory() -> ModelTransferFactory {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransferHTTPProtocol.self]
        return ModelTransferFactory(appRootURL: app, configuration: configuration, availableBytes: { _ in .max })
    }
    func changedArtifact(revision: String? = nil, sha: String? = nil, size: Int64? = nil,
                         name: String = "chosen.gguf", repository: String = "example/model") -> ModelArtifact {
        .init(role: .summary, fileName: name, byteCount: size ?? Int64(downloadBytes.count), sha256: sha ?? transferDigest(downloadBytes),
            downloadURL: URL(string: "https://huggingface.co/\(repository)/resolve/\(revision ?? self.revision)/\(name)")!,
            digestProvenance: .independentlyDownloaded)
    }
    func sourceSnapshot() throws -> [String: TransferSourceSnapshot] {
        try Dictionary(uniqueKeysWithValues: files.map { url in
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            return (url.lastPathComponent, TransferSourceSnapshot(bytes: try Data(contentsOf: url), permissions: permissions?.intValue ?? -1))
        })
    }
    func importOperations() throws -> [String] {
        let directory = app.appendingPathComponent("ModelImports")
        return FileManager.default.fileExists(atPath: directory.path)
            ? try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() : []
    }
    func remove() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix("LocalMinutesTransfer-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              UUID(uuidString: String(root.lastPathComponent.dropFirst("LocalMinutesTransfer-".count))) != nil else {
            throw TransferFixtureError.unsafeCleanup
        }
        try FileManager.default.removeItem(at: root)
    }
}
