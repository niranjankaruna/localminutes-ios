import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesModels

// The real URLSession/HTTP handling and actual destination filesystem are tested.
// URLProtocol doubles only the server response. No model/inference is fabricated.
private struct HTTPFixtureResponse: Sendable {
    let status: Int
    let bytes: Data
    let delay: TimeInterval
    let finalURL: URL?

    init(status: Int = 200, bytes: Data = Data("original model transport fixture".utf8),
         delay: TimeInterval = 0, finalURL: URL? = nil) {
        self.status = status; self.bytes = bytes; self.delay = delay; self.finalURL = finalURL
    }
}

private final class HTTPFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var response = HTTPFixtureResponse()
    private var requests: [URLRequest] = []
    private var cancellations = 0

    func configure(_ response: HTTPFixtureResponse) {
        lock.withLock { self.response = response; requests = []; cancellations = 0 }
    }
    func begin(_ request: URLRequest) -> HTTPFixtureResponse {
        lock.withLock { requests.append(request); return response }
    }
    func cancel() { lock.withLock { cancellations += 1 } }
    var requestCount: Int { lock.withLock { requests.count } }
    var cancellationCount: Int { lock.withLock { cancellations } }
}

private final class HTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = HTTPFixtureState()
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.state.begin(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            guard let url = response.finalURL ?? self.request.url,
                  let http = HTTPURLResponse(url: url, statusCode: response.status,
                    httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(response.bytes.count)"]) else { return }
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.bytes)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        lock.withLock { stopped = true }
        Self.state.cancel()
    }
}

private final class RedirectRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    func set(_ request: URLRequest?) { lock.withLock { stored = request } }
    var value: URLRequest? { lock.withLock { stored } }
}

@MainActor
final class HTTPSModelTransportTests: XCTestCase {
    private let fixture = Data("original model transport fixture".utf8)

