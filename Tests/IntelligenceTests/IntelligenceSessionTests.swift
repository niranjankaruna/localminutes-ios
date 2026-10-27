import Foundation
import SQLite3
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

@MainActor
final class IntelligenceSessionTests: XCTestCase {
    func testMissingTranscriptIsReportedBeforeLoadingAHeavyModel() async throws {
        let fixture = try await IntelligenceFixture.create()
        do {
            let meeting = UUID()
            try await fixture.store.createMeeting(.init(id: meeting, title: "Empty meeting",
                createdAt: Date(timeIntervalSince1970: 1), recordingState: .completed, capturedSampleCount: 0))
            let session = IntelligenceSession(store: fixture.store, models: fixture.models,
                admission: fixture.admission, manifest: fixture.manifest, runtimeLoader: { _ in
                    XCTFail("A summary without transcript evidence must fail before loading a model")
                    throw IntelligenceSessionError.invalidModel
                })
            do {
                _ = try await session.run(.init(meetingID: meeting, operation: .summary))
                XCTFail("An empty transcript must not produce a successful empty summary")
            } catch { XCTAssertEqual(error as? IntelligenceSessionError, .transcriptMissing) }
            XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
            try await fixture.closeAndRemove()
        } catch {
            try? await fixture.closeAndRemove()
            throw error
        }
    }

