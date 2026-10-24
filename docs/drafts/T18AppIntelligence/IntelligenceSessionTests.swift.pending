import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
@testable import LocalMinutesIntelligence

@MainActor
final class IntelligenceSessionTests: XCTestCase {
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
            XCTAssertEqual(provenance.first?["prompt_version"] as? String, "grounded-map-v1")
            XCTAssertEqual(provenance.first?["map_index"] as? Int, 0)
            XCTAssertEqual(summary.kind, .summary); XCTAssertNil(summary.question)
            XCTAssertEqual(summary.promptVersion, "grounded-map-v1")
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

    private func dictionary(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func expectModelInUse(_ h: IntelligenceFixture) async {
        do { try await h.models.remove(modelID: h.manifest.modelID); XCTFail("Service released its file lease before cleanup") }
        catch { XCTAssertEqual(error as? ModelInstallationError, .modelInUse) }
    }
}

private enum IntelligenceDraftError: Error { case neverStarted }

@MainActor
private final class IntelligenceASRBoundary: HeavyModelResourceLifecycle {
    func requestCancellation() {}
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}
