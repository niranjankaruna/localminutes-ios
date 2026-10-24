import Foundation
import SQLite3
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Real SQLite, checkpoint files, model-file leases and heavy admission.
/// Only runtime loading/tokenization/generated JSON are doubled. These files
/// contain synthetic model bytes and are never evidence of actual inference.
@MainActor
final class SummaryResumeIntelligenceTests: XCTestCase {
    func testCancelledSummaryReopensStableMeetingJobAndRemovesMapsOnlyAfterRealSQLiteCommit() async throws {
        try await withResumeIntelligenceFixture { h, checkpoints, directory in
            let oldRuntime = ResumeServiceRuntime(holdAtRequest: 2)
            let old = resumeServiceSession(h, runtime: oldRuntime, checkpoints: checkpoints)
            let request = h.request(.summary)
            let operation = Task { try await old.run(request) }
            var writer: ResumeServiceSQLiteWriter?
            var resumedOperation: Task<StoredGeneratedDocument, Error>?
            let nextRuntime = ResumeServiceRuntime()
            do {
                guard await resumeServiceEventually({ await oldRuntime.held }) else { throw ResumeServiceFixtureError.timeout }
                try await old.cancelAndDrain(requestID: request.id)
                do { _ = try await operation.value; XCTFail("Cancelled summary must not save") }
                catch is CancellationError {}
                let prefix = try resumeServiceCheckpoint(directory, meetingID: h.selected)
                XCTAssertEqual(prefix?.identity.jobID, h.selected, "Job identity belongs to the meeting, not this request or view")
                XCTAssertEqual(prefix?.maps.count, 1)
                XCTAssertEqual(old.snapshot().phase, .cancelled)
                XCTAssertNil(old.snapshot().document)
                let before = try await h.store.generatedDocuments(meetingID: h.selected)
                XCTAssertTrue(before.isEmpty)
                XCTAssertEqual(h.admission.snapshot().phase, .idle)
                let oldUnloaded = await oldRuntime.unloaded
                XCTAssertTrue(oldUnloaded)

                let reopened = try SummaryCheckpointStore(directoryURL: directory)
                let next = resumeServiceSession(h, runtime: nextRuntime, checkpoints: reopened)
                let freshRequest = h.request(.summary)
                XCTAssertNotEqual(freshRequest.id, request.id)
                writer = try ResumeServiceSQLiteWriter(database: h.database)
                let running = Task { try await next.run(freshRequest) }
                resumedOperation = running
                guard await resumeServiceEventually({ next.snapshot().phase == .saving }) else { throw ResumeServiceFixtureError.timeout }
                let waitingSince = ContinuousClock().now
                let completeMaps = try resumeServiceCheckpoint(directory, meetingID: h.selected)
                XCTAssertEqual(completeMaps?.maps.count, 2, "Do not erase checkpoint progress before the final commit")
                XCTAssertEqual(try writer?.generatedCount(), 0, "Real reserved writer must still prevent the final row")
                guard waitingSince.duration(to: ContinuousClock().now) < .milliseconds(600) else {
                    throw ResumeServiceFixtureError.timeout
                }
                try writer?.release(); writer = nil
                let saved = try await running.value
                let calls = await nextRuntime.requests
                XCTAssertEqual(calls.count, 1, "Reopened service must generate only the missing map")
                if let prompt = calls.first {
                    XCTAssertEqual(try resumeServiceSources(prompt).map(\.id), [h.segments[1].id.uuidString])
                }
                let durable = try await h.store.generatedDocument(id: saved.id, meetingID: h.selected)
                XCTAssertEqual(durable, saved)
                XCTAssertNil(try resumeServiceCheckpoint(directory, meetingID: h.selected))
                XCTAssertEqual(next.snapshot().phase, .completed)
                XCTAssertEqual(next.snapshot().document, saved)
                try await assertResumeServiceOriginals(h, note: h.note)
            } catch {
                try? writer?.release()
                operation.cancel(); resumedOperation?.cancel()
                await oldRuntime.releaseAll(); await nextRuntime.releaseAll()
                _ = try? await operation.value; _ = try? await resumedOperation?.value
                throw error
            }
        }
    }

