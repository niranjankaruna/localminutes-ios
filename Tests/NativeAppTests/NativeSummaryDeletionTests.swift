#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

/// Actual controller and SQLite storage; generated documents are fixtures.
/// These tests delete saved output without loading a model or running inference.
@MainActor
final class NativeSummaryDeletionTests: XCTestCase {
    func testDeleteRemovesAllSelectedSummariesWithoutModelAndPreservesOtherContent() async throws {
        try await fixture { f in
            await f.services.refreshModels()
            XCTAssertFalse(f.services.summaryInstalled)
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            XCTAssertEqual(controller.summary?.id, f.latest.id)
            XCTAssertTrue(controller.canDeleteSummary, "Deleting saved output must not require an installed model")
            let answerCitations = controller.citations[f.answer.id]?.map(\.id)
            XCTAssertEqual(answerCitations?.count, 1)
            controller.answerDrafts[f.answer.id] = "Unsaved answer draft stays separate."

            try f.services.beginLibraryMaintenance()
            XCTAssertFalse(controller.canDeleteSummary)
            let blocked = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            f.services.endLibraryMaintenance()
            XCTAssertFalse(blocked)

            let deleted = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            XCTAssertTrue(deleted)
            XCTAssertNil(controller.summary)
            XCTAssertEqual(controller.summaryText, "")
            XCTAssertNil(controller.citations[f.latest.id])
            XCTAssertEqual(controller.answers, [f.answer])
            XCTAssertEqual(controller.answerDrafts[f.answer.id], "Unsaved answer draft stays separate.")
            XCTAssertEqual(controller.citations[f.answer.id]?.map(\.id), answerCitations)
            let summaries = try await f.services.store.generatedDocuments(meetingID: f.selected, kind: .summary, limit: 50)
            XCTAssertTrue(summaries.isEmpty, "Removing only the displayed version would expose an older summary on reload")
            try await f.assertOriginalsAndUnrelatedContent()
            let checkpointCount = try await f.services.summaryCheckpoints.savedMapCount(jobID: f.selected, meetingID: f.selected)
            XCTAssertEqual(checkpointCount, 1, "Summary deletion must leave unfinished generation progress alone")
        }
    }

