import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesSummary

/// Mandatory real-Qwen pipeline oracle. No boundary doubles, network download,
/// answer injection or semantic string normalization is allowed in this case.
@MainActor
final class ActualSummaryPipelineTests: XCTestCase {
    func testActualQwenMapsAndValidatesGroundedDecisionsActionsAndUnknownAttributes() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_QWEN_MODEL_PATH"])
        let modelURL = URL(fileURLWithPath: path)
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        XCTAssertEqual(size?.int64Value, 1_117_320_736)
        guard size?.int64Value == 1_117_320_736 else { throw LocalSummaryRuntimeError.invalidModel }
        let file = try FileHandle(forReadingFrom: modelURL)
        var hasher = SHA256()
        while let bytes = try file.read(upToCount: 65_536), !bytes.isEmpty { hasher.update(data: bytes) }
        try file.close()
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e")
        guard digest == "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e" else {
            throw LocalSummaryRuntimeError.invalidModel
        }
        let runtime = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, threads: 4)
        let calls = ActualPipelineCallCounter()
        let revision = "91cad51170dc346986eccefdc2dd33a9da36ead9"
        let pipeline = SummaryPipeline(modelRevision: revision,
            tokenizer: { prompt in
                let count = try await runtime.promptTokenCount(prompt: prompt)
                await calls.tokenized()
                return count
            }, generator: { prompt, schema, maximum in
                let result = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum)
                await calls.generated(result)
                return result
            })
        let meetingID = UUID(uuidString: "40000000-0000-0000-0000-000000000018")!
        let source = GroundedSummarySource(meetingID: meetingID, segments: [
            .init(id: "decision-source", startSample: 0, endSample: 16_000,
                  text: "Maya: We decided to ship the prototype on Friday."),
            .init(id: "action-source", startSample: 16_000, endSample: 32_000,
                  text: "Leo: I will write the guide by Thursday.")
        ], originalManualNotes: "Original manual note — Café 📝. Keep this separate from generated text.")
        let before = source
        let failuresBefore = testRun?.failureCount ?? 0
        do {
            let positive = try await pipeline.summarize(selectedMeetingID: meetingID, source: source)
            XCTAssertEqual(positive.meetingID, meetingID)
            XCTAssertFalse(positive.summaryPoints.isEmpty)
            XCTAssertTrue(positive.decisions.contains {
                $0.text.lowercased().contains("prototype") && $0.text.contains("Friday")
            }, "Actual output must include the supported decision, without demanding a particular paraphrase")
            let action = try XCTUnwrap(positive.actions.first { $0.task.lowercased().contains("guide") })
            XCTAssertEqual(action.owner, "Leo")
            XCTAssertEqual(action.due, "Thursday")
            XCTAssertFalse(action.evidence.isEmpty)
            XCTAssertTrue(action.evidence.contains { $0.sourceID == "action-source" })
            try assertAllQuotesAndProvenance(positive, source: source, revision: revision)
            XCTAssertEqual(source, before)
            XCTAssertEqual(Array(source.originalManualNotes.utf8), Array(before.originalManualNotes.utf8))

            let unknownID = UUID(uuidString: "50000000-0000-0000-0000-000000000018")!
            let unknown = GroundedSummarySource(meetingID: unknownID, segments: [
                .init(id: "unassigned-source", startSample: 0, endSample: 16_000,
                      text: "The checklist needs review. No owner or deadline was agreed.")
            ], originalManualNotes: "Original unknown-owner fixture note")
            let negative = try await pipeline.summarize(selectedMeetingID: unknownID, source: unknown)
            XCTAssertEqual(negative.meetingID, unknownID)
            XCTAssertFalse(negative.summaryPoints.isEmpty)
            XCTAssertTrue(negative.decisions.isEmpty, "Do not invent a decision from missing agreement")
            let unassigned = try XCTUnwrap(negative.actions.first { $0.task.lowercased().contains("checklist") })
            XCTAssertNil(unassigned.owner)
            XCTAssertNil(unassigned.due)
            XCTAssertFalse(unassigned.evidence.isEmpty)
            try assertAllQuotesAndProvenance(negative, source: unknown, revision: revision)
            XCTAssertTrue((negative.summaryPoints.flatMap(\.evidence) + negative.actions.flatMap(\.evidence))
                .allSatisfy { $0.sourceID == "unassigned-source" })
            // Four minutes of original, unlabeled speech in minute-long ASR
            // paragraphs. Long quoted output must not consume 1024 tokens per
            // call before failing; the real model selects compact references.
            let paragraph = """
            We reviewed the mobile application and the meeting recording workflow during today's planning discussion.
            People need the recorded audio and transcript to remain available while they review the generated notes.
            The team examined several examples of longer conversations and checked that no source material was lost.
            There was a detailed discussion about making the progress display understandable during a slow operation.
            The display should include elapsed time, an approximate remaining time, and the current progress percentage.
            We decided to show the same progress information in the application and on the phone's lock screen.
            We also reviewed the cancellation behavior and the way saved progress is restored after an interruption.
            The next test should verify that every quote still points to the exact original transcript and sample range.
            No owner or deadline was assigned for that test, and the meeting did not settle a release date.
            The group agreed that the original meeting notes and transcript must remain unchanged during generation.
            """
            XCTAssertGreaterThan(paragraph.utf8.count, 1_024)
            let longID = UUID()
            let longerSource = GroundedSummarySource(meetingID: longID, segments: (0..<4).map { index in
                .init(id: "four-minute-\(index)", startSample: Int64(index) * 960_000,
                      endSample: Int64(index + 1) * 960_000, text: paragraph)
            }, originalManualNotes: "Original four-minute test notes.")
            let longerCalls = ActualPipelineCallCounter()
            let longerPipeline = SummaryPipeline(modelRevision: revision,
                tokenizer: { try await runtime.promptTokenCount(prompt: $0) },
                generator: { prompt, schema, maximum in
                    XCTAssertLessThanOrEqual(maximum, 256, "Long speech must use a compact response from the first call")
                    let output = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum)
                    await longerCalls.generated(output)
                    return output
                })
            let longer = try await longerPipeline.summarize(selectedMeetingID: longID, source: longerSource)
            XCTAssertFalse(longer.summaryPoints.isEmpty)
            try assertAllQuotesAndProvenance(longer, source: longerSource, revision: revision)
            XCTAssertTrue(longer.actions.allSatisfy { $0.owner == nil && $0.due == nil })
            let longerObserved = await longerCalls.snapshot()
            XCTAssertGreaterThan(longerObserved.generated, 0)
            // Real cross-section context and final selection, using the same
            // already hash-verified model. Scale is covered separately by the
            // full two-hour boundary test, not inferred from this short case.
            let relatedID = UUID()
            let background = Array(repeating: paragraph, count: 4).joined(separator: " ")
            let related = GroundedSummarySource(meetingID: relatedID, segments: [
                .init(id: "opening-decision", startSample: 0, endSample: 960_000,
                      text: "Maya: We decided to launch Project Alpha on Monday. " + background),
                .init(id: "security-update", startSample: 960_000, endSample: 1_920_000,
                      text: "Leo: I will finish the Project Alpha security review by Thursday. " + background),
                .init(id: "revised-decision", startSample: 1_920_000, endSample: 2_880_000,
                      text: "We changed the Project Alpha launch from Monday to Friday. " + background)
            ], originalManualNotes: "Focus on Project Alpha's launch date and security review. Keep any changes visible.")
            let relatedCalls = ActualPipelineCallCounter()
            let relatedPipeline = SummaryPipeline(modelRevision: revision,
                tokenizer: { try await runtime.promptTokenCount(prompt: $0) },
                generator: { prompt, schema, maximum in
                    if prompt.contains("MEETING_CONTEXT_JSON:\n[{") { await relatedCalls.usedContext() }
                    let json = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximum)
                    await relatedCalls.generated(json)
                    return json
                }, meetingContextEnabled: true)
            let relatedSummary = try await relatedPipeline.summarize(selectedMeetingID: relatedID, source: related)
            let contextCalls = await relatedCalls.contextCount()
            XCTAssertGreaterThan(contextCalls, 0, "A later native request must receive the validated running brief")
            XCTAssertFalse(relatedSummary.summaryPoints.isEmpty)
            try assertAllQuotesAndProvenance(relatedSummary, source: related, revision: revision)
            let observed = await calls.snapshot()
            XCTAssertGreaterThan(observed.tokenized, 0)
            XCTAssertGreaterThanOrEqual(observed.generated, 2,
                                        "Both fixtures require actual model generation, not decoder-only success")
            if (testRun?.failureCount ?? 0) > failuresBefore { await printFailureDiagnostics(calls) }
            await runtime.unload()
        } catch {
            await printFailureDiagnostics(calls)
            await runtime.unload()
            throw error
        }
    }

    private func printFailureDiagnostics(_ calls: ActualPipelineCallCounter) async {
        // This fixed, non-sensitive synthetic corpus is the only permitted
        // source here. Never add production prompts, file paths or user text.
        let outputs = await calls.failureOutputs()
        for (index, json) in outputs.enumerated() {
            print("SYNTHETIC_SUMMARY_MAP_JSON[\(index)] (maximum 4096 characters): \(json)")
        }
    }

    private func assertAllQuotesAndProvenance(_ output: GroundedSummary, source: GroundedSummarySource,
                                              revision: String) throws {
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
            $0.modelRevision == revision && $0.promptVersion == SummaryPipeline.currentPromptVersion && $0.mapIndex >= 0
        })
    }
}

private actor ActualPipelineCallCounter {
    private var tokenizedCount = 0
    private var generatedCount = 0
    private var outputs: [String] = []
    private var contexts = 0
    func tokenized() { tokenizedCount += 1 }
    func generated(_ json: String) {
        generatedCount += 1
        if outputs.count < 4 { outputs.append(String(json.prefix(4_096))) }
    }
    func failureOutputs() -> [String] { outputs }
    func usedContext() { contexts += 1 }
    func contextCount() -> Int { contexts }
    func snapshot() -> (tokenized: Int, generated: Int) { (tokenizedCount, generatedCount) }
}
