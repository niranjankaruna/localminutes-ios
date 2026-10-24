import CryptoKit
import Dispatch
import Foundation
import XCTest
@testable import LocalMinutesModels

// URLProtocol doubles HTTP only. URLSession, checkpoint files, retained bytes,
// real installer hashes and its atomic publication all remain actual code.
private enum ResumeEnding: Sendable { case complete, disconnect, hold }
private struct ResumeReply: Sendable {
    let status: Int
    let headers: [String: String]
    let bytes: Data
    let ending: ResumeEnding
    let finalURL: URL?
    init(status: Int = 200, headers: [String: String], bytes: Data,
         ending: ResumeEnding = .complete, finalURL: URL? = nil) {
        self.status = status; self.headers = headers; self.bytes = bytes
        self.ending = ending; self.finalURL = finalURL
    }
}
private final class ResumeHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: ResumeReply?
    private var recorded: [URLRequest] = []
    private var delivered = false
    private var stopped = 0
    private var disconnectID: UUID?
    private var disconnectCallback: (@Sendable () -> Void)?
    func reset(_ reply: ResumeReply) {
        lock.withLock { self.reply = reply; recorded = []; delivered = false; stopped = 0; disconnectID = nil; disconnectCallback = nil }
    }
    func begin(_ request: URLRequest) -> ResumeReply? { lock.withLock { recorded.append(request); return reply } }
    func sent() { lock.withLock { delivered = true } }
    func stop() { lock.withLock { stopped += 1 } }
    var requests: [URLRequest] { lock.withLock { recorded } }
    var deliveredChunk: Bool { lock.withLock { delivered } }
    var stopCount: Int { lock.withLock { stopped } }
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
private final class ResumeHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let state = ResumeHTTPState()
    private let lock = NSLock()
    private let connectionID = UUID()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let reply = Self.state.begin(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        DispatchQueue.global().async { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }),
                  let url = reply.finalURL ?? self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: reply.status,
                    httpVersion: "HTTP/1.1", headerFields: reply.headers) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: reply.bytes)
            Self.state.sent()
            guard !self.lock.withLock({ self.stopped }) else { return }
            switch reply.ending {
            case .complete: self.client?.urlProtocolDidFinishLoading(self)
            case .disconnect:
                // This is only offered data until Foundation calls the real
                // delegate. The test proves durable delivery before disconnect.
                Self.state.holdDisconnect(id: self.connectionID) { [weak self] in self?.disconnect() }
            case .hold: break
            }
        }
    }
    private func disconnect() {
        guard !lock.withLock({ stopped }) else { return }
        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
    }
    override func stopLoading() {
        lock.withLock { stopped = true }; Self.state.stop()
        Self.state.clearDisconnect(id: connectionID)
    }
}