    func testStaleSourceModelTemplateAndBudgetRequireExplicitMeetingJobReset() async throws {
        for fault in ["source", "model", "template", "budget"] {
            try await withResumeIntelligenceFixture { h, checkpoints, directory in
                try await seedResumeServiceCheckpoint(h, checkpoints: checkpoints)
                let original = try XCTUnwrap(resumeServiceCheckpoint(directory, meetingID: h.selected))
                var expectedNote = h.note
                if fault == "source" {
                    expectedNote = .init(meetingID: h.selected, text: h.note.text + " User changed the original note.",
                        editRevision: h.note.editRevision + 1, modifiedAt: Date(timeIntervalSince1970: 4_000))
                    try await h.store.saveManualNote(expectedNote)
                } else {
                    let id = original.identity
                    let stale = SummaryCheckpointIdentity(jobID: id.jobID, meetingID: id.meetingID,
                        sourceSHA256: id.sourceSHA256, planSHA256: id.planSHA256, modelID: id.modelID,
                        modelRevision: fault == "model" ? String(repeating: "b", count: 40) : id.modelRevision,
                        modelSHA256: id.modelSHA256, runtimeVersion: id.runtimeVersion,
                        promptVersion: fault == "template" ? "grounded-map-previous" : id.promptVersion,
                        contextTokenLimit: id.contextTokenLimit,
                        reservedOutputTokens: fault == "budget" ? 512 : id.reservedOutputTokens,
                        totalChunks: id.totalChunks)
                    try await checkpoints.remove(jobID: h.selected, meetingID: h.selected)
                    for map in original.maps { try await checkpoints.save(map, matching: stale) }
                }
                let runtime = ResumeServiceRuntime()
                let session = resumeServiceSession(h, runtime: runtime, checkpoints: checkpoints)
                do { _ = try await session.run(h.request(.summary)); XCTFail("Stale progress requires an explicit fresh job") }
                catch { XCTAssertEqual(error as? SummaryCheckpointError, .identityMismatch) }
                let attempted = await runtime.requests
                XCTAssertTrue(attempted.isEmpty, "Reject stale maps before any generation")
                XCTAssertEqual(session.snapshot().phase, .failed)
                XCTAssertNil(session.snapshot().document)
                let beforeReset = try await h.store.generatedDocuments(meetingID: h.selected)
                XCTAssertTrue(beforeReset.isEmpty)
                XCTAssertNotNil(try resumeServiceCheckpoint(directory, meetingID: h.selected), "Rejection must not silently discard progress")

                // This is the explicit app-owned reset boundary; no hidden
                // fallback erases stale maps or relabels their provenance.
                try await checkpoints.remove(jobID: h.selected, meetingID: h.selected)
                let freshRuntime = ResumeServiceRuntime()
                let fresh = resumeServiceSession(h, runtime: freshRuntime, checkpoints: checkpoints)
                let saved = try await fresh.run(h.request(.summary))
                let calls = await freshRuntime.requests
                XCTAssertEqual(calls.count, 2)
                XCTAssertEqual(saved.modelRevision, h.manifest.revision)
                XCTAssertNil(try resumeServiceCheckpoint(directory, meetingID: h.selected))
                let documents = try await h.store.generatedDocuments(meetingID: h.selected)
                XCTAssertEqual(documents, [saved])
                try await assertResumeServiceOriginals(h, note: expectedNote)
            }
        }
    }

