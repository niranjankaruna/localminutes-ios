import CryptoKit
import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

func intelligenceUUID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "18000000-0000-0000-0000-%012d", number))!
}

@MainActor
struct IntelligenceFixture {
    let root: URL
    let database: URL
    let sourceDirectory: URL
    let store: SQLiteMeetingStore
    let models: ModelInstallationManager
    let admission: HeavyModelAdmission
    let manifest: ModelManifest
    let selected: UUID
    let other: UUID
    let segments: [StoredTranscriptSegment]
    let otherSegments: [StoredTranscriptSegment]
    let note: StoredManualNote

    static func create(actualModel: URL? = nil, manifestOverride: ModelManifest? = nil,
                       importActualDirectoryDirectly: Bool = false, extendedSummarySource: Bool = false) async throws -> IntelligenceFixture {
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("localminutes-intelligence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var openedStore: SQLiteMeetingStore?
        do {
        if let manifestOverride {
            guard actualModel != nil, manifestOverride.purpose == .summary, manifestOverride.artifacts.count == 1,
                  let artifact = manifestOverride.artifacts.first, artifact.role == .summary,
                  !artifact.fileName.contains("/"), !artifact.fileName.contains("\\"),
                  artifact.fileName != ".", artifact.fileName != ".." else { throw IntelligenceSessionError.invalidModel }
        }
        let name = manifestOverride?.artifacts.first?.fileName
            ?? (actualModel == nil ? "boundary-model.gguf" : "qwen2.5-1.5b-instruct-q4_k_m.gguf")
        let source: URL
        if importActualDirectoryDirectly {
            guard let actualModel, manifestOverride != nil, actualModel.isFileURL,
                  actualModel.lastPathComponent == name else { throw IntelligenceSessionError.invalidModel }
            // The catalogue downloader isolates each reviewed variant in a
            // single-file directory. Import directly to avoid a third multi-GB
            // copy; the real installer still hashes the source and owned copy.
            source = actualModel.deletingLastPathComponent()
        } else {
            source = root.appendingPathComponent("import", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        }
        let file = source.appendingPathComponent(name)
        if !importActualDirectoryDirectly {
            if let actualModel { try FileManager.default.copyItem(at: actualModel, to: file) }
            else { try Data("Original nonsense bytes: file-integrity fixture, never inference.".utf8).write(to: file) }
        }
        let handle = try FileHandle(forReadingFrom: file)
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        try handle.close()
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? -1
        if actualModel != nil && manifestOverride == nil {
            XCTAssertEqual(size, 1_117_320_736)
            XCTAssertEqual(digest, "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e")
            guard size == 1_117_320_736,
                  digest == "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e" else {
                throw IntelligenceSessionError.invalidModel
            }
        }
        if let artifact = manifestOverride?.artifacts.first {
            XCTAssertEqual(size, artifact.byteCount)
            XCTAssertEqual(digest, artifact.sha256)
            guard size == artifact.byteCount, digest == artifact.sha256 else { throw IntelligenceSessionError.invalidModel }
        }
        let revision = actualModel == nil ? String(repeating: "a", count: 40) : "91cad51170dc346986eccefdc2dd33a9da36ead9"
        let repository = actualModel == nil ? "https://huggingface.co/example/original-boundary-fixture"
            : "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF"
        let manifest = manifestOverride ?? ModelManifest(modelID: actualModel == nil ? "boundary-summary" : "qwen2.5-1.5b-instruct-q4_k_m",
            purpose: .summary, upstreamRepository: URL(string: repository)!, revision: revision,
            licenseIdentifier: actualModel == nil ? "CC0-1.0" : "Apache-2.0",
            licenseNotice: actualModel == nil ? "Original non-model bytes dedicated to CC0-1.0."
                : "Qwen2.5-1.5B-Instruct by the Qwen team, Alibaba Cloud. Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0. Original model and license: https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF.",
            runtimeVersion: actualModel == nil ? "boundary-runtime" : "llama.cpp-b5046",
            artifacts: [.init(role: .summary, fileName: name, byteCount: size, sha256: digest,
                downloadURL: URL(string: repository + "/resolve/" + revision + "/" + name)!,
                digestProvenance: .independentlyDownloaded)])
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
                                               availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        _ = try await models.importDirectory(source, manifest: manifest)
        let database = root.appendingPathComponent("meetings.sqlite")
        let store = try SQLiteMeetingStore(databaseURL: database)
        openedStore = store
        let selected = intelligenceUUID(1), other = intelligenceUUID(2)
        for id in [selected, other] {
            try await store.createMeeting(.init(id: id, title: "Original synthetic meeting",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed, capturedSampleCount: 32_000))
        }
        let context = extendedSummarySource ? String(repeating: " The team reviewed the meeting agenda.", count: 12) : ""
        let segments = [
            StoredTranscriptSegment(id: intelligenceUUID(11), meetingID: selected, sequence: 0,
                startSample: 0, endSample: 16_000, text: "Maya: We decided to ship the prototype on Friday." + context, modelRevision: "original-ASR"),
            StoredTranscriptSegment(id: intelligenceUUID(12), meetingID: selected, sequence: 1,
                startSample: 16_000, endSample: 32_000, text: "Leo: I will write the guide by Thursday." + context, modelRevision: "original-ASR")
        ]
        let otherSegments = [StoredTranscriptSegment(id: intelligenceUUID(21), meetingID: other, sequence: 0,
            startSample: 0, endSample: 16_000, text: "Other meeting canary: Nolan owns the telescope task.", modelRevision: "other-ASR")]
        try await store.appendFinalizedSegments(segments, to: selected)
        try await store.appendFinalizedSegments(otherSegments, to: other)
        let note = StoredManualNote(meetingID: selected, text: "Original manual note — Café 📝.",
                                  editRevision: 3, modifiedAt: Date(timeIntervalSince1970: 2_000))
        try await store.saveManualNote(note)
        return .init(root: root, database: database, sourceDirectory: source, store: store, models: models,
                     admission: HeavyModelAdmission(), manifest: manifest, selected: selected, other: other,
                     segments: segments, otherSegments: otherSegments, note: note)
        } catch {
            try? await openedStore?.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func closeAndRemove() async throws {
        try await store.close()
        let parent = FileManager.default.temporaryDirectory.standardizedFileURL.path
        guard root.deletingLastPathComponent().standardizedFileURL.path == parent,
              root.lastPathComponent.hasPrefix("localminutes-intelligence-") else { throw IntelligenceSessionError.invalidModel }
        try FileManager.default.removeItem(at: root)
    }

    func request(_ operation: IntelligenceOperation, otherMeeting: Bool = false) -> IntelligenceRequest {
        .init(meetingID: otherMeeting ? other : selected, operation: operation,
              createdAt: Date(timeIntervalSince1970: 3_000))
    }

    func rawSummary() throws -> String {
        // These two short, contiguous original segments form source unit 0.
        // Generated prose intentionally differs from its hidden evidence.
        let bullets: [[String: Any]] = [
            ["text": "The team agreed to ship the prototype on Friday.", "source_ids": [0]],
            ["text": "Leo committed to writing the guide by Thursday.", "source_ids": [0]]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["bullets": bullets,
            "overview": ["text": "The team aligned the prototype release and its documentation schedule.",
                         "source_ids": [0]]], options: [.sortedKeys]), as: UTF8.self)
    }

    func summaryReplies() throws -> [String] {
        [try rawSummary()] + Array(repeating: "{\"issues\":[]}", count: 3)
    }

    func rawAnswer() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["status": "supported_quote",
            "source_id": segments[1].id.uuidString, "quote": segments[1].text], options: [.sortedKeys]), as: UTF8.self)
    }


}

