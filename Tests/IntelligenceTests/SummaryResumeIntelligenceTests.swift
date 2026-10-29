import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Cancellation and a user-initiated retry each run at most one model request.
/// Older source-index checkpoints remain compatible with storage, but are never
/// used as a substitute for the full transcript.
@MainActor
final class SummaryResumeIntelligenceTests: XCTestCase {
    func testCancelledSummaryHasNoPartialCheckpointAndManualRetryStartsFresh() async throws {
        let h = try await IntelligenceFixture.create()
        let runtime = IntelligenceBoundaryRuntime(replies: try h.summaryReplies(), holdGeneration: true)
        let checkpoints = try SummaryCheckpointStore(directoryURL: h.root.appendingPathComponent("Progress"))
        let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { _ in runtime }, summaryCheckpoints: checkpoints)
        let request = h.request(.summary)
        let operation = Task { try await session.run(request) }
        do {
            guard await intelligenceEventually({ await runtime.generating }) else { throw SinglePassServiceError.timeout }
            try await session.cancelAndDrain(requestID: request.id)
            do { _ = try await operation.value; XCTFail("Cancelled output must not be saved") }
            catch is CancellationError {}
            let before = try await h.store.generatedDocuments(meetingID: h.selected)
            XCTAssertTrue(before.isEmpty)
            let maps = try await checkpoints.savedMapCount(jobID: h.selected, meetingID: h.selected)
            XCTAssertEqual(maps, 0)
            let calls = await runtime.prompts
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(session.snapshot().phase, .cancelled)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)