@MainActor
final class DownloadResumeTests: XCTestCase {
    func testPinnedStrongETagResumesOnlyTheMissingBytesWithRangeAndIfRange() async throws {
        try await fixture { f in
            let prefix = 1_024
            _ = try f.seed(prefix: prefix)
            ResumeHTTPProtocol.state.reset(f.rangeReply(from: prefix))
            try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
            XCTAssertEqual(try Data(contentsOf: f.output), f.bytes)
            let requests = ResumeHTTPProtocol.state.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Range"), "bytes=\(prefix)-")
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "If-Range"), f.eTag)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.partial.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.checkpointFile.path))
        }
    }

    func testInterruptedHTTPRetainsPinnedPrefixAndResumesAfterANewTransportInstance() async throws {
        try await fixture { f in
            let prefix = 1_024
            ResumeHTTPProtocol.state.reset(f.fullReply(bytes: Data(f.bytes.prefix(prefix)), ending: .disconnect))
            let transport = f.transport(), artifact = f.artifact, output = f.output, checkpoint = f.checkpoint
            let interrupted = Task { try await transport.downloadResumable(artifact, to: output, checkpointDirectory: checkpoint) }
            let durable = await wait {
                let saved = try? f.readCheckpoint()
                return ResumeHTTPProtocol.state.canDisconnect && saved?.receivedByteCount == Int64(prefix)
                    && saved?.partialSHA256 == resumeDigest(Data(f.bytes.prefix(prefix)))
                    && (try? Data(contentsOf: f.partial)) == Data(f.bytes.prefix(prefix))
            }
            XCTAssertTrue(durable, "Real prefix/checkpoint publication must precede injected network failure")
            guard durable else {
                interrupted.cancel(); ResumeHTTPProtocol.state.disconnect()
                _ = try? await interrupted.value
                return
            }
            ResumeHTTPProtocol.state.disconnect()
            await expect(.networkFailure) {
                try await interrupted.value
            }
            let saved = try f.readCheckpoint()
            XCTAssertEqual(saved.receivedByteCount, Int64(prefix))
            XCTAssertEqual(saved.downloadURL, f.artifact.downloadURL)
            XCTAssertEqual(saved.revision, f.revision); XCTAssertEqual(saved.sha256, f.artifact.sha256)
            XCTAssertEqual(saved.expectedByteCount, f.artifact.byteCount)
            XCTAssertEqual(saved.strongETag, f.eTag)
            XCTAssertEqual(saved.partialSHA256, resumeDigest(Data(f.bytes.prefix(prefix))))
            XCTAssertEqual(try Data(contentsOf: f.partial), Data(f.bytes.prefix(prefix)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            ResumeHTTPProtocol.state.reset(f.rangeReply(from: prefix))
            try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
            XCTAssertEqual(try Data(contentsOf: f.output), f.bytes)
            XCTAssertEqual(ResumeHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=\(prefix)-")
        }
    }

    func testResumedBytesStillPassTheRealInstallerHashAndAtomicSelectionPublication() async throws {
        try await fixture { f in
            _ = try f.seed(prefix: 1_024)
            ResumeHTTPProtocol.state.reset(f.rangeReply(from: 1_024))
            let transport = f.transport()
            let checkpoint = f.checkpoint
            let manager = ModelInstallationManager(rootURL: f.modelRoot, availableBytes: { _ in .max },
                downloader: { artifact, output in
                    try await transport.downloadResumable(artifact, to: output, checkpointDirectory: checkpoint)
                })
            let verified = try await manager.download(f.manifest)
            XCTAssertEqual(verified.manifest, f.manifest)
            let bytes = try Data(contentsOf: XCTUnwrap(verified.files[.summary]))
            XCTAssertEqual(bytes, f.bytes)
            XCTAssertEqual(resumeDigest(bytes), f.artifact.sha256)
            let active = try await manager.current(modelID: f.manifest.modelID)
            XCTAssertEqual(active, verified)
            XCTAssertEqual(ResumeHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=1024-")
        }
    }

    func testCancellationRetainsDurableCheckpointOutsideInstallerStagingWithoutAnActiveInstallation() async throws {
        try await fixture { f in
            let prefix = 1_024
            ResumeHTTPProtocol.state.reset(f.fullReply(bytes: Data(f.bytes.prefix(prefix)), ending: .hold))
            let transport = f.transport()
            let checkpoint = f.checkpoint
            let manager = ModelInstallationManager(rootURL: f.modelRoot, availableBytes: { _ in .max },
                downloader: { artifact, output in
                    try await transport.downloadResumable(artifact, to: output, checkpointDirectory: checkpoint)
                })
            let manifest = f.manifest
            let pending = Task { try await manager.download(manifest) }
            let received = await wait { ResumeHTTPProtocol.state.deliveredChunk }
            XCTAssertTrue(received, "Actual URLSession must have received the server's first body chunk")
            let persisted = await wait {
                (try? f.readCheckpoint().receivedByteCount) == Int64(prefix)
                    && ((try? Data(contentsOf: f.partial).count) == prefix)
            }
            XCTAssertTrue(persisted, "Persist progress before cancellation; a transport must not retain all bytes only in memory")
            pending.cancel()
            do { _ = try await pending.value; XCTFail("Cancelled install must not report publication") }
            catch is CancellationError { }
            catch { XCTFail("Cancellation must remain distinct: \(type(of: error))") }
            let active = try await manager.current(modelID: manifest.modelID)
            XCTAssertNil(active)
            XCTAssertTrue((try? f.readCheckpoint()) != nil)
            XCTAssertEqual(try? Data(contentsOf: f.partial), Data(f.bytes.prefix(prefix)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.modelRoot.appendingPathComponent(manifest.modelID + "/current.json").path))
        }
    }

    func testServerIgnoringRangeWith200RestartsInsteadOfAppendingDuplicatePrefix() async throws {
        try await fixture { f in
            _ = try f.seed(prefix: 1_024)
            ResumeHTTPProtocol.state.reset(f.fullReply())
            try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
            XCTAssertEqual(try Data(contentsOf: f.output), f.bytes)
            XCTAssertEqual(ResumeHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "Range"), "bytes=1024-")
            XCTAssertEqual(ResumeHTTPProtocol.state.requests.first?.value(forHTTPHeaderField: "If-Range"), f.eTag)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.checkpointFile.path))
        }
    }

    func testIncoherent206StartEndTotalOrChangedETagCannotAppendToTheRetainedPrefix() async throws {
        for fault in ["start", "end", "total", "missing", "etag"] {
            try await fixture { f in
                _ = try f.seed(prefix: 1_024)
                let oldCheckpoint = try Data(contentsOf: f.checkpointFile)
                let prefix = try Data(contentsOf: f.partial)
                var headers = f.rangeHeaders(from: 1_024)
                switch fault {
                case "start": headers["Content-Range"] = "bytes 1025-4095/4096"
                case "end": headers["Content-Range"] = "bytes 1024-4096/4096"
                case "total": headers["Content-Range"] = "bytes 1024-4095/9999"
                case "missing": headers.removeValue(forKey: "Content-Range")
                default: headers["ETag"] = "\"changed-representation\""
                }
                ResumeHTTPProtocol.state.reset(.init(status: 206, headers: headers, bytes: Data(f.bytes.dropFirst(1_024))))
                await expect(.invalidRangeResponse) {
                    try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
                }
                XCTAssertEqual(try Data(contentsOf: f.partial), prefix)
                XCTAssertEqual(try Data(contentsOf: f.checkpointFile), oldCheckpoint)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            }
        }
    }

    func testStalePinnedIdentityNeverSendsARangeOrFetchesAnotherURL() async throws {
        for field in ["revision", "sha256", "expectedByteCount", "downloadURL", "fileName"] {
            try await fixture { f in
                _ = try f.seed(prefix: 1_024)
                try f.changeCheckpoint { object in
                    switch field {
                    case "revision": object[field] = String(repeating: "c", count: 40)
                    case "sha256": object[field] = String(repeating: "d", count: 64)
                    case "expectedByteCount": object[field] = 9999
                    case "downloadURL": object[field] = "https://evil.invalid/weights.bin"
                    default: object[field] = "different.gguf"
                    }
                }
                ResumeHTTPProtocol.state.reset(f.fullReply())
                let before = try Data(contentsOf: f.partial)
                await expect(.invalidResumeState) {
                    try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
                }
                XCTAssertTrue(ResumeHTTPProtocol.state.requests.isEmpty)
                XCTAssertEqual(try Data(contentsOf: f.partial), before)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            }
        }
    }

    func testWeakETagChangedPrefixOrInvalidCountIsRejectedBeforeNetwork() async throws {
        for fault in ["weak", "headerInjection", "digest", "count", "fileLength"] {
            try await fixture { f in
                _ = try f.seed(prefix: 1_024)
                if fault == "fileLength" { try Data(f.bytes.prefix(1_023)).write(to: f.partial) }
                else {
                    try f.changeCheckpoint { object in
                        if fault == "weak" { object["strongETag"] = "W/\"synthetic-v1\"" }
                        else if fault == "headerInjection" { object["strongETag"] = "\"synthetic-v1\"\r\nX-Injected: fixture" }
                        else if fault == "digest" { object["partialSHA256"] = String(repeating: "0", count: 64) }
                        else { object["receivedByteCount"] = 5_000 }
                    }
                }
                ResumeHTTPProtocol.state.reset(f.fullReply())
                await expect(.invalidResumeState) {
                    try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
                }
                XCTAssertTrue(ResumeHTTPProtocol.state.requests.isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            }
        }
    }

    func testUnapprovedFinalHostNeverPublishesOrDiscardsRetainedBytes() async throws {
        try await fixture { f in
            _ = try f.seed(prefix: 1_024)
            let before = try Data(contentsOf: f.partial)
            let reply = f.fullReply()
            ResumeHTTPProtocol.state.reset(.init(headers: reply.headers, bytes: reply.bytes,
                finalURL: URL(string: "https://evil.invalid/weights.gguf")))
            await expect(.unapprovedHost) {
                try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            XCTAssertEqual(try Data(contentsOf: f.partial), before)
        }
    }

    func testLinkedPartialOrCheckpointDirectoryCannotReadOrModifyExternalFiles() async throws {
        for mode in ["partialSymlink", "partialHardlink", "checkpointSymlink", "directorySymlink"] {
            try await fixture { f in
                _ = try f.seed(prefix: 1_024)
                let outside = f.root.appendingPathComponent("outside-owned-marker")
                let marker = Data("Original boundary marker; no model data".utf8)
                if mode == "directorySymlink" {
                    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
                    try marker.write(to: outside.appendingPathComponent("marker"))
                    try FileManager.default.removeItem(at: f.checkpoint)
                    try FileManager.default.createSymbolicLink(at: f.checkpoint, withDestinationURL: outside)
                } else {
                    try marker.write(to: outside)
                    let target = mode == "checkpointSymlink" ? f.checkpointFile : f.partial
                    try FileManager.default.removeItem(at: target)
                    if mode == "partialHardlink" { try FileManager.default.linkItem(at: outside, to: target) }
                    else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
                }
                ResumeHTTPProtocol.state.reset(f.fullReply())
                await expect(.invalidDestination) {
                    try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
                }
                XCTAssertTrue(ResumeHTTPProtocol.state.requests.isEmpty)
                let check = mode == "directorySymlink" ? outside.appendingPathComponent("marker") : outside
                XCTAssertEqual(try Data(contentsOf: check), marker)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.output.path))
            }
        }
    }

    func testExistingInstallerStagingFileIsNeverOverwrittenByResume() async throws {
        try await fixture { f in
            _ = try f.seed(prefix: 1_024)
            let original = Data("Existing owner staging bytes".utf8)
            try original.write(to: f.output)
            ResumeHTTPProtocol.state.reset(f.rangeReply(from: 1_024))
            await expect(.invalidDestination) {
                try await f.transport().downloadResumable(f.artifact, to: f.output, checkpointDirectory: f.checkpoint)
            }
            XCTAssertEqual(try Data(contentsOf: f.output), original)
            XCTAssertEqual(try Data(contentsOf: f.partial), Data(f.bytes.prefix(1_024)))
            XCTAssertTrue(ResumeHTTPProtocol.state.requests.isEmpty)
        }
    }

    private func expect(_ expected: ModelTransportError, _ body: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected transfer rejection: \(expected)", file: file, line: line) }
        catch let actual as ModelTransportError { XCTAssertEqual(actual, expected, file: file, line: line) }
        catch { XCTFail("Unexpected transfer category: \(type(of: error))", file: file, line: line) }
    }
    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }
    private func fixture(_ body: (ResumeFixture) async throws -> Void) async throws {
        let f = try ResumeFixture()
        do { try await body(f) }
        catch { try f.remove(); throw error }
        try f.remove()
    }
}