    func testFinalSaveConflictRetainsAllMapsAndRetryCommitsWithoutRegeneratingOrOverwritingExistingDocument() async throws {
        try await withResumeIntelligenceFixture { h, checkpoints, directory in
            let documentID = UUID()
            let existing = StoredGeneratedDocument(id: documentID, meetingID: h.selected, kind: .summary,
                originalJSON: Data("{\"original\":true}".utf8), question: nil, editedText: "Original edited user document",
                modelRevision: h.manifest.revision, promptVersion: "original-existing-document",
                createdAt: Date(timeIntervalSince1970: 1_000), modifiedAt: Date(timeIntervalSince1970: 1_000))
            try await h.store.createGeneratedDocument(existing)
            let runtime = ResumeServiceRuntime()
            let session = resumeServiceSession(h, runtime: runtime, checkpoints: checkpoints)
            let conflicting = IntelligenceRequest(meetingID: h.selected, documentID: documentID,
                operation: .summary, createdAt: Date(timeIntervalSince1970: 3_000))
            do { _ = try await session.run(conflicting); XCTFail("Final commit must preserve an existing different document") }
            catch { XCTAssertEqual(error as? GeneratedDocumentStoreError, .immutableConflict) }
            let complete = try resumeServiceCheckpoint(directory, meetingID: h.selected)
            XCTAssertEqual(complete?.maps.count, 2, "Final-save failure must retain fully validated expensive work")
            let unchanged = try await h.store.generatedDocument(id: documentID, meetingID: h.selected)
            XCTAssertEqual(unchanged, existing)
            XCTAssertEqual(session.snapshot().phase, .failed)
            XCTAssertNil(session.snapshot().document)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)

            let retryRuntime = ResumeServiceRuntime()
            let reopened = try SummaryCheckpointStore(directoryURL: directory)
            let retry = resumeServiceSession(h, runtime: retryRuntime, checkpoints: reopened)
            let saved = try await retry.run(h.request(.summary))
            let calls = await retryRuntime.requests
            XCTAssertTrue(calls.isEmpty, "Complete map set must be decoded/merged without regenerating")
            let durable = try await h.store.generatedDocument(id: saved.id, meetingID: h.selected)
            let preserved = try await h.store.generatedDocument(id: existing.id, meetingID: h.selected)
            XCTAssertEqual(durable, saved); XCTAssertEqual(preserved, existing)
            XCTAssertNil(try resumeServiceCheckpoint(directory, meetingID: h.selected))
            try await assertResumeServiceOriginals(h, note: h.note)
        }
    }

    func testRecordingPriorityCancellationDrainsRuntimeAndRealModelLeaseBeforeASRAdmissionWhileKeepingPrefix() async throws {
        try await withResumeIntelligenceFixture { h, checkpoints, directory in
            let runtime = ResumeServiceRuntime(holdAtRequest: 2, holdUnload: true)
            let session = resumeServiceSession(h, runtime: runtime, checkpoints: checkpoints)
            let operation = Task { try await session.run(h.request(.summary)) }
            var closing: Task<Void, Error>?
            do {
                guard await resumeServiceEventually({ await runtime.held }) else { throw ResumeServiceFixtureError.timeout }
                let lease = try XCTUnwrap(h.admission.snapshot().lease)
                XCTAssertEqual(lease.purpose, .summary)
                let drain = Task { try await h.admission.cancelAndDrain(lease) }
                closing = drain
                guard await resumeServiceEventually({ await runtime.unloading }) else { throw ResumeServiceFixtureError.timeout }
                let prefix = try resumeServiceCheckpoint(directory, meetingID: h.selected)
                XCTAssertEqual(prefix?.maps.count, 1)
                XCTAssertEqual(h.admission.snapshot().phase, .draining)
                let asr = ResumeServiceASRLifecycle()
                do { _ = try h.admission.acquire(purpose: .streamingASR, requestID: UUID(), resource: asr); XCTFail("Recording bypassed cleanup") }
                catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .busy) }
                do { try await h.models.remove(modelID: h.manifest.modelID); XCTFail("Model file lease released before native unload") }
                catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
                await runtime.releaseAll()
                try await drain.value
                do { _ = try await operation.value; XCTFail("Priority-cancelled summary must not save") }
                catch is CancellationError {}
                XCTAssertEqual(h.admission.snapshot().phase, .idle)
                let unloaded = await runtime.unloaded
                XCTAssertTrue(unloaded)
                let requests = await runtime.requests
                XCTAssertEqual(requests.count, 2)
                try await h.models.remove(modelID: h.manifest.modelID)
                _ = try await h.models.importDirectory(h.sourceDirectory, manifest: h.manifest)
                let recording = try h.admission.acquire(purpose: .streamingASR, requestID: UUID(), resource: asr)
                XCTAssertEqual(h.admission.snapshot().lease, recording)
                try await h.admission.cancelAndDrain(recording)
                let documents = try await h.store.generatedDocuments(meetingID: h.selected)
                XCTAssertTrue(documents.isEmpty)
                XCTAssertEqual(try resumeServiceCheckpoint(directory, meetingID: h.selected)?.maps.count, 1)
                try await assertResumeServiceOriginals(h, note: h.note)
            } catch {
                operation.cancel(); await runtime.releaseAll()
                _ = try? await operation.value; _ = try? await closing?.value
                throw error
            }
        }
    }
}

