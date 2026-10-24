import Foundation
import SQLite3
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Dedicated actual-Phi job only. Every load/tokenization/generation delegates
/// unchanged to the real default native runtime. Counters retain no content.
@MainActor
final class ActualResumedPhiIntelligenceTests: XCTestCase {
    func testActualPhiValidatedMapsSurviveCancelledCommitAndReopenedServiceCommitsWithoutRegeneration() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_PHI_MODEL_PATH"],
                                 "The dedicated native job must provide the reviewed real Phi model")
        let available = try ModelStoragePolicy.availableBytes(at: FileManager.default.temporaryDirectory)
        XCTAssertGreaterThanOrEqual(available, 5_000_000_000)
        guard available >= 5_000_000_000 else { throw ModelInstallationError.insufficientSpace }
        let revision = "a64113399c2f6b8ad3e11c394733a2ddadaa7f33"
        let repository = "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf"
        let name = "Phi-3-mini-4k-instruct-q4.gguf"
        let manifest = ModelManifest(modelID: "phi-3-mini-4k-instruct-q4", purpose: .summary,
            upstreamRepository: URL(string: repository)!, revision: revision,
            licenseIdentifier: "MIT", licenseNotice: "Phi-3-mini-4k-instruct, Copyright Microsoft Corporation. MIT License: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/blob/\(revision)/LICENSE",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary, fileName: name,
                byteCount: 2_393_231_072, sha256: "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef",
                downloadURL: URL(string: repository + "/resolve/" + revision + "/" + name)!,
                digestProvenance: .independentlyDownloaded)])
        // Shared fixture and actual manager independently stream-hash the full
        // pinned artifact. No small surrogate model or response is accepted.
        let h = try await IntelligenceFixture.create(actualModel: URL(fileURLWithPath: path), manifestOverride: manifest)
        let calls = ResumedPhiNativeCalls()
        let directory = h.root.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
        let checkpoints = try SummaryCheckpointStore(directoryURL: directory)
        let first = IntelligenceSession(store: h.store, models: h.models, admission: h.admission, manifest: manifest,
            runtimeLoader: { try await calls.loadRealDefault($0) }, summaryCheckpoints: checkpoints)
        let request = h.request(.summary)
        var writer: ResumedPhiSQLiteWriter?
        var operation: Task<StoredGeneratedDocument, Error>?
        var draining: Task<Void, Error>?
        var reopenedStore: SQLiteMeetingStore?
        do {
            // Reserve the writer before native inference, avoiding a race to
            // intercept the final save. Reads and real model work continue.
            writer = try ResumedPhiSQLiteWriter(database: h.database)
            let running = Task { try await first.run(request) }
            operation = running
            guard await waitForPhiSave(first, seconds: 12 * 60) else {
                running.cancel()
                _ = try await running.value
                throw ResumedPhiFixtureError.timeout
            }
            let saveObserved = ContinuousClock().now
            let checkpoint = try readPhiCheckpoint(directory, meetingID: h.selected)
            XCTAssertEqual(try writer?.generatedCount(), 0)
            let closing = Task { try await first.cancelAndDrain(requestID: request.id) }
            draining = closing
            let cancelDeadline = ContinuousClock().now.advanced(by: .milliseconds(300))
            while first.snapshot().phase != .draining, ContinuousClock().now < cancelDeadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertEqual(first.snapshot().phase, .draining)
            guard saveObserved.duration(to: ContinuousClock().now) < .milliseconds(650) else {
                throw ResumedPhiFixtureError.timeout
            }
            try writer?.release(); writer = nil
            try await closing.value
            do { _ = try await running.value; XCTFail("Cancelled final commit must not publish a document") }
            catch is CancellationError {}
            operation = nil; draining = nil
            XCTAssertEqual(first.snapshot().phase, .cancelled)
            XCTAssertNil(first.snapshot().document)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            let beforeReopen = try await h.store.generatedDocuments(meetingID: h.selected)
            XCTAssertTrue(beforeReopen.isEmpty)
            let firstCounts = await calls.snapshot()
            XCTAssertEqual(firstCounts.loads, 1)
            XCTAssertEqual(firstCounts.generated[0, default: 0], 1)
            XCTAssertEqual(firstCounts.unloaded[0, default: 0], 1)

            // The legacy ignored hook must prove its actual missing-behavior
            // RED here. Do not spend another native generation on that failure.
            guard let checkpoint else {
                XCTFail("A validated actual-Phi map must be durable before final SQLite commit")
                try await assertPhiOriginals(h, store: h.store)
                try await h.closeAndRemove()
                return
            }
            XCTAssertEqual(checkpoint.identity.jobID, h.selected)
            XCTAssertEqual(checkpoint.identity.meetingID, h.selected)
            XCTAssertEqual(checkpoint.identity.modelRevision, revision)
            XCTAssertEqual(checkpoint.identity.modelSHA256, manifest.artifacts[0].sha256)
            XCTAssertEqual(checkpoint.maps.count, 1)
            guard checkpoint.maps.count == 1 else {
                XCTFail("The unchanged small selected fixture must have exactly one validated native map")
                try await h.closeAndRemove()
                return
            }
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            reopenedStore = reopened
            let restoredCheckpoints = try SummaryCheckpointStore(directoryURL: directory)
            let restoredModels = ModelInstallationManager(rootURL: h.root.appendingPathComponent("Models", isDirectory: true),
                availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
            let gate = HeavyModelAdmission()
            let next = IntelligenceSession(store: reopened, models: restoredModels, admission: gate, manifest: manifest,
                runtimeLoader: { try await calls.loadRealDefault($0) }, summaryCheckpoints: restoredCheckpoints)
            let fresh = IntelligenceRequest(meetingID: h.selected, operation: .summary,
                                            createdAt: Date(timeIntervalSince1970: 3_001))
            XCTAssertNotEqual(fresh.id, request.id)
            let resumed = Task { try await next.run(fresh) }
            operation = resumed
            let saved = try await resumed.value
            operation = nil
            let finalCounts = await calls.snapshot()
            XCTAssertEqual(finalCounts.loads, 2, "Reopen must use the real default loader again")
            XCTAssertGreaterThan(finalCounts.tokenized[1, default: 0], 0, "Recompute the plan with the real native tokenizer")
            XCTAssertEqual(finalCounts.generated[1, default: 0], 0, "Reuse grounded native maps without a second generation")
            XCTAssertEqual(finalCounts.generated.values.reduce(0, +), 1)
            XCTAssertEqual(finalCounts.unloaded[1, default: 0], 1)
            let durable = try await reopened.generatedDocument(id: saved.id, meetingID: h.selected)
            XCTAssertEqual(durable, saved)
            XCTAssertEqual(saved.kind, .summary)
            XCTAssertEqual(saved.modelRevision, revision)
            XCTAssertEqual(saved.promptVersion, "grounded-map-v1")
            try validatePhiSummary(saved, fixture: h, revision: revision)
            XCTAssertNil(try readPhiCheckpoint(directory, meetingID: h.selected))
            XCTAssertEqual(next.snapshot().phase, .completed)
            XCTAssertEqual(gate.snapshot().phase, .idle)
            try await assertPhiOriginals(h, store: reopened)
            try await restoredModels.remove(modelID: manifest.modelID)
            try await reopened.close(); reopenedStore = nil
            try await h.closeAndRemove()
        } catch {
            try? writer?.release()
            operation?.cancel()
            _ = try? await operation?.value; _ = try? await draining?.value
            try? await reopenedStore?.close()
            try? await h.closeAndRemove()
            throw error
        }
    }

    private func validatePhiSummary(_ saved: StoredGeneratedDocument, fixture h: IntelligenceFixture, revision: String) throws {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved.originalJSON) as? [String: Any])
        XCTAssertEqual(object["meeting_id"] as? String, h.selected.uuidString)
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        XCTAssertTrue(decisions.contains { ($0["text"] as? String)?.lowercased().contains("prototype") == true
            && ($0["text"] as? String)?.contains("Friday") == true })
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        let guide = try XCTUnwrap(actions.first { ($0["task"] as? String)?.lowercased().contains("guide") == true })
        XCTAssertEqual(guide["owner"] as? String, "Leo")
        XCTAssertEqual(guide["due"] as? String, "Thursday")
        XCTAssertFalse(String(decoding: saved.originalJSON, as: UTF8.self).contains("telescope"))
        for key in ["summary_points", "decisions", "actions"] {
            for item in object[key] as? [[String: Any]] ?? [] {
                let evidence = try XCTUnwrap(item["evidence"] as? [[String: Any]])
                XCTAssertFalse(evidence.isEmpty)
                for citation in evidence {
                    let id = try XCTUnwrap(citation["source_id"] as? String)
                    let source = try XCTUnwrap(h.segments.first { $0.id.uuidString == id })
                    let quote = try XCTUnwrap(citation["quote"] as? String)
                    XCTAssertNotNil(source.text.range(of: quote))
                    XCTAssertEqual((citation["start_sample"] as? NSNumber)?.int64Value, source.startSample)
                    XCTAssertEqual((citation["end_sample"] as? NSNumber)?.int64Value, source.endSample)
                }
                let provenance = try XCTUnwrap(item["provenance"] as? [[String: Any]])
                XCTAssertFalse(provenance.isEmpty)
                for value in provenance {
                    XCTAssertEqual(value["model_revision"] as? String, revision)
                    XCTAssertEqual(value["prompt_version"] as? String, "grounded-map-v1")
                    XCTAssertEqual((value["map_index"] as? NSNumber)?.intValue, 0)
                }
            }
        }
    }
}

