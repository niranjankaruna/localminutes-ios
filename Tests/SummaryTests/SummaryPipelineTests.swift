import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class SummaryPipelineTests: XCTestCase {
    func testMapGrammarBindsEachSourceRangeQuoteAndClaimAsOneCorrelatedChoice() async throws {
        let meetingID = UUID(uuidString: "30000000-0000-0000-0000-000000000020")!
        let segments = [
            SummaryEvidenceSegment(id: "generic-source-first", startSample: 8_000, endSample: 24_000,
                text: "The cafe\u{301} workshop keeps its original quote."),
            SummaryEvidenceSegment(id: "generic-source-second", startSample: 32_000, endSample: 64_000,
                text: "Ren: I will review the checklist by Friday.")
        ]
        let source = GroundedSummarySource(meetingID: meetingID, segments: segments, originalManualNotes: "Separate original note.")
        func citation(_ segment: SummaryEvidenceSegment) -> [String: Any] {
            ["source_id": segment.id, "start_sample": segment.startSample,
             "end_sample": segment.endSample, "quote": segment.text]
        }
        let reply: [String: Any] = [
            "meeting_id": meetingID.uuidString,
            "summary_points": [["evidence": [citation(segments[0])], "text": segments[0].text]],
            "decisions": [],
            "actions": [["evidence": [citation(segments[1])], "task": segments[1].text,
                         "owner": "Ren", "due": "Friday"]]
        ]
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
        let boundary = PipelineGenerationBoundary(replies: [raw])
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            tokenizer: { _ in 10 }, generator: { prompt, schema, maximum in
                try await boundary.generate(prompt, schema: schema, maximumTokens: maximum)
            })
        let result = try await pipeline.summarize(selectedMeetingID: meetingID, source: source)
        let requests = await boundary.requests
        let schema = try XCTUnwrap(requests.first?.schema)
        _ = try schema.grammar()
        for category in ["summary_points", "decisions", "actions"] {
            let field = try XCTUnwrap(schema.fields.first { $0.name == category })
            guard case .array(let element, let maximumItems) = field.type else {
                XCTFail("The selected category must remain a bounded array"); continue
            }
            XCTAssertEqual(maximumItems, 2)
            guard case .alternatives(let branches) = element else {
                XCTFail("\(category) must choose an entire source/range/quote/claim tuple, not independent field enums")
                continue
            }
            XCTAssertEqual(branches.count, segments.count, "Every source must remain a model-selectable branch")
            var foundSources: Set<Data> = []
            for branch in branches {
                guard case .object(let itemFields) = branch else { XCTFail("Each tuple is one object"); continue }
                let claim = try XCTUnwrap(itemFields.first { $0.name == (category == "actions" ? "task" : "text") })
                guard case .stringEnumeration(let texts) = claim.type else { XCTFail("Claim must be an exact singleton"); continue }
                XCTAssertEqual(texts.count, 1)
                let text = try XCTUnwrap(texts.first)
                let expected = try XCTUnwrap(segments.first { Data($0.text.utf8) == Data(text.utf8) })
                foundSources.insert(Data(expected.id.utf8))
                let evidence = try XCTUnwrap(itemFields.first { $0.name == "evidence" })
                guard case .array(let citationType, let count) = evidence.type,
                      case .object(let citationFields) = citationType else {
                    XCTFail("Each item must bind one exact citation object"); continue
                }
                XCTAssertEqual(count, 1)
                XCTAssertEqual(citationFields.first { $0.name == "source_id" }?.type, .stringEnumeration([expected.id]))
                XCTAssertEqual(citationFields.first { $0.name == "start_sample" }?.type, .integerEnumeration([expected.startSample]))
                XCTAssertEqual(citationFields.first { $0.name == "end_sample" }?.type, .integerEnumeration([expected.endSample]))
                guard let quote = citationFields.first(where: { $0.name == "quote" }),
                      case .stringEnumeration(let quotes) = quote.type else {
                    XCTFail("Quote must be bound to the same exact claim"); continue
                }
                XCTAssertEqual(quotes.map { Data($0.utf8) }, [Data(text.utf8)],
                    "A different allowed sentence cannot be paired with this claim")
                if category == "actions" {
                    for attribute in ["owner", "due"] {
                        XCTAssertEqual(itemFields.first { $0.name == attribute }?.type, .nullable(.string),
                            "Correlation must not hardcode assignments or infer unknown attributes")
                    }
                }
            }
            XCTAssertEqual(foundSources, Set(segments.map { Data($0.id.utf8) }))
        }
        XCTAssertEqual(result.actions.first?.evidence.first?.sourceID, segments[1].id)
        XCTAssertEqual(result.actions.first?.evidence.first?.startSample, segments[1].startSample)
        XCTAssertEqual(source.segments, segments)
    }

    func testMultiSentenceSourceGrammarPermitsExactSentenceChoicesWithoutForcingParagraphOwnership() async throws {
        let meetingID = UUID(uuidString: "30000000-0000-0000-0000-000000000019")!
        let sentences = [
            "Ari: I will review the cafe\u{301} checklist by Wednesday.",
            "The supporting note preserves e\u{301} and 📝 exactly.",
            "No other owner or deadline was assigned."
        ]
        let paragraph = sentences.joined(separator: " ")
        let segment = SummaryEvidenceSegment(id: "generic-three-sentence-source",
            startSample: 32_000, endSample: 80_000, text: paragraph)
        let source = GroundedSummarySource(meetingID: meetingID, segments: [segment],
            originalManualNotes: "Original separate manual note.")
        func citation(_ quote: String) -> [String: Any] {
            ["source_id": segment.id, "start_sample": segment.startSample,
             "end_sample": segment.endSample, "quote": quote]
        }
        // Supply only the untrusted generation boundary. The schema must permit
        // this valid choice; the real decoder still validates every returned field.
        let reply: [String: Any] = [
            "meeting_id": meetingID.uuidString,
            "summary_points": [["evidence": [citation(sentences[1])], "text": sentences[1]]],
            "decisions": [],
            "actions": [["evidence": [citation(sentences[0])], "task": sentences[0],
                         "owner": "Ari", "due": "Wednesday"]]
        ]
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
        let boundary = PipelineGenerationBoundary(replies: [raw])
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            tokenizer: { _ in 10 }, generator: { prompt, schema, maximum in
                try await boundary.generate(prompt, schema: schema, maximumTokens: maximum)
            })
        let output = try await pipeline.summarize(selectedMeetingID: meetingID, source: source)
        let requests = await boundary.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(request.prompt.contains(segment.id))
        XCTAssertTrue(request.prompt.contains("No other owner or deadline was assigned."),
            "Sentence choices must not discard the later source material from model input")
        _ = try request.schema.grammar()

        func fields(inArray name: String, fields: [StructuredJSONField]) throws -> [StructuredJSONField] {
            let matching = fields.filter { $0.name == name }
            XCTAssertFalse(matching.isEmpty)
            var result: [StructuredJSONField] = []
            for field in matching {
                guard case .array(let element, let maximumItems) = field.type else {
                    XCTFail("Expected a bounded object array for \(name)"); continue
                }
                XCTAssertTrue((1...128).contains(maximumItems))
                let objects: [StructuredJSONType]
                if case .alternatives(let choices) = element { objects = choices } else { objects = [element] }
                for object in objects {
                    guard case .object(let itemFields) = object else {
                        XCTFail("Every array choice must remain an object"); continue
                    }
                    result.append(contentsOf: itemFields)
                }
            }
            return result
        }
        func exactChoices(_ name: String, fields: [StructuredJSONField]) throws {
            let matching = fields.filter { $0.name == name }
            XCTAssertFalse(matching.isEmpty)
            var values: [String] = []
            for field in matching {
                guard case .stringEnumeration(let choices) = field.type else {
                    XCTFail("Short source sentences must retain a bounded extractive choice set"); continue
                }
                values.append(contentsOf: choices)
            }
            XCTAssertEqual(values.map { Data($0.utf8) }, sentences.map { Data($0.utf8) },
                "The grammar must offer every exact sentence instead of forcing the full paragraph")
            XCTAssertFalse(values.contains(paragraph),
                "A multi-sentence task cannot inherit the first commitment's owner")
            let normalized = sentences[1].precomposedStringWithCanonicalMapping
            XCTAssertNotEqual(Data(normalized.utf8), Data(sentences[1].utf8))
            XCTAssertFalse(values.contains { Data($0.utf8) == Data(normalized.utf8) },
                "Candidate extraction must not normalize original Unicode bytes")
        }
        let actions = try fields(inArray: "actions", fields: request.schema.fields)
        try exactChoices("task", fields: actions)
        let evidence = try fields(inArray: "evidence", fields: actions)
        try exactChoices("quote", fields: evidence)
        for category in ["summary_points", "decisions"] {
            let points = try fields(inArray: category, fields: request.schema.fields)
            try exactChoices("text", fields: points)
        }
        for name in ["owner", "due"] {
            let attributes = actions.filter { $0.name == name }
            XCTAssertFalse(attributes.isEmpty)
            for field in attributes {
                XCTAssertEqual(field.type, .nullable(.string),
                    "The grammar must leave model-selected attributes unknown or independently validated")
            }
        }
        XCTAssertEqual(output.actions.first?.task, sentences[0])
        XCTAssertEqual(output.actions.first?.owner, "Ari")
        XCTAssertEqual(output.actions.first?.due, "Wednesday")
        XCTAssertEqual(output.actions.first?.evidence.first?.sourceID, segment.id)
        XCTAssertEqual(output.actions.first?.evidence.first?.startSample, segment.startSample)
        XCTAssertEqual(output.actions.first?.evidence.first?.endSample, segment.endSample)
        XCTAssertEqual(output.summaryPoints.first.map { Data($0.text.utf8) }, Data(sentences[1].utf8))
        XCTAssertEqual(source.segments, [segment])
    }

    func testPipelineMapsEveryChunkAndPublishesOnlyValidatedMergedContentWithProvenance() async throws {
        let h = PipelineFixture()
        let calls = PipelineGenerationBoundary(replies: [try h.response(for: h.first), try h.response(for: h.second)])
        let pipeline = h.pipeline(boundary: calls)
        let original = h.source
        let output = try await pipeline.summarize(selectedMeetingID: h.meetingID, source: h.source)
        let requests = await calls.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.maximumTokens), [1_024, 1_024])
        for request in requests {
            XCTAssertTrue(request.prompt.contains("MANUAL_NOTES_JSON:"))
            let notesStart = try XCTUnwrap(request.prompt.range(of: "MANUAL_NOTES_JSON:\n"))
            let evidenceStart = try XCTUnwrap(request.prompt.range(of: "\n\nEVIDENCE_JSON:\n"))
            XCTAssertLessThanOrEqual(notesStart.upperBound, evidenceStart.lowerBound)
            guard notesStart.upperBound <= evidenceStart.lowerBound else { return }
            let notesPayload = Data(request.prompt[notesStart.upperBound..<evidenceStart.lowerBound].utf8)
            let notes = try XCTUnwrap(try JSONSerialization.jsonObject(with: notesPayload,
                                                                       options: [.fragmentsAllowed]) as? String)
            XCTAssertEqual(Array(notes.utf8), Array(h.notes.utf8))
            XCTAssertEqual(request.schema.fields.map(\.name), ["meeting_id", "summary_points", "decisions", "actions"])
            guard let actionField = request.schema.fields.first(where: { $0.name == "actions" }),
                  case .array(let actionType, let count) = actionField.type,
                  case .alternatives(let choices) = actionType,
                  choices.count == 1, case .object(let fields) = choices[0] else {
                return XCTFail("Missing bounded correlated action schema")
            }
            XCTAssertTrue((1...128).contains(count))
            guard let owner = fields.first(where: { $0.name == "owner" }),
                  case .nullable(.string) = owner.type else { return XCTFail("Unknown owner must permit actual JSON null") }
            guard let due = fields.first(where: { $0.name == "due" }),
                  case .nullable(.string) = due.type else { return XCTFail("Unknown deadline must permit actual JSON null") }
        }
        XCTAssertEqual(output.summaryPoints.count, 2)
        XCTAssertEqual(output.summaryPoints.flatMap(\.evidence).map(\.sourceID), [h.first.id, h.second.id])
        XCTAssertEqual(output.summaryPoints.flatMap(\.provenance).map(\.mapIndex), [0, 1])
        XCTAssertTrue(output.summaryPoints.flatMap(\.provenance).allSatisfy {
            $0.modelRevision == h.revision && $0.promptVersion == "grounded-map-v1"
        })
        let snapshot = await pipeline.snapshot()
        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertEqual(snapshot.meetingID, h.meetingID)
        XCTAssertEqual(snapshot.result, output)
        XCTAssertEqual(h.source, original, "Generation must not replace notes or original transcript")
    }

    func testLaterInvalidGenerationRejectsCrossChunkEvidenceAndPublishesNoPartialSummary() async throws {
        let h = PipelineFixture()
        let validFirst = try h.response(for: h.first)
        let variants: [(String, GroundedSummaryError)] = [
            (try h.response(for: h.first), .unknownSourceID), // wrong chunk, although same meeting
            (try h.response(for: h.second, meetingID: UUID()), .meetingMismatch),
            ("not generated JSON", .invalidJSON),
            (try h.response(for: h.second, pointText: "A fabricated unsupported conclusion."), .unsupportedClaim)
        ]
        for (invalid, expected) in variants {
            let boundary = PipelineGenerationBoundary(replies: [validFirst, invalid])
            let pipeline = h.pipeline(boundary: boundary)
            do { _ = try await pipeline.summarize(selectedMeetingID: h.meetingID, source: h.source); XCTFail("Invalid map was published") }
            catch { XCTAssertEqual(error as? GroundedSummaryError, expected) }
            let snapshot = await pipeline.snapshot()
            XCTAssertEqual(snapshot.phase, .failed)
            XCTAssertNil(snapshot.result)
            XCTAssertEqual(snapshot.meetingID, h.meetingID)
        }
    }

    func testCancellationAfterOneMapPublishesNothingAndReplacementCannotInheritOldEvidence() async throws {
        let h = PipelineFixture()
        let boundary = PipelineGenerationBoundary(replies: [try h.response(for: h.first)], holdAfterFirst: true)
        let pipeline = h.pipeline(boundary: boundary)
        let task = Task { try await pipeline.summarize(selectedMeetingID: h.meetingID, source: h.source) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !(await boundary.held), clock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let held = await boundary.held
        XCTAssertTrue(held)
        let during = await pipeline.snapshot()
        XCTAssertEqual(during.phase, .running)
        XCTAssertNil(during.result)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled map/reduce published a result") }
        catch is CancellationError { }
        catch { XCTFail("Expected explicit cancellation, got \(error)") }
        let cancelled = await pipeline.snapshot()
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertNil(cancelled.result)

        let replacementID = UUID()
        let replacementSegment = SummaryEvidenceSegment(id: "replacement-source", startSample: 0, endSample: 16_000,
            text: "Original replacement evidence stays in its own meeting.")
        let replacement = GroundedSummarySource(meetingID: replacementID, segments: [replacementSegment],
                                                originalManualNotes: "Original replacement manual note")
        await boundary.replace(replies: [try h.response(for: replacementSegment, meetingID: replacementID)])
        let output = try await pipeline.summarize(selectedMeetingID: replacementID, source: replacement)
        XCTAssertEqual(output.meetingID, replacementID)
        XCTAssertEqual(output.summaryPoints.flatMap(\.evidence).map(\.sourceID), [replacementSegment.id])
        XCTAssertTrue(output.summaryPoints.flatMap(\.provenance).allSatisfy { $0.mapIndex == 0 })
        let final = await pipeline.snapshot()
        XCTAssertEqual(final.result, output)
        XCTAssertEqual(h.source.originalManualNotes, h.notes)
    }
}

