import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class SummaryPipelineTests: XCTestCase {
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
                  case .object(let fields) = actionType else { return XCTFail("Missing bounded nested action schema") }
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
