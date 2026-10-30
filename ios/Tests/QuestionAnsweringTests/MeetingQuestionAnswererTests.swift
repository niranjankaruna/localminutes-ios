import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesQuestionAnswering

/// Real on-disk SQLite and its real FTS5 index at schema3. Only model generation/token
/// counting are boundary doubles in this orchestration suite.
@MainActor
final class MeetingQuestionAnswererTests: XCTestCase {
    func testNaturalQuestionFindsSelectedEvidenceWithoutNaivelyANDingStopwordsAndPreservesOriginals() async throws {
        try await withQuestionFixture { fixture in
            let question = "What is the launch budget?"
            let naive = try await fixture.store.retrieveEvidence(meetingID: fixture.selected, query: question)
            XCTAssertTrue(naive.isEmpty, "Fixture exposes the missing 'what' term; QA must plan useful bounded literal retrieval")
            let probe = QuestionGenerationProbe()
            let json = try QuestionWireOutput(status: "supported_quote", source_id: questionUUID(10).uuidString,
                quote: "The launch budget is 42000 credits.").json()
            let answerer = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                tokenCounter: { _ in 128 }, generator: { request in
                    await probe.record(request, output: json); return json
                })
            let answer = try await answerer.answer(meetingID: fixture.selected, question: question)
            XCTAssertEqual(answer.status, .supportedQuote)
            XCTAssertEqual(answer.meetingID, fixture.selected)
            XCTAssertEqual(answer.evidence, [MeetingQuestionEvidence(source: fixture.selectedSegments[0],
                quote: "The launch budget is 42000 credits.")])
            XCTAssertEqual(answer.modelRevision, "unit-boundary-model")
            XCTAssertEqual(answer.promptVersion, "meeting-qa-v1")
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1)
            if let request = requests.first {
                XCTAssertEqual(request.question, question)
                XCTAssertEqual(request.meetingID, fixture.selected)
                XCTAssertTrue(request.evidence.contains(fixture.selectedSegments[0]))
                XCTAssertTrue(request.evidence.allSatisfy { $0.meetingID == fixture.selected })
                XCTAssertLessThanOrEqual(request.evidence.count, 8)
                XCTAssertEqual(request.promptTokenCount, 128)
                XCTAssertLessThan(request.promptTokenCount + request.maximumOutputTokens, 4_096)
                XCTAssertFalse(request.prompt.contains("OTHER_MEETING_CANARY_7"))
                XCTAssertFalse(request.prompt.contains("Original other notes"))
                XCTAssertEqual(request.schema.fields.map(\.name), ["status", "source_id", "quote"])
                if request.schema.fields.count == 3 {
                    XCTAssertEqual(request.schema.fields[0].type,
                        .stringEnumeration(["supported_quote", "insufficient_evidence"]))
                    XCTAssertEqual(request.schema.fields[2].type, .string,
                        "Grammar bounds structure; it must not hard-code the expected answer quote")
                    if case .stringEnumeration(let ids) = request.schema.fields[1].type {
                        XCTAssertEqual(Set(ids), Set(["none"] + request.evidence.map { $0.id.uuidString }))
                    } else { XCTFail("Evidence domain must contain every supplied source ID plus refusal") }
                }
            }
            // Reopen the actual database; a cached projection cannot prove that
            // QA left the user's original notes and transcript untouched.
            try await fixture.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            do {
                let selected = try await reopened.transcript(meetingID: fixture.selected)
                let other = try await reopened.transcript(meetingID: fixture.other)
                let selectedNote = try await reopened.manualNote(meetingID: fixture.selected)
                let otherNote = try await reopened.manualNote(meetingID: fixture.other)
                XCTAssertEqual(selected, fixture.selectedSegments); XCTAssertEqual(other, fixture.otherSegments)
                XCTAssertEqual(selectedNote, fixture.selectedNote); XCTAssertEqual(otherNote, fixture.otherNote)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        }
    }

    func testUnknownSelectedFactRefusesAndAnUnselectedCitationIsRejected() async throws {
        try await withQuestionFixture { fixture in
            let probe = QuestionGenerationProbe()
            let refusal = try QuestionWireOutput(status: "insufficient_evidence", source_id: "none", quote: "").json()
            let answerer = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                tokenCounter: { _ in 128 }, generator: { request in
                    await probe.record(request, output: refusal); return refusal
                })
            let question = "Who owns the launch budget?"
            let answer = try await answerer.answer(meetingID: fixture.selected, question: question)
            XCTAssertEqual(answer.status, .insufficientEvidence)
            XCTAssertTrue(answer.evidence.isEmpty)
            let requests = await probe.requests
            XCTAssertEqual(requests.count, 1, "The selected undecided-owner evidence must reach the generation boundary")
            if let request = requests.first {
                XCTAssertTrue(request.evidence.contains(fixture.selectedSegments[2]))
                XCTAssertTrue(request.evidence.allSatisfy { $0.meetingID == fixture.selected })
                XCTAssertFalse(request.prompt.contains("999999"))
                XCTAssertFalse(request.prompt.contains("OTHER_MEETING_CANARY_7"))
            }
            let forged = try QuestionWireOutput(status: "supported_quote", source_id: questionUUID(20).uuidString,
                quote: "Its owner is Alex.").json()
            let invalid = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                tokenCounter: { _ in 128 }, generator: { _ in forged })
            do {
                _ = try await invalid.answer(meetingID: fixture.selected, question: question)
                XCTFail("Unselected evidence from a model response must never be published")
            } catch { XCTAssertEqual(error as? MeetingQuestionError, .unsupportedEvidence) }
            let selectedNote = try await fixture.store.manualNote(meetingID: fixture.selected)
            let otherSource = try await fixture.store.transcript(meetingID: fixture.other)
            XCTAssertEqual(selectedNote, fixture.selectedNote); XCTAssertEqual(otherSource, fixture.otherSegments)
        }
    }

    func testQuestionExcerptAndCanonicalTokenBudgetsRejectBeforeGeneration() async throws {
        try await withQuestionFixture { fixture in
            let probe = QuestionGenerationProbe()
            let refusal = try QuestionWireOutput(status: "insufficient_evidence", source_id: "none", quote: "").json()
            let generator: MeetingQuestionGenerator = { request in
                await probe.record(request, output: refusal); return refusal
            }
            let questionBound = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                limits: .init(maximumQuestionUTF8Bytes: 64), tokenCounter: { _ in 128 }, generator: generator)
            do {
                _ = try await questionBound.answer(meetingID: fixture.selected, question: String(repeating: "📝", count: 17))
                XCTFail("Question bound counts UTF-8 bytes, not graphemes")
            } catch { XCTAssertEqual(error as? MeetingQuestionError, .questionTooLong) }
            let tokenBound = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                limits: .init(contextTokenLimit: 512, reservedOutputTokens: 64),
                tokenCounter: { _ in 448 }, generator: generator)
            do {
                _ = try await tokenBound.answer(meetingID: fixture.selected, question: "What is the launch budget?")
                XCTFail("Exact input + output reserve must be strictly below native context capacity")
            } catch { XCTAssertEqual(error as? MeetingQuestionError, .evidenceExceedsBudget) }
            let excerptBound = MeetingQuestionAnswerer(store: fixture.store, modelRevision: "unit-boundary-model",
                limits: .init(maximumExcerptUTF8Bytes: 8), tokenCounter: { _ in 128 }, generator: generator)
            do {
                _ = try await excerptBound.answer(meetingID: fixture.selected, question: "What is the launch budget?")
                XCTFail("Do not silently truncate original evidence to make a source fit")
            } catch { XCTAssertEqual(error as? MeetingQuestionError, .evidenceExceedsBudget) }
            let requests = await probe.requests
            XCTAssertTrue(requests.isEmpty, "No out-of-budget request reaches generation")
        }
    }
}