    func testPendingSummaryDebounceAndNavigationCannotRestoreDeletedOutput() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.summaryText = "Unsaved summary draft waiting for debounce."
            controller.summaryChanged()
            XCTAssertTrue(controller.hasSummaryEdits)
            let deleted = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            XCTAssertTrue(deleted)
            controller.leaveMeeting()
            // Cross the actual debounce interval to catch an uncancelled autosave.
            try await Task.sleep(for: .milliseconds(450))
            await controller.load()
            let summaries = try await f.services.store.generatedDocuments(meetingID: f.selected, kind: .summary, limit: 50)
            XCTAssertTrue(summaries.isEmpty)
            XCTAssertNil(controller.summary)
            XCTAssertEqual(controller.summaryText, "")
            XCTAssertFalse(controller.hasSummaryEdits)
            XCTAssertFalse(controller.isDeletingSummary)
            XCTAssertFalse(controller.canDeleteSummary)
            XCTAssertNil(controller.citations[f.latest.id])
            XCTAssertNil(controller.generationProgress)
            XCTAssertFalse(controller.editConflict)
            let reopened = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await reopened.load()
            XCTAssertNil(reopened.summary)
            XCTAssertTrue(reopened.summaryPaused, "Existing checkpoints may still offer Resume after output is deleted")
            try await f.assertOriginalsAndUnrelatedContent()
        }
    }

    func testStaleConfirmationAfterEditOrNewerSummaryPreservesEveryVersionAndDraft() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.summaryText = "My local summary draft."
            let edited = try await f.services.store.saveGeneratedDocumentEdit(id: f.latest.id, meetingID: f.selected,
                text: "A newer saved edit elsewhere.", expectedRevision: 0, modifiedAt: Date(timeIntervalSince1970: 10))
            let rejectedEdit = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            XCTAssertFalse(rejectedEdit)
            XCTAssertEqual(controller.summary?.id, f.latest.id)
            XCTAssertEqual(controller.summaryText, "My local summary draft.")
            var summaries = try await f.services.store.generatedDocuments(meetingID: f.selected, kind: .summary, limit: 50)
            XCTAssertEqual(Set(summaries.map(\.id)), [f.old.id, f.latest.id])
            XCTAssertEqual(summaries.first { $0.id == edited.id }, edited)

            let replacementController = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await replacementController.load()
            replacementController.summaryText = "Draft bound to the previously confirmed summary."
            let replacement = try f.summaryDocument(text: "A newly generated replacement.", createdAt: 20)
            try await f.services.store.createGeneratedDocument(replacement)
            let rejectedReplacement = await replacementController.deleteSummary(
                documentID: edited.id, expectedRevision: edited.editRevision)
            XCTAssertFalse(rejectedReplacement)
            XCTAssertEqual(replacementController.summaryText, "Draft bound to the previously confirmed summary.")
            summaries = try await f.services.store.generatedDocuments(meetingID: f.selected, kind: .summary, limit: 50)
            XCTAssertEqual(Set(summaries.map(\.id)), [f.old.id, f.latest.id, replacement.id])
            XCTAssertEqual(summaries.first?.id, replacement.id)
            try await f.assertOriginalsAndUnrelatedContent()
        }
    }

    func testConcurrentReloadCannotResurrectDeletedVersionAndNewOutputCanLoadLater() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let loading = Task { await controller.load() }
            await Task.yield()
            let deleted = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            await loading.value
            XCTAssertTrue(deleted)
            XCTAssertNil(controller.summary)
            XCTAssertEqual(controller.summaryText, "")
            XCTAssertNil(controller.citations[f.latest.id])

            // Simulate a later successfully persisted generation without invoking
            // inference. The controller must allow a new document after deletion.
            let regenerated = try f.summaryDocument(text: "Freshly regenerated meeting overview.", createdAt: 30)
            try await f.services.store.createGeneratedDocument(regenerated)
            await controller.load()
            XCTAssertEqual(controller.summary, regenerated)
            XCTAssertEqual(controller.summaryText, regenerated.editedText)
            XCTAssertEqual(controller.citations[regenerated.id]?.count, 1)
            XCTAssertNil(controller.citations[f.latest.id])
            XCTAssertTrue(controller.canDeleteSummary)
            try await f.assertOriginalsAndUnrelatedContent()
        }
    }

    func testStorageFailureKeepsSummaryDraftAndCitationsAvailable() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.summaryText = "Unsaved summary draft survives a failed deletion."
            let beforeCitations = controller.citations[f.latest.id]?.map(\.id)
            try await f.services.store.close()
            let deleted = await controller.deleteSummary(documentID: f.latest.id, expectedRevision: 0)
            XCTAssertFalse(deleted)
            XCTAssertEqual(controller.summary, f.latest)
            XCTAssertEqual(controller.summaryText, "Unsaved summary draft survives a failed deletion.")
            XCTAssertEqual(controller.citations[f.latest.id]?.map(\.id), beforeCitations)
            XCTAssertEqual(controller.answers, [f.answer])
            XCTAssertFalse(controller.isDeletingSummary)
            XCTAssertTrue(controller.hasSummaryEdits)
            XCTAssertNotNil(controller.errorMessage)

            let reopened = try SQLiteMeetingStore(databaseURL: f.databaseURL)
            do {
                let summaries = try await reopened.generatedDocuments(meetingID: f.selected, kind: .summary, limit: 50)
                XCTAssertEqual(Set(summaries.map(\.id)), [f.old.id, f.latest.id])
                let answers = try await reopened.generatedDocuments(meetingID: f.selected, kind: .questionAnswer, limit: 50)
                XCTAssertEqual(answers, [f.answer])
            } catch { try? await reopened.close(); throw error }
            try await reopened.close()
        }
    }

    private func fixture(_ body: @MainActor (SummaryDeletionFixture) async throws -> Void) async throws {
        let f = try await SummaryDeletionFixture.create()
        do { try await body(f) }
        catch { try? await f.services.store.close(); try? f.remove(); throw error }
        // The failure fixture deliberately closes this connection already.
        try? await f.services.store.close()
        try f.remove()
    }
}

@MainActor
private struct SummaryDeletionFixture {
    let parent: URL
    let root: URL
    let services: LocalMinutesServices
    let selected: UUID
    let other: UUID
    let segment: StoredTranscriptSegment
    let note: StoredManualNote
    let old: StoredGeneratedDocument
    let latest: StoredGeneratedDocument
    let answer: StoredGeneratedDocument
    let foreignSummary: StoredGeneratedDocument
    let audioURL: URL
    let audioBytes: Data
    var databaseURL: URL { services.libraryRoot.appendingPathComponent("meetings.sqlite") }