/// The actual runtime and boundary-fixture tests share output/evidence checks.
/// These assertions do not turn mocked semantic verdicts into model-quality evidence.
@MainActor
func assertNarrativeFixtureSummary(_ saved: StoredGeneratedDocument, fixture h: IntelligenceFixture,
                                   revision: String) throws {
    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved.originalJSON) as? [String: Any])
    XCTAssertEqual(object["schema_version"] as? Int, 2)
    XCTAssertEqual(object["meeting_id"] as? String, h.selected.uuidString)
    XCTAssertEqual(saved.promptVersion, AdaptiveSummaryPipeline.currentPromptVersion)
    XCTAssertNil(object["summary_points"]); XCTAssertNil(object["decisions"]); XCTAssertNil(object["actions"])
    let bullets = try XCTUnwrap(object["bullets"] as? [[String: Any]])
    let overview = try XCTUnwrap(object["overview"] as? [String: Any])
    let prose = bullets.compactMap { $0["text"] as? String }.map { $0.lowercased() }
    XCTAssertTrue(prose.contains { $0.contains("prototype") && $0.contains("friday") })
    XCTAssertTrue(prose.contains { $0.contains("guide") && $0.contains("leo") && $0.contains("thursday") })
    XCTAssertTrue(saved.editedText.hasPrefix("Overview\n"))
    XCTAssertTrue(saved.editedText.contains("\n\n• "))
    XCTAssertFalse(saved.editedText.contains("Decision:"))
    XCTAssertFalse(saved.editedText.contains("Action:"))
    XCTAssertFalse(String(decoding: saved.originalJSON, as: UTF8.self).contains("telescope"))
    for item in [overview] + bullets {
        let text = try XCTUnwrap(item["text"] as? String)
        XCTAssertFalse(h.segments.contains { $0.text == text }, "Narrative prose must not be a copied transcript row")
        let evidence = try XCTUnwrap(item["evidence"] as? [[String: Any]])
        XCTAssertFalse(evidence.isEmpty)
        for citation in evidence {
            let id = try XCTUnwrap(citation["source_id"] as? String)
            let source = try XCTUnwrap(h.segments.first { $0.id.uuidString == id })
            let quote = try XCTUnwrap(citation["quote"] as? String)
            XCTAssertFalse(quote.isEmpty)
            XCTAssertNotNil(Data(source.text.utf8).range(of: Data(quote.utf8)))
            XCTAssertEqual((citation["start_sample"] as? NSNumber)?.int64Value, source.startSample)
            XCTAssertEqual((citation["end_sample"] as? NSNumber)?.int64Value, source.endSample)
        }
    }
    let provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
    XCTAssertEqual(provenance["model_revision"] as? String, revision)
    XCTAssertEqual(provenance["prompt_version"] as? String, AdaptiveSummaryPipeline.currentPromptVersion)
    XCTAssertEqual((provenance["map_index"] as? NSNumber)?.intValue, 0)
}

