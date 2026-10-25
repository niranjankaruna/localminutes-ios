#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

/// Actual selected-meeting controller and SQLite CAS; stored prior output is
/// synthetic. Editing never runs or substitutes a local inference model.
@MainActor
final class NativeAnswerEditingTests: XCTestCase {
    func testAnswerEditDurablyChangesOnlyDisplayCopyAndRetainsOriginalEvidencePinsAndOtherMeeting() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let beforeCitations = controller.citations[f.answer.id]?.map(\.id)
            XCTAssertEqual(beforeCitations?.count, 1)
            controller.answerDrafts[f.answer.id] = "User-reviewed answer café — edited separately."
            let saved = await controller.flushAnswerEdits(documentID: f.answer.id)
            XCTAssertTrue(saved)
            let actual = try await f.answerFromStore(f.answer.id, meeting: f.selected)
            XCTAssertEqual(actual.editedText, controller.answerDrafts[f.answer.id])
            XCTAssertEqual(actual.editRevision, 1)
            self.assertImmutable(actual, original: f.answer)
            XCTAssertEqual(controller.answers.first { $0.id == f.answer.id }, actual)
            XCTAssertEqual(controller.citations[f.answer.id]?.map(\.id), beforeCitations)
            let other = try await f.answerFromStore(f.foreignAnswer.id, meeting: f.other)
            XCTAssertEqual(other, f.foreignAnswer)
            let untouched = try await f.answerFromStore(f.secondAnswer.id, meeting: f.selected)
            XCTAssertEqual(untouched, f.secondAnswer)
            let notes = try await f.services.store.manualNote(meetingID: f.selected)
            let transcript = try await f.services.store.transcript(meetingID: f.selected)
            XCTAssertEqual(notes?.text, "Original selected manual note.")
            XCTAssertEqual(transcript, [f.segment])
            await controller.load()
            XCTAssertEqual(controller.answers.first { $0.id == f.answer.id }, actual)
            let reopened = try SQLiteMeetingStore(databaseURL: f.services.libraryRoot.appendingPathComponent("meetings.sqlite"))
            do {
                let rows = try await reopened.generatedDocuments(meetingID: f.selected, kind: .questionAnswer, limit: 50)
                XCTAssertEqual(rows.first { $0.id == f.answer.id }, actual,
                    "A fresh database connection must observe the committed answer edit")
            } catch { try? await reopened.close(); throw error }
            try await reopened.close()
        }
    }

    func testConcurrentSavesSerializeOneRevisionAndLaterDraftCanSaveAgain() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.answerDrafts[f.answer.id] = "First explicit answer edit."
            async let one = controller.flushAnswerEdits(documentID: f.answer.id)
            async let two = controller.flushAnswerEdits(documentID: f.answer.id)
            let results = await [one, two]
            XCTAssertEqual(results, [true, true])
            let first = try await f.answerFromStore(f.answer.id, meeting: f.selected)
            XCTAssertEqual(first.editRevision, 1, "Duplicate save taps must join, not conflict or create duplicate revisions")
            controller.answerDrafts[f.answer.id] = "Second explicit answer edit."
            let saved = await controller.flushAnswerEdits(documentID: f.answer.id)
            XCTAssertTrue(saved)
            let second = try await f.answerFromStore(f.answer.id, meeting: f.selected)
            XCTAssertEqual(second.editedText, "Second explicit answer edit.")
            XCTAssertEqual(second.editRevision, 2)
            XCTAssertTrue(controller.savingAnswerIDs.isEmpty)
            XCTAssertTrue(controller.answerEditConflicts.isEmpty)
        }
    }

    func testStaleAnswerCASPreservesDraftAndNewerStoredCopyUntilExplicitReopen() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.answerDrafts[f.answer.id] = "Unsaved local answer draft."
            let newer = try await f.services.store.saveGeneratedDocumentEdit(id: f.answer.id, meetingID: f.selected,
                text: "Newer saved answer elsewhere.", expectedRevision: 0, modifiedAt: Date(timeIntervalSince1970: 5))
            let saved = await controller.flushAnswerEdits(documentID: f.answer.id)
            XCTAssertFalse(saved)
            XCTAssertTrue(controller.answerEditConflicts.contains(f.answer.id))
            XCTAssertNotNil(controller.answerSaveErrors[f.answer.id])
            XCTAssertEqual(controller.answerDrafts[f.answer.id], "Unsaved local answer draft.")
            let stored = try await f.answerFromStore(f.answer.id, meeting: f.selected)
            XCTAssertEqual(stored, newer)
            await controller.reopenSavedAnswer(documentID: f.answer.id)
            XCTAssertEqual(controller.answerDrafts[f.answer.id], newer.editedText)
            XCTAssertEqual(controller.answers.first { $0.id == f.answer.id }, newer)
            XCTAssertFalse(controller.answerEditConflicts.contains(f.answer.id))
            XCTAssertNil(controller.answerSaveErrors[f.answer.id])
            self.assertImmutable(newer, original: f.answer)
        }
    }

    func testLeavingMeetingFlushesBoundAnswerDraftAndReopenedControllerKeepsOtherMeetingUntouched() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.answerDrafts[f.answer.id] = "Navigation-preserved answer edit."
            controller.leaveMeeting()
            var stored = f.answer
            for _ in 0..<200 {
                stored = try await f.answerFromStore(f.answer.id, meeting: f.selected)
                if stored.editRevision == 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(stored.editedText, "Navigation-preserved answer edit.")
            XCTAssertEqual(stored.editRevision, 1)
            let reopened = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await reopened.load()
            XCTAssertEqual(reopened.answers.first { $0.id == f.answer.id }?.editedText, stored.editedText)
            let other = try await f.answerFromStore(f.foreignAnswer.id, meeting: f.other)
            XCTAssertEqual(other, f.foreignAnswer)
        }
    }

    func testFlushAllSavesEachSelectedAnswerAndForeignOrUnknownDocumentIDsCannotBeEdited() async throws {
        try await fixture { f in
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            controller.answerDrafts[f.answer.id] = "First selected saved edit."
            controller.answerDrafts[f.secondAnswer.id] = "Second selected saved edit."
            controller.answerDrafts[f.foreignAnswer.id] = "Attempted cross-meeting edit."
            let foreign = await controller.flushAnswerEdits(documentID: f.foreignAnswer.id)
            let unknown = await controller.flushAnswerEdits(documentID: UUID())
            XCTAssertFalse(foreign); XCTAssertFalse(unknown)
            let saved = await controller.flushAllAnswerEdits()
            XCTAssertTrue(saved, "Foreign draft keys cannot prevent flushing this controller's actual selected answers")
            let first = try await f.answerFromStore(f.answer.id, meeting: f.selected)
            let second = try await f.answerFromStore(f.secondAnswer.id, meeting: f.selected)
            let other = try await f.answerFromStore(f.foreignAnswer.id, meeting: f.other)
            XCTAssertEqual(first.editedText, "First selected saved edit.")
            XCTAssertEqual(second.editedText, "Second selected saved edit.")
            XCTAssertEqual(other, f.foreignAnswer)
        }
    }

    private func assertImmutable(_ actual: StoredGeneratedDocument, original: StoredGeneratedDocument,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.meetingID, original.meetingID, file: file, line: line)
        XCTAssertEqual(actual.kind, original.kind, file: file, line: line)
        XCTAssertEqual(actual.originalJSON, original.originalJSON, file: file, line: line)
        XCTAssertEqual(actual.question, original.question, file: file, line: line)
        XCTAssertEqual(actual.modelRevision, original.modelRevision, file: file, line: line)
        XCTAssertEqual(actual.promptVersion, original.promptVersion, file: file, line: line)
        XCTAssertEqual(actual.createdAt, original.createdAt, file: file, line: line)
    }

    private func fixture(_ body: @MainActor (AnswerEditingFixture) async throws -> Void) async throws {
        let f = try await AnswerEditingFixture.create()
        do { try await body(f) }
        catch { try? await f.services.store.close(); try? f.remove(); throw error }
        try await f.services.store.close()
        try f.remove()
    }
}

