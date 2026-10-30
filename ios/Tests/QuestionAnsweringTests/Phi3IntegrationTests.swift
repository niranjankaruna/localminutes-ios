import CryptoKit
import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
import LocalMinutesQuestionAnswering

/// Pinned Phi-3 integration tests use actual CPU inference and grounded evidence.
@MainActor
final class Phi3IntegrationTests: XCTestCase {
    func testActualPinnedPhi3SummariesAndSelectedMeetingQuestions() async throws {
        phi3Progress("setup", "begin")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_PHI_MODEL_PATH"])
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
        let maximumCalls = 64
        let observations = Phi3ComparisonObservations(maximumCalls: maximumCalls)
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
            await observe("summary_positive", observations: observations) {
                let output = try await self.pipeline(runtime, observations, revision, stage: "summary_positive")
                    .summarize(selectedMeetingID: positiveID, source: positive)
                XCTAssertEqual(output.meetingID, positiveID)
                XCTAssertFalse(output.bullets.isEmpty)
                let prose = output.bullets.map(\.text).joined(separator: " ")
                XCTAssertTrue(prose.lowercased().contains("prototype") && prose.contains("Friday"))
                XCTAssertTrue(prose.lowercased().contains("guide") && prose.contains("Leo") && prose.contains("Thursday"))
                XCTAssertTrue(output.bullets.flatMap(\.evidence).contains { $0.sourceID == "action-source" })
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
                XCTAssertFalse(output.bullets.isEmpty)
                let prose = output.bullets.map(\.text).joined(separator: " ").lowercased()
                XCTAssertTrue(prose.contains("checklist"))
                for invented in ["maya", "leo", "friday", "thursday"] { XCTAssertFalse(prose.contains(invented)) }
                try self.validate(output, source: unknownSource, revision: revision)
                XCTAssertTrue((output.bullets.flatMap(\.evidence) + (output.overview?.evidence ?? []))
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
            let count = await observations.count
            XCTAssertEqual(count, 4, "One request per summary and one per question")
            XCTAssertLessThanOrEqual(count, maximumCalls)
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
                          _ revision: String, stage: String) -> AdaptiveSummaryPipeline {
        AdaptiveSummaryPipeline(modelRevision: revision,
            contextTokenLimit: runtime.contextTokenLimit, reservedOutputTokens: runtime.outputTokenLimit,
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

    private func validate(_ output: NarrativeSummary, source: GroundedSummarySource, revision: String) throws {
        let overview = try XCTUnwrap(output.overview)
        let evidence = output.bullets.flatMap(\.evidence) + overview.evidence
        XCTAssertFalse(evidence.isEmpty)
        for citation in evidence {
            let segment = try XCTUnwrap(source.segments.first { Data($0.id.utf8) == Data(citation.sourceID.utf8) })
            XCTAssertEqual(citation.startSample, segment.startSample)
            XCTAssertEqual(citation.endSample, segment.endSample)
            XCTAssertFalse(citation.quote.isEmpty)
            XCTAssertNotNil(Data(segment.text.utf8).range(of: Data(citation.quote.utf8)))
        }
        XCTAssertEqual(output.provenance.modelRevision, revision)
        XCTAssertEqual(output.provenance.promptVersion, AdaptiveSummaryPipeline.currentPromptVersion)
        for paragraph in output.bullets + [overview] {
            XCTAssertFalse(source.segments.contains { $0.text == paragraph.text }, "Narrative prose should synthesize, not copy a source row")
        }
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
    if let value = error as? NarrativeSummaryError { return "NarrativeSummaryError.\(value)" }
    if let value = error as? MeetingQuestionError { return "MeetingQuestionError.\(value)" }
    if error is CancellationError { return "CancellationError" }
    return String(reflecting: type(of: error))
}

extension Phi3IntegrationTests {
    /// A fixed synthetic quality screen, not a claim of broad meeting accuracy.
    /// Every tokenizer/generator call delegates to the pinned native runtime.
    func testActualPinnedPhi3RepresentativeNarrativeAndUnknownDeadlineRefusal() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_PHI_MODEL_PATH"])
        let url = URL(fileURLWithPath: path)
        let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, 2_393_231_072)
        guard size == 2_393_231_072 else { throw LocalSummaryRuntimeError.invalidModel }
        let input = try FileHandle(forReadingFrom: url)
        var hash = SHA256()
        do {
            while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
            try input.close()
        } catch { try? input.close(); throw error }
        let expected = "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef"
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, expected)
        guard digest == expected else { throw LocalSummaryRuntimeError.invalidModel }
        let runtime = try LocalSummaryRuntime(modelURL: url, contextSize: 4_096, threads: 4, chatFormat: .phi3)
        let revision = "a64113399c2f6b8ad3e11c394733a2ddadaa7f33"
        let observations = Phi3ComparisonObservations(maximumCalls: 2) // One summary and one question.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phi-representative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let database = root.appendingPathComponent("meetings.sqlite")
        var opened: SQLiteMeetingStore?
        do {
            let store = try SQLiteMeetingStore(databaseURL: database)
            opened = store
            let selected = questionUUID(601), other = questionUUID(602)
            for id in [selected, other] {
                try await store.createMeeting(.init(id: id, title: "Synthetic workshop release review",
                    createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed,
                    capturedSampleCount: 192_000))
            }
            let utterances = Self.representativePhiUtterances
            XCTAssertEqual(utterances.count, 12)
            let wordCount = utterances.joined(separator: " ").split(whereSeparator: \.isWhitespace).count
            XCTAssertTrue((450...650).contains(wordCount), "Keep this fixed quality screen bounded and readable")
            let segments = utterances.enumerated().map { index, text in
                StoredTranscriptSegment(id: questionUUID(610 + index), meetingID: selected, sequence: index,
                    startSample: Int64(index * 16_000), endSample: Int64((index + 1) * 16_000),
                    text: text, modelRevision: "synthetic-ASR-revision")
            }
            let otherSegments = [StoredTranscriptSegment(id: questionUUID(650), meetingID: other, sequence: 0,
                startSample: 0, endSample: 16_000,
                text: "OTHER_MEETING_CANARY_PHI_19: Nolan will review the checklist by June 1 for the telescope project.",
                modelRevision: "other-synthetic-ASR")]
            let note = StoredManualNote(meetingID: selected,
                text: "Earlier personal draft: ship on Monday. This was a proposal before the recorded final agreement. Original note — Café 📝.",
                editRevision: 4, modifiedAt: Date(timeIntervalSince1970: 2_000))
            let otherNote = StoredManualNote(meetingID: other, text: "OTHER_MEETING_NOTE_CANARY_PHI_19",
                editRevision: 1, modifiedAt: Date(timeIntervalSince1970: 2_001))
            try await store.appendFinalizedSegments(segments, to: selected)
            try await store.appendFinalizedSegments(otherSegments, to: other)
            try await store.saveManualNote(note)
            try await store.saveManualNote(otherNote)
            let persisted = try await store.transcript(meetingID: selected)
            let storedNote = try await store.manualNote(meetingID: selected)
            let persistedNote = try XCTUnwrap(storedNote)
            let source = GroundedSummarySource(meetingID: selected, segments: persisted.map {
                .init(id: $0.id.uuidString, startSample: $0.startSample, endSample: $0.endSample, text: $0.text)
            }, originalManualNotes: persistedNote.text)
            // The full fixture and dynamic response allowance must fit together.
            let pipeline = AdaptiveSummaryPipeline(modelRevision: revision, contextTokenLimit: 4_096,
                reservedOutputTokens: 1_024, tokenizer: { prompt in
                    XCTAssertFalse(prompt.contains("OTHER_MEETING_CANARY_PHI_19"))
                    XCTAssertFalse(prompt.contains("OTHER_MEETING_NOTE_CANARY_PHI_19"))
                    let count = try await runtime.promptTokenCount(prompt: prompt)
                    await observations.tokenized("representative_map", count: count)
                    return count
                }, generator: { prompt, schema, maximum in
                    let mapCalls = await observations.count
                    guard mapCalls < 255 else { throw LocalSummaryRuntimeError.generationFailed }
                    let actualCount = try await runtime.promptTokenCount(prompt: prompt)
                    XCTAssertLessThan(actualCount + maximum, 4_096)
                    try await observations.admit("representative_map", promptBytes: prompt.utf8.count,
                        maximumOutputTokens: maximum)
                    let raw = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum)
                    await observations.record("representative_map", raw: raw)
                    return raw
                })
            let summary = try await pipeline.summarize(selectedMeetingID: selected, source: source)
            let mapCalls = await observations.count
            XCTAssertEqual(mapCalls, 1, "Generate once from the complete meeting")
            XCTAssertEqual(summary.meetingID, selected)
            XCTAssertFalse(summary.bullets.isEmpty)
            let prose = summary.bullets.map(\.text).joined(separator: " ")
            XCTAssertTrue(prose.contains("prototype") && prose.contains("Friday"))
            XCTAssertTrue(prose.contains("guide") && prose.contains("Leo") && prose.contains("Thursday"))
            XCTAssertTrue(prose.lowercased().contains("checklist"))
            XCTAssertFalse(prose.contains("June 1") || prose.contains("Nolan"))
            try validate(summary, source: source, revision: revision)
            let evidence = summary.bullets.flatMap(\.evidence) + (summary.overview?.evidence ?? [])
            XCTAssertTrue(evidence.contains { $0.sourceID == segments[0].id.uuidString })
            XCTAssertTrue(evidence.contains { $0.sourceID == segments[11].id.uuidString })
            XCTAssertFalse(evidence.contains { $0.quote.contains("OTHER_MEETING") || $0.quote.contains("telescope") })
            let answerer = MeetingQuestionAnswerer(store: store, modelRevision: revision,
                tokenCounter: { try await runtime.promptTokenCount(prompt: $0) }, generator: { request in
                    XCTAssertEqual(request.meetingID, selected)
                    XCTAssertTrue(request.evidence.allSatisfy { $0.meetingID == selected })
                    XCTAssertTrue(request.evidence.contains { $0.id == segments[11].id })
                    XCTAssertFalse(request.prompt.contains("OTHER_MEETING_CANARY_PHI_19"))
                    XCTAssertFalse(request.prompt.contains("OTHER_MEETING_NOTE_CANARY_PHI_19"))
                    XCTAssertFalse(request.prompt.contains("June 1"))
                    let count = try await runtime.promptTokenCount(prompt: request.prompt)
                    XCTAssertEqual(count, request.promptTokenCount)
                    XCTAssertLessThan(count + request.maximumOutputTokens, 4_096)
                    try await observations.admit("representative_qa", promptBytes: request.prompt.utf8.count,
                        maximumOutputTokens: request.maximumOutputTokens)
                    let raw = try await runtime.generateJSON(prompt: request.prompt,
                        schema: request.schema, maximumTokens: request.maximumOutputTokens)
                    await observations.record("representative_qa", raw: raw)
                    let wire = try JSONDecoder().decode(QuestionWireOutput.self, from: Data(raw.utf8))
                    XCTAssertEqual(wire.status, "insufficient_evidence")
                    XCTAssertEqual(wire.source_id, "none"); XCTAssertEqual(wire.quote, "")
                    return raw
                })
            let answer = try await answerer.answer(meetingID: selected,
                question: "What deadline was agreed for the checklist review?")
            XCTAssertEqual(answer.meetingID, selected)
            XCTAssertEqual(answer.modelRevision, revision)
            XCTAssertEqual(answer.status, .insufficientEvidence)
            XCTAssertTrue(answer.evidence.isEmpty)
            let totalCalls = await observations.count
            XCTAssertEqual(totalCalls, mapCalls + 1)
            try await store.close(); opened = nil
            let reopened = try SQLiteMeetingStore(databaseURL: database)
            opened = reopened
            let finalSelected = try await reopened.transcript(meetingID: selected)
            let finalOther = try await reopened.transcript(meetingID: other)
            let finalNote = try await reopened.manualNote(meetingID: selected)
            let finalOtherNote = try await reopened.manualNote(meetingID: other)
            let documents = try await reopened.generatedDocuments(meetingID: selected)
            let otherDocuments = try await reopened.generatedDocuments(meetingID: other)
            XCTAssertEqual(finalSelected, segments); XCTAssertEqual(finalOther, otherSegments)
            XCTAssertEqual(finalNote, note); XCTAssertEqual(finalOtherNote, otherNote)
            XCTAssertTrue(documents.isEmpty); XCTAssertTrue(otherDocuments.isEmpty)
            try await reopened.close(); opened = nil
            await runtime.unload()
            try FileManager.default.removeItem(at: root)
        } catch {
            for stage in ["representative_map", "representative_qa"] {
                for raw in await observations.outputs(stage) {
                    phi3Emit("FIXED_SYNTHETIC_CANDIDATE_RAW[\(stage)] \(raw)")
                }
            }
            try? await opened?.close()
            await runtime.unload()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private static let representativePhiUtterances = [
        "Maya: We decided to ship the prototype on Friday. The earlier Tuesday suggestion was withdrawn before this final agreement. This release is for our small workshop demonstration, using the existing sample screens and the current local installation process without any customer information.",
        "Leo: I will write the guide by Thursday. The guide will explain the demonstration sequence using the sample screens. It will include the existing installation instructions and the steps for reopening the workshop session, so a colleague can follow along without asking for private account details.",
        "Priya: The workshop audience already knows the problem we are trying to solve. A short explanation of the original workflow should provide enough background. There is no need to introduce a new product name or compare the demonstration against an unrelated project during the opening discussion.",
        "Maya: The current sample data is entirely synthetic and belongs to this workshop exercise. The examples use invented people and ordinary planning tasks. Nobody needs to paste a real customer conversation into the demonstration to explain why an accurate record of decisions would be useful.",
        "Leo: The printed handout currently describes the older navigation arrangement. That difference is background for the discussion rather than another task assignment. The new guide already mentioned will describe the current screens, and the presenter can use those screens when showing the ordinary sequence.",
        "Priya: Several attendees have used the previous workshop exercise, so they may recognize the sample labels. Those familiar labels can help explain the transition between the old and current examples. They do not imply that any old schedule or responsibility has been carried into this meeting.",
        "Maya: Our discussion of the demonstration room is informational. The room has an ordinary projector and a table for the presenter. We have not agreed to buy equipment, book another venue, change the workshop budget, or assign anyone a separate facilities task in this conversation.",
        "Leo: The existing examples already show how a short decision can be traced to its original sentence. During the discussion we can explain the distinction between a proposal and a final agreement. A proposal remains background unless someone explicitly accepts it as the agreed plan.",
        "Priya: The same distinction applies to personal notes written before a meeting. A note may explain what someone expected to discuss, but it does not override the words people actually agreed during the conversation. Keeping that difference visible should make the workshop examples easier to understand.",
        "Maya: There is no additional release decision in this part of the discussion. We are describing how the synthetic examples are organized for the audience. The earlier agreement remains the recorded plan, and background remarks about the demonstration should not introduce a different shipment date.",
        "Leo: Questions about installation can be addressed with the existing guide material and the current sample screens. This comment does not add another owner or another deadline. It simply describes the information already available to the presenter when explaining how the workshop demonstration is opened.",
        "Priya: The checklist needs review. No owner or deadline was agreed for the checklist review. This remains a useful action to retain with both attributes unknown, rather than borrowing a person or date from another project or from an earlier personal note."
    ]
}
