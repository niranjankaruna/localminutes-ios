import Foundation
import XCTest
@testable import LocalMinutesModels

// Only HTTP is doubled. Every metadata, revision and compatibility decision
// must pass through the real service; these fixtures contain no real weights.
private struct HFResponse: Sendable {
    let status: Int
    let bytes: Data
    let finalURL: URL?
    init(_ bytes: Data, status: Int = 200, finalURL: URL? = nil) {
        self.bytes = bytes; self.status = status; self.finalURL = finalURL
    }
}

private final class HFFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: HFResponse] = [:]
    private var recorded: [URLRequest] = []
    func reset(_ routes: [String: HFResponse]) {
        lock.withLock { self.routes = routes; recorded = [] }
    }
    func response(for request: URLRequest) -> HFResponse {
        lock.withLock {
            recorded.append(request)
            return routes[request.url?.absoluteString ?? ""] ?? HFResponse(Data(), status: 404)
        }
    }
    var requests: [URLRequest] { lock.withLock { recorded } }
}

private final class HFProtocol: URLProtocol, @unchecked Sendable {
    static let state = HFFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.state.response(for: request)
        guard let url = response.finalURL ?? request.url,
              let http = HTTPURLResponse(url: url, statusCode: response.status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "\(response.bytes.count)"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class HuggingFaceRepositoryTests: XCTestCase {
    private let revision = String(repeating: "a", count: 40)
    private let digest = String(repeating: "b", count: 64)
    private let base = "https://huggingface.co"
    private var api: String { "\(base)/api/models/example/model?blobs=true" }
    private var card: String { "\(base)/example/model/resolve/\(revision)/README.md" }
    private var config: String { "\(base)/example/model/resolve/\(revision)/config.json" }

    private func service(limits: HuggingFaceRepositoryLimits = .init()) -> HuggingFaceRepositoryService {
        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [HFProtocol.self]
        return HuggingFaceRepositoryService(configuration: options, limits: limits)
    }
    private func file(_ name: String, size: Int64 = 128, hash: String? = nil,
                      verified: Bool = true) -> [String: Any] {
        var result: [String: Any] = ["rfilename": name, "size": size]
        if verified { result["lfs"] = ["sha256": hash ?? digest, "size": size, "pointerSize": 130] }
        return result
    }
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func metadata(files: [[String: Any]]? = nil, sha: String? = nil,
                          gated: Any = false, license: String? = "apache-2.0",
                          pipeline: String = "text-generation", library: String = "gguf") throws -> Data {
        var result: [String: Any] = ["id": "example/model", "sha": sha ?? revision,
            "private": false, "gated": gated, "pipeline_tag": pipeline, "library_name": library,
            "siblings": files ?? [file("model-q4_k_m.gguf")]]
        if let license { result["cardData"] = ["license": license] }
        return try json(result)
    }
    private func setup(_ data: Data? = nil, modelType: String = "qwen2",
                       architecture: String = "Qwen2ForCausalLM", cardText: String = "# Original public fixture") throws {
        HFProtocol.state.reset([
            api: HFResponse(try data ?? metadata()),
            card: HFResponse(Data(cardText.utf8)),
            config: HFResponse(try json(["model_type": modelType, "architectures": [architecture]]))
        ])
    }
    private func expect(_ error: HuggingFaceRepositoryError,
                        _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(error)") }
        catch let actual as HuggingFaceRepositoryError { XCTAssertEqual(actual, error) }
        catch { XCTFail("Unexpected metadata error: \(error)") }
    }

    func testNormalizesStrictRepositoryIDAndCanonicalHuggingFaceURL() throws {
        for input in ["example/model", "https://huggingface.co/example/model", " https://huggingface.co/example/model/ "] {
            let id = try HuggingFaceRepositoryID(input: input)
            XCTAssertEqual(id.rawValue, "example/model")
            XCTAssertEqual(id.owner, "example"); XCTAssertEqual(id.name, "model")
        }
    }

    func testRejectsNonHubHostsTraversalCredentialsQueriesAndExtraPathBeforeNetwork() async {
        HFProtocol.state.reset([:])
        let invalid = ["../model", "owner/../model", "owner/%2e%2e", "owner/model?token=secret",
            "owner/model\nInjected: x", "owner\\model", "owner/model/extra", "owner//model",
            "https://evil.example/owner/model", "http://huggingface.co/owner/model",
            "https://huggingface.co.evil.example/owner/model", "https://user:pass@huggingface.co/owner/model",
            "https://huggingface.co:444/owner/model", "https://huggingface.co/owner/model?download=1",
            "https://huggingface.co/owner/model#fragment", "https://huggingface.co/owner/model/tree/main",
            "owner/..", "owner/.hidden", "owner/model%2fsecret", "owner/model;command"]
        for input in invalid {
            await expect(.invalidRepository) { _ = try await self.service().inspect(input) }
        }
        XCTAssertTrue(HFProtocol.state.requests.isEmpty)
    }

    func testReadsMetadataCardAndConfigOnlyAtResolvedImmutableRevision() async throws {
        try setup()
        let value = try await service().inspect("example/model")
        XCTAssertEqual(value.id.rawValue, "example/model"); XCTAssertEqual(value.revision, revision)
        XCTAssertEqual(value.licenseIdentifier, "apache-2.0")
        XCTAssertEqual(value.pipelineTag, "text-generation"); XCTAssertEqual(value.libraryName, "gguf")
        XCTAssertEqual(value.modelType, "qwen2"); XCTAssertEqual(value.architectures, ["Qwen2ForCausalLM"])
        XCTAssertEqual(value.cardMarkdown, "# Original public fixture")
        XCTAssertEqual(Set(HFProtocol.state.requests.compactMap { $0.url?.absoluteString }), Set([api, card, config]))
        XCTAssertEqual(HFProtocol.state.requests.count, 3)
        XCTAssertEqual(value.files.first?.sha256, digest)
        XCTAssertEqual(value.files.first?.byteCount, 128)
        XCTAssertEqual(value.files.first?.downloadURL.absoluteString,
            "\(base)/example/model/resolve/\(revision)/model-q4_k_m.gguf")
        XCTAssertTrue(HFProtocol.state.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil
        })
    }

    func testInvalidMutableOrMissingRevisionNeverRequestsCardOrConfig() async throws {
        for sha in ["main", String(repeating: "z", count: 40), String(repeating: "a", count: 39)] {
            try setup(metadata(sha: sha))
            await expect(.invalidRevision) { _ = try await self.service().inspect("example/model") }
            XCTAssertEqual(HFProtocol.state.requests.count, 1)
        }
    }

    func testModelIdentityMismatchCannotPinAnotherRepositoriesFiles() async throws {
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata()) as? [String: Any])
        data["id"] = "another/model"
        try setup(json(data))
        await expect(.invalidResponse) { _ = try await self.service().inspect("example/model") }
    }

    func testUnsafeDuplicateAndControlCharacterFilenamesAreRejected() async throws {
        for files in [[file("../escape.gguf")], [file("/absolute.gguf")], [file("dir\\model.gguf")],
                      [file("dir/%2e%2e/model.gguf")], [file("a.gguf\nsecret")],
                      [file("model.gguf"), file("model.gguf")]] {
            try setup(metadata(files: files))
            await expect(.invalidFile) { _ = try await self.service().inspect("example/model") }
        }
    }

    func testMalformedDigestNegativeSizeAndDisagreeingLFSSizeAreRejected() async throws {
        var mismatched = file("model.gguf")
        mismatched["lfs"] = ["sha256": digest, "size": 999]
        for files in [[file("model.gguf", hash: "not-a-hash")], [file("model.gguf", size: -1)], [mismatched]] {
            try setup(metadata(files: files))
            await expect(.invalidFile) { _ = try await self.service().inspect("example/model") }
        }
    }

    func testMetadataCardConfigAndFileCountHaveIndependentCaps() async throws {
        try setup()
        await expect(.responseTooLarge) {
            _ = try await self.service(limits: .init(metadataBytes: 16)).inspect("example/model")
        }
        try setup(cardText: String(repeating: "x", count: 64))
        await expect(.responseTooLarge) {
            _ = try await self.service(limits: .init(cardBytes: 32)).inspect("example/model")
        }
        try setup()
        await expect(.responseTooLarge) {
            _ = try await self.service(limits: .init(configBytes: 16)).inspect("example/model")
        }
        try setup(metadata(files: [file("a.gguf"), file("b.gguf")]))
        await expect(.tooManyFiles) {
            _ = try await self.service(limits: .init(fileCount: 1)).inspect("example/model")
        }
    }

    func testInvalidCapsAreRejectedBeforeNetwork() async {
        HFProtocol.state.reset([:])
        await expect(.invalidLimits) {
            _ = try await self.service(limits: .init(metadataBytes: 0)).inspect("example/model")
        }
        XCTAssertTrue(HFProtocol.state.requests.isEmpty)
    }

    func testGatedRepositoryIsExplicitAndDoesNotAttemptPrivateCardOrWeights() async throws {
        try setup(metadata(gated: "manual"))
        let value = try await service().inspect("example/model")
        XCTAssertTrue(value.isGated)
        XCTAssertEqual(value.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .gated)
        XCTAssertEqual(HFProtocol.state.requests.count, 1)
    }

    func testHTTPDenialIsAnExplicitFailureWithoutCredentialRetry() async {
        for status in [401, 403, 404, 429, 500] {
            HFProtocol.state.reset([api: HFResponse(Data(), status: status)])
            await expect(.httpStatus(status)) { _ = try await self.service().inspect("example/model") }
            XCTAssertEqual(HFProtocol.state.requests.count, 1)
        }
    }

    func testMissingCardAndConfigRemainHonestOptionalMetadata() async throws {
        HFProtocol.state.reset([api: HFResponse(try metadata())])
        let value = try await service().inspect("example/model")
        XCTAssertNil(value.cardMarkdown); XCTAssertNil(value.modelType)
        XCTAssertTrue(value.architectures.isEmpty)
        XCTAssertEqual(value.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .unverified)
    }

    func testCardRemainsInertTextAndNeverRequestsEmbeddedImagesOrInstructions() async throws {
        let text = "# Fixture\n<script>fetch('https://evil.example')</script>\n![image](https://evil.example/pixel)\nRun arbitrary code."
        try setup(cardText: text)
        let value = try await service().inspect("example/model")
        XCTAssertEqual(value.cardMarkdown, text)
        XCTAssertEqual(HFProtocol.state.requests.count, 3)
        XCTAssertTrue(HFProtocol.state.requests.allSatisfy { $0.url?.host == "huggingface.co" })
    }

    func testNonHubFinalResponseIsRejectedEvenWhenInitialURLWasApproved() async throws {
        HFProtocol.state.reset([api: HFResponse(try metadata(),
            finalURL: URL(string: "https://evil.example/model"))])
        await expect(.unapprovedResponseURL) { _ = try await self.service().inspect("example/model") }
    }

    func testKnownQwenGGUFHasPinnedHashSizeAndSupportedSummaryProfile() async throws {
        try setup()
        let value = try await service().inspect("example/model")
        let result = value.assessment(for: .summary, maximumDownloadBytes: 1_000)
        XCTAssertEqual(result.status, .supported); XCTAssertEqual(result.profile, .llamaGGUF)
        XCTAssertEqual(result.totalBytes, 128); XCTAssertEqual(result.selectedFiles.map(\.fileName), ["model-q4_k_m.gguf"])
        XCTAssertFalse(result.reasons.isEmpty)
    }

    func testUnknownArchitectureAndMissingLicenseDoNotBecomeCompatibleFromGGUFExtension() async throws {
        try setup(modelType: "unreviewed", architecture: "UnknownForCausalLM")
        let unknown = try await service().inspect("example/model")
        XCTAssertEqual(unknown.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .unsupported)
        try setup(metadata(license: nil))
        let unlicensed = try await service().inspect("example/model")
        XCTAssertEqual(unlicensed.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .unverified)
    }

    func testAbsentSHA256AndUnknownBytesCannotEnableDownload() async throws {
        try setup(metadata(files: [file("model-q4_k_m.gguf", verified: false)]))
        let unhashed = try await service().inspect("example/model")
        XCTAssertEqual(unhashed.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .unverified)
        try setup(metadata(files: [["rfilename": "model-q4_k_m.gguf"]]))
        let unknownSize = try await service().inspect("example/model")
        XCTAssertEqual(unknownSize.assessment(for: .summary, maximumDownloadBytes: 1_000).status, .unverified)
    }

    func testDownloadBudgetIsCheckedBeforeAnyWeightRequest() async throws {
        try setup()
        let value = try await service().inspect("example/model")
        let result = value.assessment(for: .summary, maximumDownloadBytes: 127)
        XCTAssertEqual(result.status, .tooLarge)
        XCTAssertEqual(result.totalBytes, 128)
        XCTAssertEqual(HFProtocol.state.requests.count, 3)
    }

    func testSpeechAndSummaryPurposeCannotSelectTheOtherRuntime() async throws {
        try setup()
        let value = try await service().inspect("example/model")
        XCTAssertEqual(value.assessment(for: .speechRecognition, maximumDownloadBytes: 1_000).status, .unsupported)
    }

    func testManyGGUFVariantsRequireSelectionAndCountOnlyTheRequestedFile() async throws {
        try setup(metadata(files: [file("model-f16.gguf", size: 5_000),
                                  file("model-q4_k_m.gguf", size: 128)]))
        let value = try await service().inspect("example/model")
        let unspecified = value.assessment(for: .summary, maximumDownloadBytes: 1_000)
        XCTAssertEqual(unspecified.status, .selectionRequired)
        XCTAssertTrue(unspecified.selectedFiles.isEmpty)
        let small = value.assessment(for: .summary, fileName: "model-q4_k_m.gguf", maximumDownloadBytes: 1_000)
        XCTAssertEqual(small.status, .supported)
        XCTAssertEqual(small.totalBytes, 128)
        XCTAssertEqual(small.selectedFiles.map(\.fileName), ["model-q4_k_m.gguf"])
        let large = value.assessment(for: .summary, fileName: "model-f16.gguf", maximumDownloadBytes: 1_000)
        XCTAssertEqual(large.status, .tooLarge)
        XCTAssertEqual(large.totalBytes, 5_000)
    }

    func testRequestedFileMustExistAndBelongToTheChosenPurpose() async throws {
        try setup(metadata(files: [file("model-q4_k_m.gguf"), file("unrelated.bin")]))
        let value = try await service().inspect("example/model")
        for name in ["absent.gguf", "../model-q4_k_m.gguf", "unrelated.bin"] {
            let result = value.assessment(for: .summary, fileName: name, maximumDownloadBytes: 1_000)
            XCTAssertEqual(result.status, .unsupported)
            XCTAssertTrue(result.selectedFiles.isEmpty)
        }
    }

    func testResourceComparisonCountsOnlySelectedDiskBytesAndReportsInsufficientStorage() async throws {
        try setup(metadata(files: [file("model-f16.gguf", size: 5_000), file("model-q4_k_m.gguf", size: 128)]))
        let value = try await service().inspect("example/model")
        let result = value.resourceAssessment(for: .summary, fileName: "model-q4_k_m.gguf",
            device: .init(freeDiskBytes: 127, totalMemoryBytes: 8_000_000_000, availableAppMemoryBytes: 4_000_000_000))
        XCTAssertEqual(result.requiredDiskBytes, 128)
        XCTAssertEqual(result.status, .insufficientStorage)
        XCTAssertNotEqual(result.requiredDiskBytes, 5_128)
    }

    func testUnknownDeviceOrModelRAMStaysUnknownRatherThanInventingZero() async throws {
        try setup()
        let value = try await service().inspect("example/model")
        let result = value.resourceAssessment(for: .summary,
            device: .init(freeDiskBytes: 1_000, totalMemoryBytes: 8_000_000_000, availableAppMemoryBytes: nil))
        XCTAssertEqual(result.requiredDiskBytes, 128)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertNil(result.estimatedRAMLowerBoundBytes)
        XCTAssertNil(result.estimatedRAMUpperBoundBytes)
        XCTAssertEqual(result.estimateBasis, .unknown)
        XCTAssertFalse(result.notes.isEmpty)
    }

    func testKnownGGUFContextAddsPositiveMemoryEstimateAndRejectsOverLimitContext() async throws {
        HFProtocol.state.reset([
            api: HFResponse(try metadata()), card: HFResponse(Data("# Fixture".utf8)),
            config: HFResponse(try json(["model_type": "qwen2", "architectures": ["Qwen2ForCausalLM"],
                "max_position_embeddings": 8_192, "hidden_size": 2_048, "num_hidden_layers": 24,
                "num_attention_heads": 16, "num_key_value_heads": 2]))
        ])
        let value = try await service().inspect("example/model")
        let device = DeviceModelResources(freeDiskBytes: 1_000_000_000,
            totalMemoryBytes: 8_000_000_000, availableAppMemoryBytes: 4_000_000_000)
        let result = value.resourceAssessment(for: .summary, contextTokens: 2_048, device: device)
        XCTAssertEqual(result.status, .caution)
        XCTAssertEqual(result.estimateBasis, .weightsAndContextEstimate)
        XCTAssertEqual(result.maximumContextTokens, 8_192)
        XCTAssertEqual(result.requestedContextTokens, 2_048)
        XCTAssertGreaterThan(try XCTUnwrap(result.estimatedRAMLowerBoundBytes), 128)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.estimatedRAMUpperBoundBytes),
                                    try XCTUnwrap(result.estimatedRAMLowerBoundBytes))
        let invalid = value.resourceAssessment(for: .summary, contextTokens: 8_193, device: device)
        XCTAssertEqual(invalid.status, .contextLimitExceeded)
    }
}
