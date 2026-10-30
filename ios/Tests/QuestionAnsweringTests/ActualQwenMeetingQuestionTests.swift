import CryptoKit
import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesQuestionAnswering

/// Mandatory actual CPU model integration after activation. No skip, network
/// request, fabricated model response, or byte-count substitute for tokenizer.
@MainActor
final class ActualQwenMeetingQuestionTests: XCTestCase {
    func testActualPinnedQwenAnswersSelectedBudgetAndPreservesUnknownOwnerDespiteOtherMeetingAnswer() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_QWEN_MODEL_PATH"],
            "The dedicated real-model job must supply the verified pinned Qwen artifact; absence fails")
        let modelURL = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.int64Value
        XCTAssertEqual(size, 1_117_320_736)
        guard size == 1_117_320_736 else { throw LocalSummaryRuntimeError.invalidModel }
        let input = try FileHandle(forReadingFrom: modelURL)
        var hasher = SHA256()
        do {
            while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty { hasher.update(data: bytes) }
            try input.close()
        } catch { try? input.close(); throw error }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let expectedDigest = "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        XCTAssertEqual(digest, expectedDigest)
        guard digest == expectedDigest else { throw LocalSummaryRuntimeError.invalidModel }
        let revision = "91cad51170dc346986eccefdc2dd33a9da36ead9"
        let runtime = try LocalSummaryRuntime(modelURL: modelURL, contextSize: 4_096, threads: 4)
        do {
            try await withQuestionFixture { fixture in
                let probe = QuestionGenerationProbe()
                let answerer = MeetingQuestionAnswerer(store: fixture.store, modelRevision: revision,
                    tokenCounter: { try await runtime.promptTokenCount(prompt: $0) }, generator: { request in
                        let json = try await runtime.generateJSON(prompt: request.prompt,
                            schema: request.schema, maximumTokens: request.maximumOutputTokens)
                        await probe.record(request, output: json)
                        return json
                    })
                let supported = try await answerer.answer(meetingID: fixture.selected,
                    question: "What is the launch budget?")
                XCTAssertEqual(supported.status, .supportedQuote)
                XCTAssertEqual(supported.meetingID, fixture.selected)
                XCTAssertEqual(supported.modelRevision, revision)
                XCTAssertEqual(supported.evidence.count, 1)
                if let evidence = supported.evidence.first {
                    XCTAssertEqual(evidence.source, fixture.selectedSegments[0])
                    XCTAssertTrue(evidence.quote.contains("42000"))
                    XCTAssertTrue(evidence.quote.lowercased().contains("credits"))
                    XCTAssertFalse(evidence.quote.contains("1800"))
                    XCTAssertFalse(evidence.quote.contains("999999"))
                    XCTAssertNotNil(Data(evidence.source.text.utf8).range(of: Data(evidence.quote.utf8)))
                }
                let unknown = try await answerer.answer(meetingID: fixture.selected,
                    question: "Who owns the launch budget?")
                XCTAssertEqual(unknown.status, .insufficientEvidence,
                    "The selected meeting explicitly leaves the owner undecided; Alex belongs to another meeting")
                XCTAssertTrue(unknown.evidence.isEmpty)
                let requests = await probe.requests
                let outputs = await probe.outputs
                XCTAssertEqual(requests.count, 2, "Both semantic observations must execute actual native inference")
                XCTAssertEqual(outputs.count, 2)
                if outputs.count == 2 {
                    let originalAnswer = try JSONDecoder().decode(QuestionWireOutput.self, from: Data(outputs[0].utf8))
                    let originalRefusal = try JSONDecoder().decode(QuestionWireOutput.self, from: Data(outputs[1].utf8))
                    XCTAssertEqual(originalAnswer.status, "supported_quote")
                    XCTAssertEqual(originalAnswer.source_id, questionUUID(10).uuidString)
                    XCTAssertTrue(originalAnswer.quote.contains("42000"))
                    XCTAssertEqual(originalRefusal.status, "insufficient_evidence")
                    XCTAssertEqual(originalRefusal.source_id, "none")
                    XCTAssertEqual(originalRefusal.quote, "")
                }
                for request in requests {
                    XCTAssertTrue(request.evidence.allSatisfy { $0.meetingID == fixture.selected })
                    XCTAssertFalse(request.prompt.contains("OTHER_MEETING_CANARY_7"))
                    XCTAssertFalse(request.prompt.contains("999999"))
                    XCTAssertEqual(request.schema.fields.map(\.name), ["status", "source_id", "quote"])
                    if request.schema.fields.count == 3 {
                        XCTAssertEqual(request.schema.fields[0].type,
                            .stringEnumeration(["supported_quote", "insufficient_evidence"]))
                        XCTAssertEqual(request.schema.fields[2].type, .string,
                            "Model must generate its quote rather than select a fixture's sole answer")
                        if case .stringEnumeration(let ids) = request.schema.fields[1].type {
                            XCTAssertEqual(Set(ids), Set(["none"] + request.evidence.map { $0.id.uuidString }))
                        } else { XCTFail("Native grammar omitted the full supplied source/refusal domain") }
                    }
                    let nativeCount = try await runtime.promptTokenCount(prompt: request.prompt)
                    XCTAssertEqual(request.promptTokenCount, nativeCount)
                    XCTAssertLessThan(nativeCount + request.maximumOutputTokens, 4_096)
                }
                let selected = try await fixture.store.transcript(meetingID: fixture.selected)
                let other = try await fixture.store.transcript(meetingID: fixture.other)
                let note = try await fixture.store.manualNote(meetingID: fixture.selected)
                let otherNote = try await fixture.store.manualNote(meetingID: fixture.other)
                XCTAssertEqual(selected, fixture.selectedSegments); XCTAssertEqual(other, fixture.otherSegments)
                XCTAssertEqual(note, fixture.selectedNote); XCTAssertEqual(otherNote, fixture.otherNote)
            }
            await runtime.unload()
        } catch { await runtime.unload(); throw error }
    }
}
