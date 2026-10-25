import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesModels

private final class TransferEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ModelTransferProgress] = []
    func append(_ event: ModelTransferProgress) { lock.withLock { events.append(event) } }
    var values: [ModelTransferProgress] { lock.withLock { events } }
}

private final class ProgressHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let bytes = Data(repeating: 0x4d, count: 1_048_576)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(Self.bytes.count), "ETag": "\"progress-fixture\""])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for offset in stride(from: 0, to: Self.bytes.count, by: 65_536) {
            client?.urlProtocol(self, didLoad: Self.bytes.subdata(in: offset..<(offset + 65_536)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ModelTransferProgressTests: XCTestCase {
    func testActualHTTPTransferReportsByteProgressThenVerificationBeforeCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-progress-\(UUID().uuidString)", isDirectory: true)
        let staging = root.appendingPathComponent("Models/.staging", isDirectory: true)
        let operation = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resume = root.appendingPathComponent("DownloadResume", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressHTTPProtocol.self]
        let transport = HTTPSModelTransport(stagingRootURL: staging, allowedHosts: ["huggingface.co"],
            configuration: configuration, resumeRootURL: resume)
        let bytes = ProgressHTTPProtocol.bytes
        let artifact = ModelArtifact(role: .summary, fileName: "fixture.gguf", byteCount: Int64(bytes.count),
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            downloadURL: URL(string: "https://huggingface.co/example/progress/resolve/\(String(repeating: "a", count: 40))/fixture.gguf")!,
            digestProvenance: .independentlyDownloaded)
        let log = TransferEvents()
        let output = operation.appendingPathComponent(artifact.fileName)
        try await transport.downloadResumable(artifact, to: output,
            checkpointDirectory: resume.appendingPathComponent(UUID().uuidString, isDirectory: true),
            progress: { log.append($0) })
        let events = log.values
        XCTAssertEqual(try Data(contentsOf: output), bytes)
        XCTAssertTrue(events.contains { $0.stage == .downloading && $0.completedBytes > 0 && $0.completedBytes < $0.totalBytes },
            "The real HTTP callback must publish intermediate byte progress, not only an indeterminate spinner")
        XCTAssertTrue(events.contains { $0.stage == .verifying }, "Checksum/copy work needs its own visible stage")
        XCTAssertEqual(events.last?.stage, .completed, "Completion is only reported after verified staging publication")
        XCTAssertEqual(events.last?.completedBytes, Int64(bytes.count))
        XCTAssertTrue(events.allSatisfy { $0.fileName == artifact.fileName && $0.totalBytes == Int64(bytes.count) })
        let download = events.filter { $0.stage == .downloading }
        XCTAssertEqual(download.map(\.completedBytes), download.map(\.completedBytes).sorted())
        XCTAssertTrue(download.contains { ($0.bytesPerSecond ?? 0) > 0 && ($0.remainingSeconds ?? -1) >= 0 },
            "Available speed and time remaining must describe observed bytes, not invented values")
    }
}