private enum IntelligenceFixtureError: Error {
    case missingReply, missingRuntime
}

// Only the async inference/load boundaries are doubled. They do not release any
// model/gate lease or save a document: the real service must perform that work.
actor IntelligenceBoundaryRuntime: IntelligenceRuntime {
    nonisolated let contextTokenLimit: Int
    nonisolated let outputTokenLimit: Int
    private let tokenCount: Int
    private var replies: [String]
    private var holdGeneration: Bool
    private var holdUnload: Bool
    private var generationReleased = false
    private var unloadReleased = false
    private(set) var generating = false
    private(set) var unloading = false
    private(set) var unloaded = false
    private(set) var events: [String] = []
    private(set) var requestedMaximumTokens: [Int] = []
    private(set) var prompts: [String] = []
    init(replies: [String], holdGeneration: Bool = false, holdUnload: Bool = false,
         contextTokenLimit: Int = 4_096, tokenCount: Int = 500, outputTokenLimit: Int = 1_024) {
        self.replies = replies; self.holdGeneration = holdGeneration; self.holdUnload = holdUnload
        self.contextTokenLimit = contextTokenLimit; self.tokenCount = tokenCount
        self.outputTokenLimit = outputTokenLimit
    }
    func promptTokenCount(prompt: String) async throws -> Int { try Task.checkCancellation(); return tokenCount }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int,
                      progress: SummaryGenerationProgressReporter?) async throws -> String {
        progress?(.promptTokens(completed: 128, total: 500))
        progress?(.promptTokens(completed: 500, total: 500))
        progress?(.responseTokens(completed: 1, limit: maximumTokens))
        return try await generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
    }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        requestedMaximumTokens.append(maximumTokens)
        prompts.append(prompt)
        generating = true; events.append("work.begin")
        defer { generating = false; events.append("work.drained") }
        while holdGeneration && !generationReleased { try await Task.sleep(for: .milliseconds(1)) }
        try Task.checkCancellation()
        guard !replies.isEmpty else { throw IntelligenceFixtureError.missingReply }
        return replies.removeFirst()
    }
    func unload() async {
        unloading = true; events.append("unload.begin")
        while holdUnload && !unloadReleased { try? await Task.sleep(for: .milliseconds(1)) }
        unloaded = true; unloading = false; events.append("unload.end")
    }
    func releaseGeneration() { generationReleased = true }
    func releaseUnload() { unloadReleased = true }
}

actor IntelligenceBoundaryLoader {
    private var runtimes: [IntelligenceBoundaryRuntime]
    private(set) var loaded: [VerifiedModel] = []
    init(_ runtimes: [IntelligenceBoundaryRuntime]) { self.runtimes = runtimes }
    func load(_ model: VerifiedModel) throws -> any IntelligenceRuntime {
        loaded.append(model)
        guard !runtimes.isEmpty else { throw IntelligenceFixtureError.missingRuntime }
        return runtimes.removeFirst()
    }
}

@MainActor
func intelligenceEventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: .seconds(2))
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