            let retryRuntime = IntelligenceBoundaryRuntime(replies: try h.summaryReplies())
            let retry = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: h.manifest, runtimeLoader: { _ in retryRuntime }, summaryCheckpoints: checkpoints)
            let saved = try await retry.run(h.request(.summary))
            let retried = await retryRuntime.prompts
            XCTAssertEqual(retried.count, 1)
            XCTAssertEqual(retried.first, calls.first, "A manual retry reads the whole original transcript again")
            let durable = try await h.store.generatedDocument(id: saved.id, meetingID: h.selected)
            XCTAssertEqual(durable, saved)
            try await assertSinglePassOriginals(h)
            try await h.closeAndRemove()
        } catch {
            operation.cancel(); await runtime.releaseGeneration()
            _ = try? await operation.value
            try? await h.closeAndRemove()
            throw error
        }
    }

    func testLegacyCheckpointIsIgnoredAndRemovedOnlyAfterSuccessfulSave() async throws {
        let h = try await IntelligenceFixture.create()
        do {
            let checkpoints = try SummaryCheckpointStore(directoryURL: h.root.appendingPathComponent("Progress"))
            let identity = SummaryCheckpointIdentity(jobID: h.selected, meetingID: h.selected,
                sourceSHA256: String(repeating: "a", count: 64), planSHA256: String(repeating: "b", count: 64),
                modelID: h.manifest.modelID, modelRevision: h.manifest.revision,
                modelSHA256: h.manifest.artifacts[0].sha256, runtimeVersion: h.manifest.runtimeVersion,
                promptVersion: "narrative-v4", contextTokenLimit: 4_096, reservedOutputTokens: 1_024, totalChunks: 1)
            let bytes = try JSONSerialization.data(withJSONObject: ["schema_version": 2,
                "meeting_id": h.selected.uuidString, "topics": [["label": "Old progress", "source_ids": [0]]]])
            try await checkpoints.save(.init(index: 0, chunkSHA256: String(repeating: "c", count: 64), mapJSON: bytes),
                matching: identity)
            let failedRuntime = IntelligenceBoundaryRuntime(replies: ["invalid"])
            let failed = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: h.manifest, runtimeLoader: { _ in failedRuntime }, summaryCheckpoints: checkpoints)
            do {
                _ = try await failed.run(h.request(.summary))
                XCTFail("Invalid generation must fail")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidResponse) }
            let retained = try await checkpoints.savedMapCount(jobID: h.selected, meetingID: h.selected)
            XCTAssertEqual(retained, 1)
            let runtime = IntelligenceBoundaryRuntime(replies: try h.summaryReplies())
            let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: h.manifest, runtimeLoader: { _ in runtime }, summaryCheckpoints: checkpoints)
            _ = try await session.run(h.request(.summary))
            let calls = await runtime.prompts
            XCTAssertEqual(calls.count, 1)
            XCTAssertFalse(calls[0].contains("Old progress"))
            let remaining = try await checkpoints.savedMapCount(jobID: h.selected, meetingID: h.selected)
            XCTAssertEqual(remaining, 0)
            try await assertSinglePassOriginals(h)
            try await h.closeAndRemove()
        } catch { try? await h.closeAndRemove(); throw error }
    }

    func testFinalSaveConflictDoesNotOverwriteDocumentOrRetryGeneration() async throws {
        let h = try await IntelligenceFixture.create()
        do {
            let request = h.request(.summary)
            let existing = StoredGeneratedDocument(id: request.documentID, meetingID: h.selected, kind: .summary,
                originalJSON: Data(#"{"original":true}"#.utf8), question: nil, editedText: "User edited summary",
                modelRevision: h.manifest.revision, promptVersion: "existing",
                createdAt: request.createdAt, modifiedAt: request.createdAt)
            try await h.store.createGeneratedDocument(existing)
            let runtime = IntelligenceBoundaryRuntime(replies: try h.summaryReplies())
            let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: h.manifest, runtimeLoader: { _ in runtime })
            do {
                _ = try await session.run(request)
                XCTFail("A conflicting save must preserve the existing document")
            } catch { XCTAssertEqual(error as? GeneratedDocumentStoreError, .immutableConflict) }
            let saved = try await h.store.generatedDocument(id: existing.id, meetingID: h.selected)
            XCTAssertEqual(saved, existing)
            let calls = await runtime.prompts
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(session.snapshot().phase, .failed)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            try await assertSinglePassOriginals(h)
            try await h.closeAndRemove()
        } catch { try? await h.closeAndRemove(); throw error }
    }

    func testRecordingCancellationDrainsAndUnloadsBeforeReleasingModelLease() async throws {
        let h = try await IntelligenceFixture.create()
        let runtime = IntelligenceBoundaryRuntime(replies: try h.summaryReplies(), holdGeneration: true, holdUnload: true)
        let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { _ in runtime })
        let operation = Task { try await session.run(h.request(.summary)) }
        var closing: Task<Void, Error>?
        do {
            guard await intelligenceEventually({ await runtime.generating }) else { throw SinglePassServiceError.timeout }
            let lease = try XCTUnwrap(h.admission.snapshot().lease)
            let drain = Task { try await h.admission.cancelAndDrain(lease) }
            closing = drain
            guard await intelligenceEventually({ await runtime.unloading }) else { throw SinglePassServiceError.timeout }
            XCTAssertEqual(h.admission.snapshot().phase, .draining)
            do { try await h.models.remove(modelID: h.manifest.modelID); XCTFail("The model is still unloading") }
            catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
            await runtime.releaseUnload()
            try await drain.value
            do { _ = try await operation.value; XCTFail("Cancelled generation must not save") }
            catch is CancellationError {}
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            let calls = await runtime.prompts
            XCTAssertEqual(calls.count, 1)
            let documents = try await h.store.generatedDocuments(meetingID: h.selected)
            XCTAssertTrue(documents.isEmpty)
            try await h.models.remove(modelID: h.manifest.modelID)
            try await assertSinglePassOriginals(h)
            try await h.closeAndRemove()
        } catch {
            operation.cancel(); await runtime.releaseGeneration(); await runtime.releaseUnload()
            _ = try? await operation.value; _ = try? await closing?.value
            try? await h.closeAndRemove()
            throw error
        }
    }
}

private enum SinglePassServiceError: Error { case timeout }

@MainActor
private func assertSinglePassOriginals(_ h: IntelligenceFixture) async throws {
    let transcript = try await h.store.transcript(meetingID: h.selected)
    let note = try await h.store.manualNote(meetingID: h.selected)
    let other = try await h.store.transcript(meetingID: h.other)
    XCTAssertEqual(transcript, h.segments)
    XCTAssertEqual(note, h.note)
    XCTAssertEqual(other, h.otherSegments)
}
