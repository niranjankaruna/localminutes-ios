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
                       importActualDirectoryDirectly: Bool = false) async throws -> IntelligenceFixture {
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
        let segments = [
            StoredTranscriptSegment(id: intelligenceUUID(11), meetingID: selected, sequence: 0,
                startSample: 0, endSample: 16_000, text: "Maya: We decided to ship the prototype on Friday.", modelRevision: "original-ASR"),
            StoredTranscriptSegment(id: intelligenceUUID(12), meetingID: selected, sequence: 1,
                startSample: 16_000, endSample: 32_000, text: "Leo: I will write the guide by Thursday.", modelRevision: "original-ASR")
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
        let points = segments.map { segment -> [String: Any] in
            ["text": segment.text, "evidence": [citation(segment)]]
        }
        let decision: [String: Any] = ["text": segments[0].text, "evidence": [citation(segments[0])]]
        let action: [String: Any] = ["task": "write the guide", "owner": "Leo", "due": "Thursday",
                                    "evidence": [citation(segments[1])]]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["meeting_id": selected.uuidString,
            "summary_points": points, "decisions": [decision], "actions": [action]], options: [.sortedKeys]), as: UTF8.self)
    }

    func rawAnswer() throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["status": "supported_quote",
            "source_id": segments[1].id.uuidString, "quote": segments[1].text], options: [.sortedKeys]), as: UTF8.self)
    }

    private func citation(_ segment: StoredTranscriptSegment) -> [String: Any] {
        ["source_id": segment.id.uuidString, "start_sample": segment.startSample,
         "end_sample": segment.endSample, "quote": segment.text]
    }
}

private enum IntelligenceFixtureError: Error {
    case missingReply, missingRuntime
}

// Only the async inference/load boundaries are doubled. They do not release any
// model/gate lease or save a document: the real service must perform that work.
actor IntelligenceBoundaryRuntime: IntelligenceRuntime {
    private var replies: [String]
    private var holdGeneration: Bool
    private var holdUnload: Bool
    private var generationReleased = false
    private var unloadReleased = false
    private(set) var generating = false
    private(set) var unloading = false
    private(set) var unloaded = false
    private(set) var events: [String] = []
    init(replies: [String], holdGeneration: Bool = false, holdUnload: Bool = false) {
        self.replies = replies; self.holdGeneration = holdGeneration; self.holdUnload = holdUnload
    }
    func promptTokenCount(prompt: String) async throws -> Int { try Task.checkCancellation(); return 500 }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
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