    func testSummaryAndQASaveSelectedValidatedDocumentsAndProvenanceWithoutChangingOriginals() async throws {
        let h = try await IntelligenceFixture.create()
        do {
            let summaryRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawSummary()])
            let qaRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawAnswer()])
            let loader = IntelligenceBoundaryLoader([summaryRuntime, qaRuntime])
            let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
            let summaryRequest = h.request(.summary)
            let summary = try await session.run(summaryRequest)
            let answerRequest = h.request(.question("Who will write the guide?"))
            let answer = try await session.run(answerRequest)
            let summaryJSON = try dictionary(summary.originalJSON)
            XCTAssertEqual(summaryJSON["schema_version"] as? Int, 1)
            XCTAssertEqual(summaryJSON["meeting_id"] as? String, h.selected.uuidString)
            let points = try XCTUnwrap(summaryJSON["summary_points"] as? [[String: Any]])
            XCTAssertEqual(points.count, 2)
            let evidence = try XCTUnwrap(points.first?["evidence"] as? [[String: Any]])
            XCTAssertEqual(evidence.first?["source_id"] as? String, h.segments[0].id.uuidString)
            let provenance = try XCTUnwrap(points.first?["provenance"] as? [[String: Any]])
            XCTAssertEqual(provenance.first?["model_revision"] as? String, h.manifest.revision)
            XCTAssertEqual(provenance.first?["prompt_version"] as? String, SummaryPipeline.currentPromptVersion)
            XCTAssertEqual(provenance.first?["map_index"] as? Int, 0)
            XCTAssertEqual(summary.kind, .summary); XCTAssertNil(summary.question)
            XCTAssertEqual(summary.promptVersion, SummaryPipeline.currentPromptVersion)
            XCTAssertEqual(answer.kind, .questionAnswer); XCTAssertEqual(answer.question, "Who will write the guide?")
            XCTAssertEqual(answer.promptVersion, "meeting-qa-v1")
            XCTAssertEqual(summary.modelRevision, h.manifest.revision); XCTAssertEqual(answer.modelRevision, h.manifest.revision)
            XCTAssertEqual(summary.id, summaryRequest.documentID); XCTAssertEqual(answer.id, answerRequest.documentID)
            XCTAssertFalse(summary.editedText.isEmpty); XCTAssertFalse(answer.editedText.isEmpty)
            XCTAssertEqual(summary.editRevision, 0); XCTAssertEqual(answer.editRevision, 0)
            let answerJSON = try dictionary(answer.originalJSON)
            XCTAssertEqual(answerJSON["status"] as? String, "supported_quote")
            let answerEvidence = try XCTUnwrap(answerJSON["evidence"] as? [[String: Any]])
            XCTAssertEqual(answerEvidence.first?["source_id"] as? String, h.segments[1].id.uuidString)
            XCTAssertEqual(answerEvidence.first?["quote"] as? String, h.segments[1].text)
            let loaded = await loader.loaded
            XCTAssertEqual(loaded.count, 2)
            let summaryUnloaded = await summaryRuntime.unloaded, qaUnloaded = await qaRuntime.unloaded
            XCTAssertTrue(summaryUnloaded); XCTAssertTrue(qaUnloaded)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            let otherDocuments = try await h.store.generatedDocuments(meetingID: h.other)
            XCTAssertTrue(otherDocuments.isEmpty)
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            let storedSummary = try await reopened.generatedDocument(id: summary.id, meetingID: h.selected)
            let storedAnswer = try await reopened.generatedDocument(id: answer.id, meetingID: h.selected)
            let transcript = try await reopened.transcript(meetingID: h.selected)
            let otherTranscript = try await reopened.transcript(meetingID: h.other)
            let note = try await reopened.manualNote(meetingID: h.selected)
            XCTAssertEqual(storedSummary, summary); XCTAssertEqual(storedAnswer, answer)
            XCTAssertEqual(transcript, h.segments); XCTAssertEqual(otherTranscript, h.otherSegments); XCTAssertEqual(note, h.note)
            try await reopened.close()
            try await h.closeAndRemove()
        } catch { try? await h.closeAndRemove(); throw error }
    }

    func testCancellationJoinsWorkThenUnloadsAndReleasesRealModelLeaseBeforeReplacement() async throws {
        let h = try await IntelligenceFixture.create()
        let oldRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawSummary()], holdGeneration: true, holdUnload: true)
        let nextRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawAnswer()])
        let loader = IntelligenceBoundaryLoader([oldRuntime, nextRuntime])
        let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
        let oldRequest = h.request(.summary)
        let operation = Task { try await session.run(oldRequest) }
        do {
            let started = await intelligenceEventually { await oldRuntime.generating }
            XCTAssertTrue(started)
            guard started else { throw IntelligenceDraftError.neverStarted }
            await expectModelInUse(h)
            let closing = Task { try await session.cancelAndDrain(requestID: oldRequest.id) }
            operation.cancel()
            let unloadHeld = await intelligenceEventually { await oldRuntime.unloading }
            XCTAssertTrue(unloadHeld)
            guard unloadHeld else { throw IntelligenceDraftError.neverStarted }
            let events = await oldRuntime.events
            XCTAssertEqual(events, ["work.begin", "work.drained", "unload.begin"])
            XCTAssertEqual(h.admission.snapshot().phase, .draining)
            await expectModelInUse(h)
            do { _ = try await session.run(h.request(.question("Who will write the guide?"))); XCTFail("Replacement bypassed native unload") }
            catch { XCTAssertEqual(error as? IntelligenceSessionError, .busy) }
            let before = try await h.store.generatedDocuments(meetingID: h.selected)
            XCTAssertTrue(before.isEmpty)
            await oldRuntime.releaseUnload()
            try await closing.value
            do { _ = try await operation.value; XCTFail("Cancelled operation saved a document") }
            catch is CancellationError {}
            let cancelled = session.snapshot()
            XCTAssertEqual(cancelled.phase, .cancelled); XCTAssertNil(cancelled.document)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            // Only real manager deletion success proves its service-owned file
            // lease was released. The fake runtime never releases that lease.
            try await h.models.remove(modelID: h.manifest.modelID)
            _ = try await h.models.importDirectory(h.sourceDirectory, manifest: h.manifest)
            let replacement = try await session.run(h.request(.question("Who will write the guide?")))
            XCTAssertEqual(replacement.kind, .questionAnswer)
            let rows = try await h.store.generatedDocuments(meetingID: h.selected)
            XCTAssertEqual(rows, [replacement])
            let ended = await oldRuntime.events
            XCTAssertEqual(ended, ["work.begin", "work.drained", "unload.begin", "unload.end"])
            try await h.closeAndRemove()
        } catch {
            operation.cancel(); await oldRuntime.releaseGeneration(); await oldRuntime.releaseUnload()
            _ = try? await operation.value
            try? await h.closeAndRemove(); throw error
        }
    }

    func testOneSharedGateRejectsASRThenConcurrentSummaryQAWithoutLoadingAnotherRuntime() async throws {
        let h = try await IntelligenceFixture.create()
        let asr = IntelligenceASRBoundary()
        let recordingLease = try h.admission.acquire(purpose: .streamingASR, requestID: UUID(), resource: asr)
        let summaryRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawSummary()], holdGeneration: true)
        let qaRuntime = IntelligenceBoundaryRuntime(replies: [try h.rawAnswer()])
        let loader = IntelligenceBoundaryLoader([summaryRuntime, qaRuntime])
        let first = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
        let second = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
        var operation: Task<StoredGeneratedDocument, Error>?
        do {
            for request in [h.request(.summary), h.request(.question("Who will write the guide?"))] {
                do { _ = try await first.run(request); XCTFail("Intelligence overlapped admitted ASR") }
                catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .busy) }
            }
            let before = await loader.loaded
            XCTAssertTrue(before.isEmpty)
            try await h.admission.cancelAndDrain(recordingLease)
            let request = h.request(.summary)
            let running = Task { try await first.run(request) }
            operation = running
            let started = await intelligenceEventually { await summaryRuntime.generating }
            XCTAssertTrue(started)
            do { _ = try await second.run(h.request(.question("Who will write the guide?"))); XCTFail("QA loaded alongside summary") }
            catch { XCTAssertEqual(error as? HeavyModelAdmissionError, .busy) }
            let during = await loader.loaded
            XCTAssertEqual(during.count, 1)
            await summaryRuntime.releaseGeneration()
            _ = try await running.value
            _ = try await second.run(h.request(.question("Who will write the guide?")))
            let after = await loader.loaded
            XCTAssertEqual(after.count, 2)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            try await h.closeAndRemove()
        } catch {
            operation?.cancel()
            await summaryRuntime.releaseGeneration()
            _ = try? await operation?.value
            try? await h.admission.cancelAndDrain(recordingLease)
            try? await h.closeAndRemove(); throw error
        }
    }

    func testActualClosedSQLiteSaveFailurePublishesNothingAndStillReleasesRuntimeAndLeases() async throws {
        let h = try await IntelligenceFixture.create()
        let runtime = IntelligenceBoundaryRuntime(replies: [try h.rawSummary()], holdGeneration: true)
        let loader = IntelligenceBoundaryLoader([runtime])
        let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
        let request = h.request(.summary)
        let running = Task { try await session.run(request) }
        do {
            let started = await intelligenceEventually { await runtime.generating }
            XCTAssertTrue(started)
            guard started else { throw IntelligenceDraftError.neverStarted }
            try await h.store.close()
            await runtime.releaseGeneration()
            do { _ = try await running.value; XCTFail("Closed database was acknowledged as a saved result") }
            catch { XCTAssertEqual(error as? MeetingStoreError, .closed) }
            XCTAssertEqual(session.snapshot().phase, .failed); XCTAssertNil(session.snapshot().document)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            try await h.models.remove(modelID: h.manifest.modelID)
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            let documents = try await reopened.generatedDocuments(meetingID: h.selected)
            let transcript = try await reopened.transcript(meetingID: h.selected)
            let note = try await reopened.manualNote(meetingID: h.selected)
            XCTAssertTrue(documents.isEmpty); XCTAssertEqual(transcript, h.segments); XCTAssertEqual(note, h.note)
            try await reopened.close(); try await h.closeAndRemove()
        } catch {
            running.cancel(); await runtime.releaseGeneration(); _ = try? await running.value
            try? await h.closeAndRemove(); throw error
        }
    }

    func testCancellationBeforeBlockedSQLiteCommitSavesNothingAndPreservesOriginalsAndModel() async throws {
        let h = try await IntelligenceFixture.create()
        let runtime = IntelligenceBoundaryRuntime(replies: [try h.rawSummary()], holdGeneration: true)
        let loader = IntelligenceBoundaryLoader([runtime])
        let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
            manifest: h.manifest, runtimeLoader: { try await loader.load($0) })
        let request = h.request(.summary)
        let installedModel = try await h.models.current(modelID: h.manifest.modelID)
        let originalModel = try XCTUnwrap(installedModel)
        let modelFile = try XCTUnwrap(originalModel.files[.summary])
        let originalModelBytes = try Data(contentsOf: modelFile)
        let running = Task { try await session.run(request) }
        var writer: IntelligenceSQLiteWriteLock?
        var closing: Task<Void, Error>?
        do {
            let started = await intelligenceEventually { await runtime.generating }
            XCTAssertTrue(started)
            guard started else { throw IntelligenceDraftError.neverStarted }
            writer = try IntelligenceSQLiteWriteLock(databaseURL: h.database)
            let clock = ContinuousClock()
            let heldAt = clock.now
            let releaseBy = heldAt.advanced(by: .milliseconds(500))
            // BEGIN IMMEDIATE on the second real connection prevents any service
            // writer from committing while the generated result reaches saving.
            await runtime.releaseGeneration()
            let saving = await waitForPhase(.saving, session: session, until: releaseBy)
            XCTAssertTrue(saving, "The real SQLite save must be pending behind the held writer")
            guard saving else { throw IntelligenceSQLiteLockError.deadlineExceeded }
            XCTAssertEqual(try writer?.generatedRowCount(), 0)
            closing = Task { try await session.cancelAndDrain(requestID: request.id) }
            let draining = await waitForPhase(.draining, session: session, until: releaseBy)
            XCTAssertTrue(draining, "Cancellation must be accepted before releasing the pre-commit writer")
            guard draining else { throw IntelligenceSQLiteLockError.deadlineExceeded }
            XCTAssertEqual(try writer?.generatedRowCount(), 0)
            XCTAssertLessThan(heldAt.duration(to: clock.now), .milliseconds(750),
                              "Release well within the production 1000ms SQLite busy timeout")
            try writer?.release()
            writer = nil
            try await closing?.value
            do { _ = try await running.value; XCTFail("A request cancelled before SQLite commit saved a generated document") }
            catch is CancellationError {}
            catch { XCTFail("Expected cancellation, not a lock timeout or storage failure: \(error)") }
            XCTAssertEqual(session.snapshot().phase, .cancelled)
            XCTAssertNil(session.snapshot().document)
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
            let preservedModel = try await h.models.current(modelID: h.manifest.modelID)
            XCTAssertEqual(preservedModel, originalModel)
            XCTAssertEqual(try Data(contentsOf: modelFile), originalModelBytes)
            // Preservation is checked above; this deliberate delete/reimport
            // additionally proves the actual service file lease was released.
            try await h.models.remove(modelID: h.manifest.modelID)
            let restoredModel = try await h.models.importDirectory(h.sourceDirectory, manifest: h.manifest)
            XCTAssertEqual(restoredModel.manifest, originalModel.manifest)
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            let documents = try await reopened.generatedDocuments(meetingID: h.selected)
            let transcript = try await reopened.transcript(meetingID: h.selected)
            let otherTranscript = try await reopened.transcript(meetingID: h.other)
            let note = try await reopened.manualNote(meetingID: h.selected)
            XCTAssertTrue(documents.isEmpty, "No cancelled generated row may appear after reopening the real database")
            XCTAssertEqual(transcript, h.segments); XCTAssertEqual(otherTranscript, h.otherSegments)
            XCTAssertEqual(note, h.note)
            try await reopened.close(); try await h.closeAndRemove()
        } catch {
            try? writer?.release()
            running.cancel(); await runtime.releaseGeneration()
            _ = try? await running.value; _ = try? await closing?.value
            try? await h.closeAndRemove(); throw error
        }
    }

    private func waitForPhase(_ phase: IntelligencePhase, session: IntelligenceSession,
                              until deadline: ContinuousClock.Instant) async -> Bool {
        let clock = ContinuousClock()
        while session.snapshot().phase != phase {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func expectModelInUse(_ h: IntelligenceFixture) async {
        do { try await h.models.remove(modelID: h.manifest.modelID); XCTFail("Service released its file lease before cleanup") }
        catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
    }
}

private enum IntelligenceDraftError: Error { case neverStarted }

private enum IntelligenceSQLiteLockError: Error { case openFailed, transactionFailed, releaseFailed, deadlineExceeded }

/// A real independent connection, owned only by the MainActor test. No pointer
/// crosses into service tasks. Every exit rolls back/closes this owned writer.
private final class IntelligenceSQLiteWriteLock {
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        guard databaseURL.isFileURL else { throw IntelligenceSQLiteLockError.openFailed }
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw IntelligenceSQLiteLockError.openFailed
        }
        database = opened
        guard sqlite3_busy_timeout(opened, 100) == SQLITE_OK,
              sqlite3_exec(opened, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close_v2(opened); database = nil
            throw IntelligenceSQLiteLockError.transactionFailed
        }
    }

    func generatedRowCount() throws -> Int64 {
        guard let database else { throw IntelligenceSQLiteLockError.transactionFailed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT count(*) FROM generated_documents", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw IntelligenceSQLiteLockError.transactionFailed
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IntelligenceSQLiteLockError.transactionFailed }
        return sqlite3_column_int64(statement, 0)
    }

    func release() throws {
        guard let database else { return }
        let rollback = sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
        let closed = sqlite3_close_v2(database)
        if closed == SQLITE_OK { self.database = nil }
        guard rollback == SQLITE_OK, closed == SQLITE_OK else { throw IntelligenceSQLiteLockError.releaseFailed }
    }

    deinit {
        if let database {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            sqlite3_close_v2(database)
        }
    }
}

@MainActor
private final class IntelligenceASRBoundary: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}