private struct ResumeServiceEnvelope: Decodable { let schemaVersion: Int; let checkpoint: StoredSummaryCheckpoint }
private enum ResumeServiceFixtureError: Error { case timeout, invalidPrompt, sqlite(Int32) }

@MainActor
private func resumeServiceSession(_ h: IntelligenceFixture, runtime: ResumeServiceRuntime,
                                  checkpoints: SummaryCheckpointStore) -> IntelligenceSession {
    IntelligenceSession(store: h.store, models: h.models, admission: h.admission, manifest: h.manifest,
        runtimeLoader: { _ in runtime }, summaryCheckpoints: checkpoints)
}

private func resumeServiceCheckpoint(_ directory: URL, meetingID: UUID) throws -> StoredSummaryCheckpoint? {
    let url = directory.appendingPathComponent(meetingID.uuidString + ".json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let envelope = try JSONDecoder().decode(ResumeServiceEnvelope.self, from: Data(contentsOf: url))
    XCTAssertEqual(envelope.schemaVersion, 1)
    return envelope.checkpoint
}

@MainActor
private func seedResumeServiceCheckpoint(_ h: IntelligenceFixture, checkpoints: SummaryCheckpointStore) async throws {
    let runtime = ResumeServiceRuntime()
    let segments = try await h.store.transcript(meetingID: h.selected)
    let note = try await h.store.manualNote(meetingID: h.selected)
    let source = GroundedSummarySource(meetingID: h.selected, segments: segments.map {
        .init(id: $0.id.uuidString, startSample: $0.startSample, endSample: $0.endSample, text: $0.text)
    }, originalManualNotes: note?.text ?? "")
    let artifact = try XCTUnwrap(h.manifest.artifacts.first)
    let pipeline = SummaryPipeline(modelRevision: h.manifest.revision,
        tokenizer: { try await runtime.promptTokenCount(prompt: $0) },
        generator: { try await runtime.generateJSON(prompt: $0, schema: $1, maximumTokens: $2) },
        resume: .init(jobID: h.selected, modelID: h.manifest.modelID, modelSHA256: artifact.sha256,
                      runtimeVersion: h.manifest.runtimeVersion, checkpoints: checkpoints))
    _ = try await pipeline.summarize(selectedMeetingID: h.selected, source: source)
    await runtime.unload()
}

@MainActor
private func assertResumeServiceOriginals(_ h: IntelligenceFixture, note: StoredManualNote) async throws {
    let selected = try await h.store.transcript(meetingID: h.selected)
    let other = try await h.store.transcript(meetingID: h.other)
    let manual = try await h.store.manualNote(meetingID: h.selected)
    let otherDocuments = try await h.store.generatedDocuments(meetingID: h.other)
    XCTAssertEqual(selected, h.segments); XCTAssertEqual(other, h.otherSegments)
    XCTAssertEqual(manual, note); XCTAssertTrue(otherDocuments.isEmpty)
}

@MainActor
private func withResumeIntelligenceFixture(
    _ body: @MainActor (IntelligenceFixture, SummaryCheckpointStore, URL) async throws -> Void) async throws {
    let h = try await IntelligenceFixture.create()
    do {
        let directory = h.root.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
        let checkpoints = try SummaryCheckpointStore(directoryURL: directory)
        try await body(h, checkpoints, directory)
        try await h.closeAndRemove()
    } catch { try? await h.closeAndRemove(); throw error }
}

private actor ResumeServiceRuntime: IntelligenceRuntime {
    let holdAtRequest: Int?
    let holdUnload: Bool
    var released = false
    private(set) var requests: [String] = []
    private(set) var held = false
    private(set) var unloading = false
    private(set) var unloaded = false
    init(holdAtRequest: Int? = nil, holdUnload: Bool = false) {
        self.holdAtRequest = holdAtRequest; self.holdUnload = holdUnload
    }
    func promptTokenCount(prompt: String) async throws -> Int {
        try Task.checkCancellation()
        return try resumeServiceSources(prompt).count == 1 ? 3_000 : 3_072
    }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        requests.append(prompt)
        if let holdAtRequest, requests.count == holdAtRequest {
            held = true
            while !released { try await Task.sleep(for: .milliseconds(1)) }
        }
        try Task.checkCancellation()
        let sources = try resumeServiceSources(prompt)
        guard let marker = prompt.range(of: "SELECTED_MEETING_ID: "),
              let meeting = UUID(uuidString: String(prompt[marker.upperBound...].prefix(36))) else {
            throw ResumeServiceFixtureError.invalidPrompt
        }
        let points: [[String: Any]] = sources.map {
            ["text": $0.text, "evidence": [["source_id": $0.id, "start_sample": $0.startSample,
                                           "end_sample": $0.endSample, "quote": $0.text]]]
        }
        let object: [String: Any] = ["meeting_id": meeting.uuidString, "summary_points": points,
                                   "decisions": [], "actions": []]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
    func unload() async {
        unloading = true
        while holdUnload && !released { try? await Task.sleep(for: .milliseconds(1)) }
        unloaded = true; unloading = false
    }
    func releaseAll() { released = true }
}

private func resumeServiceSources(_ prompt: String) throws -> [SummaryEvidenceSegment] {
    guard let marker = prompt.range(of: "\n\nEVIDENCE_JSON:\n") else { throw ResumeServiceFixtureError.invalidPrompt }
    return try JSONDecoder().decode([SummaryEvidenceSegment].self, from: Data(prompt[marker.upperBound...].utf8))
}

@MainActor
private func resumeServiceEventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    let clock = ContinuousClock(), deadline = ContinuousClock().now.advanced(by: .seconds(3))
    while !(await condition()) {
        if clock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

@MainActor
private final class ResumeServiceASRLifecycle: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}

@MainActor
private final class ResumeServiceSQLiteWriter {
    private var handle: OpaquePointer?
    init(database: URL) throws {
        var opened: OpaquePointer?
        let code = sqlite3_open_v2(database.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw ResumeServiceFixtureError.sqlite(code)
        }
        handle = opened
        let result = sqlite3_exec(opened, "BEGIN IMMEDIATE", nil, nil, nil)
        guard result == SQLITE_OK else { sqlite3_close_v2(opened); handle = nil; throw ResumeServiceFixtureError.sqlite(result) }
    }
    func generatedCount() throws -> Int64 {
        guard let handle else { throw ResumeServiceFixtureError.invalidPrompt }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, "SELECT count(*) FROM generated_documents", -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw ResumeServiceFixtureError.sqlite(result) }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ResumeServiceFixtureError.sqlite(SQLITE_ERROR) }
        return sqlite3_column_int64(statement, 0)
    }
    func release() throws {
        guard let handle else { return }
        let result = sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
        let closed = sqlite3_close_v2(handle)
        self.handle = nil
        guard result == SQLITE_OK, closed == SQLITE_OK else { throw ResumeServiceFixtureError.sqlite(result) }
    }
}