private actor PipelineGenerationBoundary {
    struct Request: Sendable { let prompt: String; let schema: StructuredJSONSchema; let maximumTokens: Int }
    private var replies: [String]
    private var holdAfterFirst: Bool
    private(set) var requests: [Request] = []
    private(set) var held = false
    init(replies: [String], holdAfterFirst: Bool = false) { self.replies = replies; self.holdAfterFirst = holdAfterFirst }
    func generate(_ prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        requests.append(.init(prompt: prompt, schema: schema, maximumTokens: maximumTokens))
        if holdAfterFirst && requests.count > 1 {
            held = true
            try await Task.sleep(for: .seconds(30))
        }
        guard requests.count <= replies.count else { throw PipelineFixtureError.missingReply }
        return replies[requests.count - 1]
    }
    func replace(replies: [String]) { self.replies = replies; holdAfterFirst = false; held = false; requests = [] }
}

private enum PipelineFixtureError: Error { case invalidPrompt, missingReply }

private struct PipelineFixture {
    let meetingID = UUID(uuidString: "30000000-0000-0000-0000-000000000018")!
    let revision = String(repeating: "a", count: 40) // pure metadata fixture, not inference
    let notes = "Original note — Café 📝; do not overwrite user content."
    let first = SummaryEvidenceSegment(id: "first", startSample: 0, endSample: 16_000,
        text: "First original complete extractive sentence.")
    let second = SummaryEvidenceSegment(id: "second", startSample: 32_000, endSample: 48_000,
        text: "Second original complete extractive sentence after a source gap.")
    var source: GroundedSummarySource { .init(meetingID: meetingID, segments: [first, second], originalManualNotes: notes) }
    func pipeline(boundary: PipelineGenerationBoundary) -> SummaryPipeline {
        SummaryPipeline(modelRevision: revision, tokenizer: { prompt in
            guard let marker = prompt.range(of: "\n\nEVIDENCE_JSON:\n"),
                  let json = String(prompt[marker.upperBound...]).data(using: .utf8),
                  let segments = try JSONSerialization.jsonObject(with: json) as? [[String: Any]] else {
                throw PipelineFixtureError.invalidPrompt
            }
            return segments.count == 1 ? 3_000 : 3_072
        }, generator: { prompt, schema, maximum in
            try await boundary.generate(prompt, schema: schema, maximumTokens: maximum)
        })
    }
    func response(for source: SummaryEvidenceSegment, meetingID: UUID? = nil, pointText: String? = nil) throws -> String {
        let object: [String: Any] = ["meeting_id": (meetingID ?? self.meetingID).uuidString,
            "summary_points": [["text": pointText ?? source.text, "evidence": [["source_id": source.id,
                "start_sample": source.startSample, "end_sample": source.endSample, "quote": source.text]]]],
            "decisions": [], "actions": []]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
