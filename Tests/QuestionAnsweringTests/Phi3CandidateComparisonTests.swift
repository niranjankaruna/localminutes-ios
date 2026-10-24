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
        try await runComparison(includeQuestions: true)
    }

    func testActualPinnedPhi3ComparesTwoSummariesWithReviewedRevision() async throws {
        try await runComparison(includeQuestions: false)
    }

    func testActualPinnedPhi3PositiveSummaryWithReviewedRevision() async throws {
        try await runComparison(includeQuestions: false, summaries: .positive)
    }

    func testActualPinnedPhi3UnknownSummaryWithReviewedRevision() async throws {
        try await runComparison(includeQuestions: false, summaries: .unknown)
    }

    private enum SummarySelection { case both, positive, unknown }

    private func runComparison(includeQuestions: Bool, summaries: SummarySelection = .both) async throws {
        phi3Progress("setup", "begin")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_CANDIDATE_MODEL_PATH"])
        let url = URL(fileURLWithPath: path)
        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, 2_393_231_072)
        guard size == 2_393_231_072 else { throw LocalSummaryRuntimeError.invalidModel }
        phi3Progress("setup", "hash_begin")
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
        phi3Progress("setup", "hash_verified")
        phi3Progress("setup", "native_load_begin")
        let runtime = try LocalSummaryRuntime(modelURL: url, contextSize: 4_096, threads: 4, chatFormat: .phi3)
        phi3Progress("setup", "native_loaded")
        let expectedCalls = (summaries == .both ? 2 : 1) + (includeQuestions ? 2 : 0)
        let observations = Phi3ComparisonObservations(maximumCalls: expectedCalls)
        let revision = "a64113399c2f6b8ad3e11c394733a2ddadaa7f33"
        do {
            let positiveID = UUID(uuidString: "40000000-0000-0000-0000-000000000018")!
            let positive = GroundedSummarySource(meetingID: positiveID, segments: [
                .init(id: "decision-source", startSample: 0, endSample: 16_000,
                      text: "Maya: We decided to ship the prototype on Friday."),
                .init(id: "action-source", startSample: 16_000, endSample: 32_000,
                      text: "Leo: I will write the guide by Thursday.")
            ], originalManualNotes: "Original manual note — Café 📝. Keep this separate from generated text.")
            let originalPositive = positive
            if summaries != .unknown {
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
            }
            let unknownID = UUID(uuidString: "50000000-0000-0000-0000-000000000018")!
            let unknownSource = GroundedSummarySource(meetingID: unknownID, segments: [
                .init(id: "unassigned-source", startSample: 0, endSample: 16_000,
                      text: "The checklist needs review. No owner or deadline was agreed.")
            ], originalManualNotes: "Original unknown-owner fixture note")
            if summaries != .positive {
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
            }
            if includeQuestions {
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
                                try await observations.admit(stage, promptBytes: request.prompt.utf8.count,
                                    maximumOutputTokens: request.maximumOutputTokens)
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
            }
            let count = await observations.count
            XCTAssertEqual(count, expectedCalls,
                "Every selected observation must execute actual native inference exactly once")
            phi3Progress("setup", "unload_begin")
            await runtime.unload()
            phi3Progress("setup", "unloaded")
        } catch {
            phi3Progress("setup", "failed", error: phi3SafeError(error))
            await runtime.unload()
            phi3Progress("setup", "unloaded")
            throw error
        }
    }

    private func pipeline(_ runtime: LocalSummaryRuntime, _ observations: Phi3ComparisonObservations,
                          _ revision: String, stage: String) -> SummaryPipeline {
        SummaryPipeline(modelRevision: revision,
            tokenizer: { prompt in
                await observations.tokenizing(stage, bytes: prompt.utf8.count)
                let count = try await runtime.promptTokenCount(prompt: prompt)
                await observations.tokenized(stage, count: count)
                return count
            }, generator: { prompt, schema, maximum in
                try await observations.admit(stage, promptBytes: prompt.utf8.count, maximumOutputTokens: maximum)
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
        phi3Progress(stage, "begin")
        let heartbeat = Task { @MainActor in
            for _ in 0..<60 {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                await observations.heartbeat(stage, seconds: Int(Date().timeIntervalSince(started)))
            }
        }
        defer { heartbeat.cancel() }
        do { try await body() }
        catch {
            threw = true
            let safe = phi3SafeError(error)
            phi3Progress(stage, "failed", error: safe)
            XCTFail("Candidate stage \(stage) threw: \(safe)")
        }
        let failures = (testRun?.failureCount ?? 0) - before
        phi3Emit("CANDIDATE_STAGE {\"stage\":\"\(stage)\",\"passed\":\(!threw && failures == 0),\"assertion_failures\":\(failures),\"seconds\":\(Int(Date().timeIntervalSince(started)))}")
        if threw || failures > 0 {
            for raw in await observations.outputs(stage) {
                phi3Emit("FIXED_SYNTHETIC_CANDIDATE_RAW[\(stage)] \(raw)")
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
    private let maximumCalls: Int
    private var phases: [String: String] = [:]
    private var tokenizations: [String: Int] = [:]
    init(maximumCalls: Int) { self.maximumCalls = maximumCalls }
    func tokenizing(_ stage: String, bytes: Int) {
        phases[stage] = "tokenization"
        phi3Progress(stage, "tokenization_begin", counts: ["prompt_bytes": bytes])
    }
    func tokenized(_ stage: String, count: Int) {
        tokenizations[stage, default: 0] += 1
        phi3Progress(stage, "tokenization_complete", counts: ["tokens": count,
            "tokenizations": tokenizations[stage, default: 0]])
    }
    func admit(_ stage: String, promptBytes: Int, maximumOutputTokens: Int) throws {
        guard count < maximumCalls else { throw LocalSummaryRuntimeError.generationFailed }
        count += 1
        phases[stage] = "native_generation"
        phi3Progress(stage, "generation_begin", counts: ["generation_calls": count,
            "prompt_bytes": promptBytes, "maximum_output_tokens": maximumOutputTokens])
    }
    func record(_ stage: String, raw: String) {
        self.raw[stage, default: []].append(String(raw.prefix(4_096)))
        phases[stage] = "semantic_validation"
        phi3Progress(stage, "generation_complete", counts: ["generation_calls": count, "output_bytes": raw.utf8.count])
    }
    func heartbeat(_ stage: String, seconds: Int) {
        phi3Progress(stage, phases[stage] ?? "awaiting_pipeline", counts: ["elapsed_seconds": seconds,
            "generation_calls": count, "tokenizations": tokenizations[stage, default: 0]])
    }
    func outputs(_ stage: String) -> [String] { raw[stage] ?? [] }
}

/// Direct writes avoid stdio/tee buffering hiding the last native boundary on
/// timeout. No source/prompt/path or model bytes appear in progress diagnostics.
private func phi3Emit(_ line: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
}

private func phi3Progress(_ stage: String, _ event: String, counts: [String: Int] = [:], error: String? = nil) {
    var payload: [String: Any] = ["stage": stage, "event": event]
    counts.forEach { payload[$0.key] = $0.value }
    if let error { payload["error"] = error }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8) { phi3Emit("CANDIDATE_PROGRESS " + json) }
}

private func phi3SafeError(_ error: any Error) -> String {
    if let value = error as? LocalSummaryRuntimeError { return "LocalSummaryRuntimeError.\(value)" }
    if let value = error as? GroundedSummaryError { return "GroundedSummaryError.\(value)" }
    if let value = error as? SummaryPipelineError { return "SummaryPipelineError.\(value)" }
    if let value = error as? MeetingQuestionError { return "MeetingQuestionError.\(value)" }
    if let value = error as? SummaryChunkPlannerError {
        switch value {
        case .oversizedSegment: return "SummaryChunkPlannerError.oversizedSegment"
        default: return "SummaryChunkPlannerError.\(value)"
        }
    }
    if error is CancellationError { return "CancellationError" }
    return String(reflecting: type(of: error))
}