    private func artifact(url: URL? = nil, byteCount: Int64? = nil) -> ModelArtifact {
        ModelArtifact(role: .encoder, fileName: "encoder.onnx", byteCount: byteCount ?? Int64(fixture.count),
            sha256: SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined(),
            downloadURL: url ?? URL(string: "https://huggingface.co/example/model/resolve/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/encoder.onnx")!,
            digestProvenance: .independentlyDownloaded)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPFixtureProtocol.self]
        return configuration
    }

    private func ownedDirectory() throws -> (root: URL, staging: URL, output: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("localminutes-transport-test-\(UUID().uuidString)", isDirectory: true)
        let staging = root.appendingPathComponent(".staging", isDirectory: true)
        let operation = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: true)
        return (root, staging, operation.appendingPathComponent("encoder.onnx"))
    }

    private func cleanup(_ root: URL) throws {
        guard root.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-transport-test-") else {
            XCTFail("Unsafe fixture cleanup"); return
        }
        try FileManager.default.removeItem(at: root)
    }

    private func expect(_ expected: ModelTransportError, _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(expected)") }
        catch let actual as ModelTransportError { XCTAssertEqual(actual, expected) }
        catch { XCTFail("Unexpected transport error: \(error)") }
    }

    func testActualURLSessionWritesNonemptyServerBytesOnlyToOwnedStaging() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture))
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        try await transport.download(artifact(), to: h.output)
        XCTAssertEqual(try Data(contentsOf: h.output), fixture)
        XCTAssertEqual(HTTPFixtureProtocol.state.requestCount, 1)
    }

    func testHTTPStatusFailureCannotPublishAStagingFile() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(status: 403, bytes: fixture))
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        await expect(.httpStatus(403)) { try await transport.download(self.artifact(), to: h.output) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.output.path))
    }

    func testShortAndOversizedResponsesFailBeforeAFileCanBeInstalled() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        for count in [1, fixture.count + 1] {
            HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: Data(repeating: 1, count: count)))
            await expect(.sizeMismatch) { try await transport.download(self.artifact(), to: h.output) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.output.path))
        }
    }

    func testPlainHTTPAndUnapprovedInitialHostsAreRejectedBeforeNetwork() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        for (url, error) in [("http://huggingface.co/model.onnx", ModelTransportError.insecureURL),
                             ("https://unreviewed.example/model.onnx", .unapprovedHost)] {
            HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture))
            await expect(error) {
                try await transport.download(self.artifact(url: URL(string: url)!), to: h.output)
            }
            XCTAssertEqual(HTTPFixtureProtocol.state.requestCount, 0)
        }
    }

    func testFinalResponseURLMustRemainHTTPSOnAnApprovedDistributionHost() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture,
            finalURL: URL(string: "https://unreviewed.example/model.onnx")))
        await expect(.unapprovedHost) { try await transport.download(self.artifact(), to: h.output) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.output.path))
    }

    func testUnownedOrSymlinkedDestinationCannotBeWritten() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture))
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        let outside = h.root.appendingPathComponent("outside.onnx")
        await expect(.invalidDestination) { try await transport.download(self.artifact(), to: outside) }
        let outsideFolder = h.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: false)
        let linkedOperation = h.staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedOperation, withDestinationURL: outsideFolder)
        await expect(.invalidDestination) {
            try await transport.download(self.artifact(), to: linkedOperation.appendingPathComponent("encoder.onnx"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outsideFolder.path).isEmpty)
        XCTAssertEqual(HTTPFixtureProtocol.state.requestCount, 0)
    }

    func testExistingDestinationIsNeverOverwritten() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        let previous = Data("previous verified bytes".utf8)
        try previous.write(to: h.output)
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture))
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        await expect(.invalidDestination) { try await transport.download(self.artifact(), to: h.output) }
        XCTAssertEqual(try Data(contentsOf: h.output), previous)
        XCTAssertEqual(HTTPFixtureProtocol.state.requestCount, 0)
    }

    func testCallerCancellationCancelsActualURLSessionTaskAndLeavesNoOutput() async throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        HTTPFixtureProtocol.state.configure(HTTPFixtureResponse(bytes: fixture, delay: 5))
        let transport = HTTPSModelTransport(stagingRootURL: h.staging,
            allowedHosts: ["huggingface.co"], configuration: configuration())
        let candidate = artifact()
        let task = Task { try await transport.download(candidate, to: h.output) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while HTTPFixtureProtocol.state.requestCount == 0 && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(HTTPFixtureProtocol.state.requestCount, 1)
        task.cancel()
        do { try await task.value; XCTFail("Cancelled download reported success") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation must remain distinguishable: \(error)") }
        XCTAssertGreaterThanOrEqual(HTTPFixtureProtocol.state.cancellationCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.output.path))
    }

    func testRedirectDelegateApprovesOnlyReviewedHTTPSHosts() throws {
        let session = URLSession(configuration: configuration())
        defer { session.invalidateAndCancel() }
        let original = artifact().downloadURL
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 302,
            httpVersion: "HTTP/1.1", headerFields: nil))
        let policy = ModelDownloadRedirectPolicy(allowedHosts: ["huggingface.co", "cdn-lfs-us-1.hf.co"])
        for (address, permitted) in [("https://cdn-lfs-us-1.hf.co/model.onnx", true),
            ("http://cdn-lfs-us-1.hf.co/model.onnx", false),
            ("https://cdn-lfs-us-1.hf.co.attacker.example/model.onnx", false),
            ("https://unreviewed.example/model.onnx", false)] {
            let box = RedirectRequestBox()
            policy.urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: URL(string: address)!)) { box.set($0) }
            XCTAssertEqual(box.value != nil, permitted)
        }
    }

    func testRealStorageCapacityQueryReturnsNonnegativeCapacityForPersistentDirectory() throws {
        let h = try ownedDirectory(); defer { try? cleanup(h.root) }
        XCTAssertGreaterThanOrEqual(try ModelStoragePolicy.availableBytes(at: h.root), 0)
    }
}