private func resumeDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
private enum ResumeFixtureError: Error { case unsafeCleanup }

private final class ResumeFixture {
    let root: URL
    let modelRoot: URL
    let staging: URL
    let output: URL
    let resumeRoot: URL
    let checkpoint: URL
    let bytes = Data((0..<4_096).map { UInt8($0 % 251) })
    let revision = String(repeating: "a", count: 40)
    let eTag = "\"synthetic-v1\""
    var partial: URL { checkpoint.appendingPathComponent("partial.bin") }
    var checkpointFile: URL { checkpoint.appendingPathComponent("checkpoint.json") }
    var artifact: ModelArtifact {
        .init(role: .summary, fileName: "chosen.gguf", byteCount: Int64(bytes.count), sha256: resumeDigest(bytes),
            downloadURL: URL(string: "https://huggingface.co/example/model/resolve/\(revision)/chosen.gguf")!,
            digestProvenance: .independentlyDownloaded)
    }
    var manifest: ModelManifest {
        .init(modelID: "resume-fixture", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/example/model")!, revision: revision,
            licenseIdentifier: "CC0-1.0", licenseNotice: "Original synthetic bytes; transport/installation only, not inference.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [artifact])
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("LocalMinutesResume-\(UUID().uuidString)", isDirectory: true)
        modelRoot = root.appendingPathComponent("Models", isDirectory: true)
        staging = modelRoot.appendingPathComponent(".staging", isDirectory: true)
        output = staging.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent("chosen.gguf")
        // Inventory enumerates model containers; progress belongs beside the
        // Models root, not inside it or disposable installer staging.
        resumeRoot = root.appendingPathComponent("DownloadResume", isDirectory: true)
        checkpoint = resumeRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: true)
    }
    func transport() -> HTTPSModelTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResumeHTTPProtocol.self]
        return HTTPSModelTransport(stagingRootURL: staging, allowedHosts: ["huggingface.co"],
                                   configuration: configuration, resumeRootURL: resumeRoot)
    }
    func seed(prefix: Int) throws -> ModelDownloadCheckpoint {
        let data = Data(bytes.prefix(prefix))
        try data.write(to: partial)
        let point = ModelDownloadCheckpoint(downloadURL: artifact.downloadURL, revision: revision,
            fileName: artifact.fileName, expectedByteCount: artifact.byteCount, sha256: artifact.sha256,
            strongETag: eTag, receivedByteCount: Int64(prefix), partialSHA256: resumeDigest(data))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(point).write(to: checkpointFile)
        return point
    }
    func readCheckpoint() throws -> ModelDownloadCheckpoint {
        try JSONDecoder().decode(ModelDownloadCheckpoint.self, from: Data(contentsOf: checkpointFile))
    }
    func changeCheckpoint(_ body: (inout [String: Any]) throws -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: checkpointFile)) as? [String: Any])
        try body(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: checkpointFile)
    }
    func fullReply(bytes body: Data? = nil, ending: ResumeEnding = .complete) -> ResumeReply {
        .init(headers: ["Content-Length": "\(bytes.count)", "ETag": eTag, "Accept-Ranges": "bytes"],
              bytes: body ?? bytes, ending: ending)
    }
    func rangeHeaders(from start: Int) -> [String: String] {
        ["Content-Length": "\(bytes.count - start)", "Content-Range": "bytes \(start)-\(bytes.count - 1)/\(bytes.count)",
         "ETag": eTag, "Accept-Ranges": "bytes"]
    }
    func rangeReply(from start: Int) -> ResumeReply {
        .init(status: 206, headers: rangeHeaders(from: start), bytes: Data(bytes.dropFirst(start)))
    }
    func remove() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix("LocalMinutesResume-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              UUID(uuidString: String(root.lastPathComponent.dropFirst("LocalMinutesResume-".count))) != nil else {
            throw ResumeFixtureError.unsafeCleanup
        }
        try FileManager.default.removeItem(at: root)
    }
}
