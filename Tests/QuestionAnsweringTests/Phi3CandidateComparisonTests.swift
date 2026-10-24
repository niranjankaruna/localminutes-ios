import CryptoKit
import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
import LocalMinutesQuestionAnswering

/// An isolated candidate screen, never an application/default-model switch.
/// All four observations use actual CPU inference and unchanged semantic oracles.
@MainActor
final class Phi3CandidateComparisonTests: XCTestCase {
    func testActualPinnedPhi3ComparesTwoSummariesAndTwoSelectedMeetingQuestions() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_CANDIDATE_MODEL_PATH"])
        let url = URL(fileURLWithPath: path)
        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, 2_393_231_072)
        guard size == 2_393_231_072 else { throw LocalSummaryRuntimeError.invalidModel }
        let file = try FileHandle(forReadingFrom: url)
        var hash = SHA256()
        do {
            while let bytes = try file.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
            try file.close()
        } catch { try? file.close(); throw error }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let expected = "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef"
        XCTAssertEqual(digest, expected)
        guard digest == expected else { throw LocalSummaryRuntimeError.invalidModel }
        let runtime = try LocalSummaryRuntime(modelURL: url, contextSize: 4_096, threads: 4, chatFormat: .phi3)
        let observations = Phi3ComparisonObservations()
        let revision = expected
        do {
            let positiveID = UUID(uuidString: "40000000-0000-0000-0000-000000000018")!
            let positive = GroundedSummarySource(meetingID: positiveID, segments: [
                .init(id: "decision-source", startSample: 0, endSample: 16_000,
                      text: "Maya: We decided to ship the prototype on Friday."),
                .init(id: "action-source", startSample: 16_000, endSample: 32_000,
                      text: "Leo: I will write the guide by Thursday.")
            ], originalManualNotes: "Original manual note — Café 📝. Keep this separate from generated text.")
            let originalPositive = positive
            await observe("summary_positive", observations: observations) {
                let output = try await self.pipeline(runtime, observations, revision, stage: "summary_positive")
                    .summarize(selectedMeetingID: positiveID, source: positive)
                XCTAssertEqual(output.meetingID, positiveID)
                XCTAssertFalse(output.summaryPoints.isEmpty)
                XCTAssertTrue(output.decisions.contains { $0.text.lowercased().contains("prototype") && $0.text.contains("Friday") })
                let action = try XCTUnwrap(output.actions.first { $0.task.lowercased().contains("guide") })
                XCTAssertEqual(action.owner, "Leo"); XCTAssertEqual(action.due, "Thursday")
                XCTAssertFalse(action.evidence.isEmpty)
                XCTAssertTrue(action.evidence.contains { $0.sourceID == "action-source" })
                try self.validate(output, source: positive, revision: revision)
                XCTAssertEqual(positive, originalPositive)
            }
            let unknownID = UUID(uuidString: "50000000-0000-0000-0000-000000000018")!
            let unknownSource = GroundedSummarySource(meetingID: unknownID, segments: [
                .init(id: "unassigned-source", startSample: 0, endSample: 16_000,
                      text: "The checklist needs review. No owner or deadline was agreed.")
            ], originalManualNotes: "Original unknown-owner fixture note")
            await observe("summary_unknown", observations: observations) {
                let output = try await self.pipeline(runtime, observations, revision, stage: "summary_unknown")
                    .summarize(selectedMeetingID: unknownID, source: unknownSource)
                XCTAssertEqual(output.meetingID, unknownID)
                XCTAssertFalse(output.summaryPoints.isEmpty)
                XCTAssertTrue(output.decisions.isEmpty)
                let action = try XCTUnwrap(output.actions.first { $0.task.lowercased().contains("checklist") })
                XCTAssertNil(action.owner); XCTAssertNil(action.due)
                XCTAssertFalse(action.evidence.isEmpty)
                try self.validate(output, source: unknownSource, revision: revision)
                XCTAssertTrue((output.summaryPoints.flatMap(\.evidence) + output.actions.flatMap(\.evidence))
                    .allSatisfy { $0.sourceID == "unassigned-source" })
            }
            try await withQuestionFixture { fixture in
                for (stage, question) in [("qa_positive", "What is the launch budget?"),
                                          ("qa_unknown", "Who owns the launch budget?")] {
                    await self.observe(stage, observations: observations) {
                        let answerer = MeetingQuestionAnswerer(store: fixture.store, modelRevision: revision,
                            tokenCounter: { try await runtime.promptTokenCount(prompt: $0) }, generator: { request in
                                XCTAssertEqual(request.meetingID, fixture.selected)
                                XCTAssertTrue(request.evidence.allSatisfy { $0.meetingID == fixture.selected })
                                XCTAssertFalse(request.prompt.contains("OTHER_MEETING_CANARY_7"))
                                XCTAssertFalse(request.prompt.contains("999999"))
                                XCTAssertEqual(request.schema.fields.map(\.name), ["status", "source_id", "quote"])
                                XCTAssertEqual(request.schema.fields.first?.type,
                                    .stringEnumeration(["supported_quote", "insufficient_evidence"]))
                                XCTAssertEqual(request.schema.fields.last?.type, .string)
                                if case .stringEnumeration(let ids) = request.schema.fields[1].type {
                                    XCTAssertEqual(Set(ids), Set(["none"] + request.evidence.map { $0.id.uuidString }))
                                } else { XCTFail("Candidate grammar must retain every source and refusal ID") }
                                let count = try await runtime.promptTokenCount(prompt: request.prompt)
                                XCTAssertEqual(request.promptTokenCount, count)
                                XCTAssertLessThan(count + request.maximumOutputTokens, 4_096)
                                try await observations.admit(stage)
                                let raw = try await runtime.generateJSON(prompt: request.prompt,
                                    schema: request.schema, maximumTokens: request.maximumOutputTokens)
                                await observations.record(stage, raw: raw)
                                let wire = try JSONDecoder().decode(QuestionWireOutput.self, from: Data(raw.utf8))
                                if stage == "qa_positive" {
                                    XCTAssertEqual(wire.status, "supported_quote")
                                    XCTAssertEqual(wire.source_id, questionUUID(10).uuidString)
                                    XCTAssertTrue(wire.quote.contains("42000"))
                                } else {
                                    XCTAssertEqual(wire.status, "insufficient_evidence")
                                    XCTAssertEqual(wire.source_id, "none"); XCTAssertEqual(wire.quote, "")
                                }
                                return raw
                            })
                        let answer = try await answerer.answer(meetingID: fixture.selected, question: question)
                        XCTAssertEqual(answer.meetingID, fixture.selected)
                        XCTAssertEqual(answer.modelRevision, revision)
                        XCTAssertEqual(answer.promptVersion, "meeting-qa-v1")
                        if stage == "qa_positive" {
                            XCTAssertEqual(answer.status, .supportedQuote)
                            XCTAssertEqual(answer.evidence.count, 1)
                            let evidence = try XCTUnwrap(answer.evidence.first)
                            XCTAssertEqual(evidence.source, fixture.selectedSegments[0])
                            XCTAssertTrue(evidence.quote.contains("42000"))
                            XCTAssertTrue(evidence.quote.lowercased().contains("credits"))
                            XCTAssertFalse(evidence.quote.contains("1800")); XCTAssertFalse(evidence.quote.contains("999999"))
                            XCTAssertNotNil(Data(evidence.source.text.utf8).range(of: Data(evidence.quote.utf8)))
                        } else {
                            XCTAssertEqual(answer.status, .insufficientEvidence)
                            XCTAssertTrue(answer.evidence.isEmpty)
                        }
                    }
                }
                try await fixture.store.close()
                let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
                do {
                    let selected = try await reopened.transcript(meetingID: fixture.selected)
                    let other = try await reopened.transcript(meetingID: fixture.other)
                    let note = try await reopened.manualNote(meetingID: fixture.selected)
                    let otherNote = try await reopened.manualNote(meetingID: fixture.other)
                    XCTAssertEqual(selected, fixture.selectedSegments); XCTAssertEqual(other, fixture.otherSegments)
                    XCTAssertEqual(note, fixture.selectedNote); XCTAssertEqual(otherNote, fixture.otherNote)
                    try await reopened.close()
                } catch { try? await reopened.close(); throw error }
            }
            let count = await observations.count
            XCTAssertEqual(count, 4, "Exactly two summary and two question native generations are required")
            await runtime.unload()
        } catch { await runtime.unload(); throw error }
    }

    private func pipeline(_ runtime: LocalSummaryRuntime, _ observations: Phi3ComparisonObservations,
                          _ revision: String, stage: String) -> SummaryPipeline {
        SummaryPipeline(modelRevision: revision,
            tokenizer: { try await runtime.promptTokenCount(prompt: $0) }, generator: { prompt, schema, maximum in
                try await observations.admit(stage)
                let raw = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum)
                await observations.record(stage, raw: raw)
                return raw
            })
    }

    private func observe(_ stage: String, observations: Phi3ComparisonObservations,
                         body: @MainActor () async throws -> Void) async {
        let before = testRun?.failureCount ?? 0
        let started = Date()
        var threw = false
        do { try await body() }
        catch { threw = true; XCTFail("Candidate stage \(stage) threw: \(String(reflecting: type(of: error)))") }
        let failures = (testRun?.failureCount ?? 0) - before
        print("CANDIDATE_STAGE {\"stage\":\"\(stage)\",\"passed\":\(!threw && failures == 0),\"assertion_failures\":\(failures),\"seconds\":\(Int(Date().timeIntervalSince(started)))}")
        if threw || failures > 0 {
            for raw in await observations.outputs(stage) {
                print("FIXED_SYNTHETIC_CANDIDATE_RAW[\(stage)] \(raw)")
            }
        }
    }

    private func validate(_ output: GroundedSummary, source: GroundedSummarySource, revision: String) throws {
        let evidence = output.summaryPoints.flatMap(\.evidence) + output.decisions.flatMap(\.evidence)
            + output.actions.flatMap(\.evidence)
        XCTAssertFalse(evidence.isEmpty)
        for citation in evidence {
            let segment = try XCTUnwrap(source.segments.first { Data($0.id.utf8) == Data(citation.sourceID.utf8) })
            XCTAssertEqual(citation.startSample, segment.startSample)
            XCTAssertEqual(citation.endSample, segment.endSample)
            XCTAssertFalse(citation.quote.isEmpty)
            XCTAssertNotNil(Data(segment.text.utf8).range(of: Data(citation.quote.utf8)))
        }
        let provenance = output.summaryPoints.flatMap(\.provenance) + output.decisions.flatMap(\.provenance)
            + output.actions.flatMap(\.provenance)
        XCTAssertFalse(provenance.isEmpty)
        XCTAssertTrue(provenance.allSatisfy {
            $0.modelRevision == revision && $0.promptVersion == "grounded-map-v1" && $0.mapIndex >= 0
        })
    }
}

private actor Phi3ComparisonObservations {
    private(set) var count = 0
    private var raw: [String: [String]] = [:]
    func admit(_ stage: String) throws {
        guard count < 4 else { throw LocalSummaryRuntimeError.generationFailed }
        count += 1
    }
    func record(_ stage: String, raw: String) { self.raw[stage, default: []].append(String(raw.prefix(4_096))) }
    func outputs(_ stage: String) -> [String] { raw[stage] ?? [] }
}