    static func create() async throws -> Self {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-summary-delete-\(UUID().uuidString)", isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root)
        let selected = UUID(), other = UUID()
        let date = Date(timeIntervalSince1970: 1)
        for id in [selected, other] {
            try await services.store.createMeeting(.init(id: id, title: "Synthetic summary-deletion fixture",
                createdAt: date, recordingState: .completed, capturedSampleCount: 16_000))
        }
        let segment = StoredTranscriptSegment(id: UUID(), meetingID: selected, sequence: 0,
            startSample: 0, endSample: 16_000, text: "Original selected meeting evidence.", modelRevision: "synthetic-asr")
        try await services.store.appendFinalizedSegments([segment], to: selected)
        let note = StoredManualNote(meetingID: selected, text: "Original selected manual note.", editRevision: 0, modifiedAt: date)
        try await services.store.saveManualNote(note)
        func summary(meetingID: UUID, text: String, createdAt: TimeInterval) throws -> StoredGeneratedDocument {
            try makeSummary(meetingID: meetingID, segment: segment, text: text, createdAt: createdAt)
        }
        let old = try summary(meetingID: selected, text: "Earlier generated summary.", createdAt: 1)
        let latest = try summary(meetingID: selected, text: "Latest generated summary.", createdAt: 2)
        let foreign = try summary(meetingID: other, text: "Other meeting summary.", createdAt: 3)
        let answerPayload: [String: Any] = ["meeting_id": selected.uuidString, "status": "supported_quote",
            "evidence": [citation(segment)]]
        let answer = StoredGeneratedDocument(id: UUID(), meetingID: selected, kind: .questionAnswer,
            originalJSON: try JSONSerialization.data(withJSONObject: answerPayload, options: [.sortedKeys]),
            question: "What was reviewed?", editedText: "Original generated answer.",
            modelRevision: String(repeating: "a", count: 40), promptVersion: "meeting-qa-v1",
            createdAt: date, modifiedAt: date)
        for document in [old, latest, answer, foreign] { try await services.store.createGeneratedDocument(document) }
        let directory = services.meetingsDirectory.appendingPathComponent(selected.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let audioURL = directory.appendingPathComponent("preserved-recording.caf")
        let audioBytes = Data("Owned recording-byte preservation fixture.".utf8)
        try audioBytes.write(to: audioURL)
        let identity = SummaryCheckpointIdentity(jobID: selected, meetingID: selected,
            sourceSHA256: String(repeating: "1", count: 64), planSHA256: String(repeating: "2", count: 64),
            modelID: "synthetic-summary", modelRevision: String(repeating: "a", count: 40),
            modelSHA256: String(repeating: "3", count: 64), runtimeVersion: "fixture-runtime",
            promptVersion: "narrative-v1", contextTokenLimit: 4_096, reservedOutputTokens: 1_024, totalChunks: 2)
        let index: [String: Any] = ["schema_version": 2, "meeting_id": selected.uuidString,
            "topics": [["label": "Original discussion", "source_ids": [0]]]]
        try await services.summaryCheckpoints.save(.init(index: 0, chunkSHA256: String(repeating: "4", count: 64),
            mapJSON: try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])), matching: identity)
        return .init(parent: parent, root: root, services: services, selected: selected, other: other,
            segment: segment, note: note, old: old, latest: latest, answer: answer, foreignSummary: foreign,
            audioURL: audioURL, audioBytes: audioBytes)
    }

    func summaryDocument(text: String, createdAt: TimeInterval) throws -> StoredGeneratedDocument {
        try Self.makeSummary(meetingID: selected, segment: segment, text: text, createdAt: createdAt)
    }

    func assertOriginalsAndUnrelatedContent(file: StaticString = #filePath, line: UInt = #line) async throws {
        let transcript = try await services.store.transcript(meetingID: selected)
        let savedNote = try await services.store.manualNote(meetingID: selected)
        let answers = try await services.store.generatedDocuments(meetingID: selected, kind: .questionAnswer, limit: 50)
        let foreign = try await services.store.generatedDocuments(meetingID: other, kind: .summary, limit: 50)
        XCTAssertEqual(transcript, [segment], file: file, line: line)
        XCTAssertEqual(savedNote, note, file: file, line: line)
        XCTAssertEqual(answers, [answer], file: file, line: line)
        XCTAssertEqual(foreign, [foreignSummary], file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: audioURL), audioBytes, file: file, line: line)
    }

    private static func citation(_ segment: StoredTranscriptSegment) -> [String: Any] {
        ["source_id": segment.id.uuidString, "start_sample": segment.startSample,
         "end_sample": segment.endSample, "quote": segment.text]
    }

    private static func makeSummary(meetingID: UUID, segment: StoredTranscriptSegment,
                                    text: String, createdAt: TimeInterval) throws -> StoredGeneratedDocument {
        let paragraph: [String: Any] = ["text": text, "evidence": [citation(segment)]]
        let payload: [String: Any] = ["schema_version": 2, "meeting_id": meetingID.uuidString,
            "overview": paragraph, "bullets": [paragraph]]
        let date = Date(timeIntervalSince1970: createdAt)
        return .init(id: UUID(), meetingID: meetingID, kind: .summary,
            originalJSON: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            question: nil, editedText: text, modelRevision: String(repeating: "a", count: 40),
            promptVersion: "narrative-v1", createdAt: date, modifiedAt: date)
    }

    func remove() throws {
        let prefix = "localminutes-summary-delete-"
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside owned summary-deletion fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