private struct ResumedPhiEnvelope: Decodable { let schemaVersion: Int; let checkpoint: StoredSummaryCheckpoint }
private enum ResumedPhiFixtureError: Error { case timeout, sqlite(Int32) }
private func readPhiCheckpoint(_ directory: URL, meetingID: UUID) throws -> StoredSummaryCheckpoint? {
    let url = directory.appendingPathComponent(meetingID.uuidString + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let envelope = try JSONDecoder().decode(ResumedPhiEnvelope.self, from: Data(contentsOf: url))
    XCTAssertEqual(envelope.schemaVersion, 1)
    return envelope.checkpoint
}
@MainActor
private func waitForPhiSave(_ session: IntelligenceSession, seconds: Int) async -> Bool {
    let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: .seconds(seconds))
    while session.snapshot().phase != .saving {
        if [.failed, .cancelled, .completed].contains(session.snapshot().phase) || clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return true
}
@MainActor
private func assertPhiOriginals(_ h: IntelligenceFixture, store: SQLiteMeetingStore) async throws {
    let transcript = try await store.transcript(meetingID: h.selected)
    let note = try await store.manualNote(meetingID: h.selected)
    let other = try await store.transcript(meetingID: h.other)
    let otherDocuments = try await store.generatedDocuments(meetingID: h.other)
    XCTAssertEqual(transcript, h.segments); XCTAssertEqual(note, h.note)
    XCTAssertEqual(other, h.otherSegments); XCTAssertTrue(otherDocuments.isEmpty)
}

private actor ResumedPhiNativeCalls {
    struct Snapshot: Sendable {
        let loads: Int
        let generated: [Int: Int]
        let tokenized: [Int: Int]
        let unloaded: [Int: Int]
    }
    var loads = 0
    var generated: [Int: Int] = [:]
    var tokenized: [Int: Int] = [:]
    var unloaded: [Int: Int] = [:]
    func loadRealDefault(_ model: VerifiedModel) async throws -> any IntelligenceRuntime {
        let runtime = try await IntelligenceSession.loadPinnedRuntime(model)
        let index = loads; loads += 1
        return ResumedPhiCountingRuntime(real: runtime, calls: self, index: index)
    }
    func generated(_ index: Int) { generated[index, default: 0] += 1 }
    func tokenized(_ index: Int) { tokenized[index, default: 0] += 1 }
    func unloaded(_ index: Int) { unloaded[index, default: 0] += 1 }
    func snapshot() -> Snapshot { .init(loads: loads, generated: generated, tokenized: tokenized, unloaded: unloaded) }
}
private actor ResumedPhiCountingRuntime: IntelligenceRuntime {
    let real: any IntelligenceRuntime
    let calls: ResumedPhiNativeCalls
    let index: Int
    init(real: any IntelligenceRuntime, calls: ResumedPhiNativeCalls, index: Int) {
        self.real = real; self.calls = calls; self.index = index
    }
    func promptTokenCount(prompt: String) async throws -> Int {
        let count = try await real.promptTokenCount(prompt: prompt)
        await calls.tokenized(index); return count
    }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        let output = try await real.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens)
        await calls.generated(index); return output
    }
    func unload() async { await real.unload(); await calls.unloaded(index) }
}

@MainActor
private final class ResumedPhiSQLiteWriter {
    private var handle: OpaquePointer?
    init(database: URL) throws {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(database.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw ResumedPhiFixtureError.sqlite(result)
        }
        handle = opened
        let begin = sqlite3_exec(opened, "BEGIN IMMEDIATE", nil, nil, nil)
        guard begin == SQLITE_OK else { sqlite3_close_v2(opened); handle = nil; throw ResumedPhiFixtureError.sqlite(begin) }
    }
    func generatedCount() throws -> Int64 {
        guard let handle else { throw ResumedPhiFixtureError.sqlite(SQLITE_MISUSE) }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, "SELECT count(*) FROM generated_documents", -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw ResumedPhiFixtureError.sqlite(result) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ResumedPhiFixtureError.sqlite(SQLITE_ERROR) }
        return sqlite3_column_int64(statement, 0)
    }
    func release() throws {
        guard let handle else { return }
        let rollback = sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
        let close = sqlite3_close_v2(handle); self.handle = nil
        guard rollback == SQLITE_OK, close == SQLITE_OK else { throw ResumedPhiFixtureError.sqlite(rollback) }
    }
}