@MainActor
private struct AnswerEditingFixture {
    let parent: URL
    let root: URL
    let services: LocalMinutesServices
    let selected: UUID
    let other: UUID
    let segment: StoredTranscriptSegment
    let answer: StoredGeneratedDocument
    let secondAnswer: StoredGeneratedDocument
    let foreignAnswer: StoredGeneratedDocument

    static func create() async throws -> Self {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-answer-edit-\(UUID().uuidString)", isDirectory: true)
        let services = try LocalMinutesServices(rootURL: root)
        let selected = UUID(), other = UUID()
        let date = Date(timeIntervalSince1970: 1)
        for id in [selected, other] {
            try await services.store.createMeeting(.init(id: id, title: "Synthetic answer-edit fixture",
                createdAt: date, recordingState: .completed, capturedSampleCount: 16_000))
        }
        let segment = StoredTranscriptSegment(id: UUID(), meetingID: selected, sequence: 0,
            startSample: 0, endSample: 16_000, text: "Original selected answer evidence.", modelRevision: "synthetic-asr")
        try await services.store.appendFinalizedSegments([segment], to: selected)
        try await services.store.saveManualNote(.init(meetingID: selected, text: "Original selected manual note.",
            editRevision: 0, modifiedAt: date))
        func answer(meetingID: UUID, text: String) throws -> StoredGeneratedDocument {
            let payload: [String: Any] = ["meeting_id": meetingID.uuidString, "status": "supported_quote",
                "evidence": [["source_id": segment.id.uuidString, "start_sample": 0,
                              "end_sample": 16_000, "quote": segment.text]]]
            return .init(id: UUID(), meetingID: meetingID, kind: .questionAnswer,
                originalJSON: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                question: "Synthetic selected-meeting question?", editedText: text,
                modelRevision: String(repeating: "a", count: 40), promptVersion: "synthetic-answer-edit-v1",
                createdAt: date, modifiedAt: date)
        }
        let first = try answer(meetingID: selected, text: "Original generated answer.")
        let second = try answer(meetingID: selected, text: "Second original generated answer.")
        let foreign = try answer(meetingID: other, text: "Other meeting original answer.")
        for document in [first, second, foreign] { try await services.store.createGeneratedDocument(document) }
        return .init(parent: parent, root: root, services: services, selected: selected, other: other,
            segment: segment, answer: first, secondAnswer: second, foreignAnswer: foreign)
    }

    func answerFromStore(_ id: UUID, meeting: UUID) async throws -> StoredGeneratedDocument {
        let rows = try await services.store.generatedDocuments(meetingID: meeting, kind: .questionAnswer, limit: 50)
        return try XCTUnwrap(rows.first { $0.id == id })
    }

    func remove() throws {
        let prefix = "localminutes-answer-edit-"
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside owned answer-edit fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
