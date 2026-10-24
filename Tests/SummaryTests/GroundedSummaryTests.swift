import Foundation
import XCTest
@testable import LocalMinutesSummary

/// Only the untrusted generated-JSON boundary is supplied as a fixture. These
/// tests exercise a pure extractive validator/merger, never stand in for a model.
final class GroundedSummaryTests: XCTestCase {
    func testExtractiveSummaryDecisionsAndNullableActionsRetainSourceAndManualTextExactly() throws {
        let h = GroundedFixture()
        let sourceBefore = h.source
        let summary = try h.decode(h.validJSON())
        XCTAssertEqual(summary.meetingID, h.meetingID)
        XCTAssertEqual(summary.summaryPoints.count, 1)
        XCTAssertEqual(summary.decisions.count, 1)
        XCTAssertEqual(summary.actions.count, 2)
        let point = try XCTUnwrap(summary.summaryPoints.first)
        XCTAssertEqual(Array(point.text.utf8), Array(h.unicode.text.utf8))
        XCTAssertEqual(point.evidence, [h.evidence(h.unicode)])
        XCTAssertEqual(point.provenance, [h.provenance])
        XCTAssertEqual(summary.decisions.first?.text, h.decision.text)
        let known = try XCTUnwrap(summary.actions.first)
        XCTAssertEqual(known.task, "I will write the installation guide by Thursday.")
        XCTAssertEqual(known.owner, "Leo")
        XCTAssertEqual(known.due, "Thursday")
        XCTAssertEqual(known.evidence, [h.evidence(h.commitment)])
        XCTAssertEqual(known.provenance, [h.provenance])
        let uncertain = try XCTUnwrap(summary.actions.last)
        XCTAssertNil(uncertain.owner)
        XCTAssertNil(uncertain.due)
        XCTAssertEqual(uncertain.task, h.unknown.text)
        XCTAssertEqual(h.source, sourceBefore, "Generated content is separate from original notes/transcript")
        XCTAssertEqual(Array(h.source.originalManualNotes.utf8), Array(h.manualNotes.utf8))
    }

    func testDecoderRejectsOtherMeetingAndUnknownSourceIDsBeforePublishingContent() throws {
        let h = GroundedFixture()
        var otherMeeting = h.validJSON()
        otherMeeting["meeting_id"] = UUID().uuidString
        expect(.meetingMismatch) { try h.decode(otherMeeting) }
        let wrongSource = GroundedSummarySource(meetingID: UUID(), segments: h.source.segments,
                                               originalManualNotes: h.manualNotes)
        expect(.meetingMismatch) { try h.decode(h.validJSON(), source: wrongSource) }
        var unknown = h.validJSON()
        unknown["summary_points"] = [h.point(h.unicode.text, citation: [
            "source_id": "not-in-selected-meeting", "start_sample": h.unicode.startSample,
            "end_sample": h.unicode.endSample, "quote": h.unicode.text
        ])]
        expect(.unknownSourceID) { try h.decode(unknown) }
    }

    func testEvidenceRangesAndVerbatimUTF8QuotesCannotCrossOrNormalizeSources() throws {
        let h = GroundedFixture()
        var crossRange = h.validJSON()
        var citation = h.citation(h.decision)
        citation["end_sample"] = h.commitment.endSample
        crossRange["summary_points"] = [h.point(h.decision.text, citation: citation)]
        expect(.invalidRange) { try h.decode(crossRange) }
        var borrowed = h.validJSON()
        var borrowedCitation = h.citation(h.decision)
        borrowedCitation["quote"] = h.commitment.text
        borrowed["summary_points"] = [h.point(h.commitment.text, citation: borrowedCitation)]
        expect(.unsupportedQuote) { try h.decode(borrowed) }
        var normalized = h.validJSON()
        let altered = h.unicode.text.replacingOccurrences(of: "e\u{301}", with: "é")
        var alteredCitation = h.citation(h.unicode)
        alteredCitation["quote"] = altered
        normalized["summary_points"] = [h.point(altered, citation: alteredCitation)]
        expect(.unsupportedQuote) { try h.decode(normalized) }
    }

    func testPresentNamesAndDatesDoNotSupportAnotherActionsOwnerDueOrParaphrase() throws {
        let h = GroundedFixture()
        var mentionedName = h.validJSON()
        mentionedName["actions"] = [h.action(task: "I will send Maya the notes by Thursday.", owner: "Maya",
                                             due: "Thursday", segment: h.mentions)]
        expect(.unsupportedClaim) { try h.decode(mentionedName) }
        var borrowedDate = h.validJSON()
        borrowedDate["actions"] = [h.action(task: "I will write the installation guide by Thursday.", owner: "Leo",
                                            due: "Friday", segment: h.commitment)]
        expect(.unsupportedClaim) { try h.decode(borrowedDate) }
        var inventedOwner = h.validJSON()
        inventedOwner["actions"] = [h.action(task: h.unknown.text, owner: "Leo", due: nil, segment: h.unknown)]
        expect(.unsupportedClaim) { try h.decode(inventedOwner) }
        var paraphrase = h.validJSON()
        paraphrase["summary_points"] = [h.point("The team approved every launch requirement.", citation: h.citation(h.decision))]
        expect(.unsupportedClaim) { try h.decode(paraphrase) }
        var inventedTask = h.validJSON()
        inventedTask["actions"] = [h.action(task: "Prepare the entire onboarding program", owner: "Leo",
                                            due: "Thursday", segment: h.commitment)]
        expect(.unsupportedClaim) { try h.decode(inventedTask) }
    }

    func testInvalidJSONDuplicateItemsOverflowAndExplicitLimitsCannotPublishPartialData() throws {
        let h = GroundedFixture()
        expect(.invalidJSON) { try h.decodeBytes(Data("Original non-JSON generation".utf8)) }
        var duplicates = h.validJSON()
        let point = h.point(h.unicode.text, citation: h.citation(h.unicode))
        duplicates["summary_points"] = [point, point]
        expect(.duplicateItem) { try h.decode(duplicates) }
        var duplicateEvidence = h.validJSON()
        duplicateEvidence["summary_points"] = [["text": h.unicode.text,
                                                  "evidence": [h.citation(h.unicode), h.citation(h.unicode)]]]
        expect(.duplicateItem) { try h.decode(duplicateEvidence) }
        let invalidSource = GroundedSummarySource(meetingID: h.meetingID,
            segments: h.source.segments + [h.unicode], originalManualNotes: h.manualNotes)
        expect(.invalidSource) { try h.decode(h.validJSON(), source: invalidSource) }
        let overflow = """
        {"meeting_id":"\(h.meetingID.uuidString)","summary_points":[{"text":"Original","evidence":[{"source_id":"decision","start_sample":0,"end_sample":9223372036854775808,"quote":"Original"}]}],"decisions":[],"actions":[]}
        """
        expect(.invalidJSON) { try h.decodeBytes(Data(overflow.utf8)) }
        let encoded = try JSONSerialization.data(withJSONObject: h.validJSON(), options: [.sortedKeys])
        expect(.limitExceeded) { try h.decodeBytes(encoded, limits: .init(maximumJSONBytes: encoded.count - 1)) }
        expect(.limitExceeded) { try h.decode(h.validJSON(), limits: .init(maximumItems: 1)) }
        expect(.limitExceeded) { try h.decode(h.validJSON(), limits: .init(maximumQuoteUTF8Bytes: 4)) }
        let invalidProvenance = SummaryGenerationProvenance(modelRevision: "unverified", promptVersion: "", mapIndex: -1)
        expect(.invalidProvenance) { try h.decode(h.validJSON(), provenance: invalidProvenance) }
    }

    func testMergeIsOrderIndependentAndRetainsEveryEvidenceAndProvenanceWithoutFillingUnknowns() throws {
        let h = GroundedFixture()
        let p0 = h.provenance
        let p1 = SummaryGenerationProvenance(modelRevision: p0.modelRevision, promptVersion: p0.promptVersion, mapIndex: 1)
        let first = GroundedSummaryPoint(text: h.echo0.text, evidence: [h.evidence(h.echo0)], provenance: [p0])
        let repeated = GroundedSummaryPoint(text: h.echo1.text, evidence: [h.evidence(h.echo1)], provenance: [p1])
        let decision = GroundedSummaryPoint(text: h.decision.text, evidence: [h.evidence(h.decision)], provenance: [p0])
        let uncertain = GroundedSummaryAction(task: h.unknown.text, owner: nil, due: nil,
            evidence: [h.evidence(h.unknown)], provenance: [p0])
        let known = GroundedSummaryAction(task: "I will write the installation guide by Thursday.", owner: "Leo", due: "Thursday",
            evidence: [h.evidence(h.commitment)], provenance: [p1])
        let map0 = GroundedSummary(meetingID: h.meetingID, summaryPoints: [first], decisions: [decision], actions: [uncertain])
        let map1 = GroundedSummary(meetingID: h.meetingID, summaryPoints: [repeated], decisions: [], actions: [known])
        let forward = try GroundedSummaryMerger.merge([map0, map1], selectedMeetingID: h.meetingID, source: h.source)
        let reversed = try GroundedSummaryMerger.merge([map1, map0], selectedMeetingID: h.meetingID, source: h.source)
        XCTAssertEqual(forward, reversed)
        XCTAssertEqual(forward.summaryPoints.count, 1)
        XCTAssertEqual(forward.summaryPoints.first?.evidence, [h.evidence(h.echo0), h.evidence(h.echo1)])
        XCTAssertEqual(forward.summaryPoints.first?.provenance, [p0, p1])
        XCTAssertEqual(forward.decisions, [decision])
        XCTAssertEqual(forward.actions, [known, uncertain], "Order by actual source position, retaining nullable fields")
        XCTAssertNil(forward.actions.last?.owner)
        XCTAssertNil(forward.actions.last?.due)
        let missingOwner = GroundedSummaryAction(task: known.task, owner: nil, due: nil, evidence: known.evidence, provenance: [p0])
        let conflicting = GroundedSummary(meetingID: h.meetingID, summaryPoints: [], decisions: [], actions: [missingOwner])
        expect(.conflictingClaim) {
            try GroundedSummaryMerger.merge([map1, conflicting], selectedMeetingID: h.meetingID, source: h.source)
        }
        let wrongMeeting = GroundedSummary(meetingID: UUID(), summaryPoints: [], decisions: [], actions: [])
        expect(.meetingMismatch) {
            try GroundedSummaryMerger.merge([map0, wrongMeeting], selectedMeetingID: h.meetingID, source: h.source)
        }
        XCTAssertEqual(map0.actions, [uncertain], "Merge must not mutate its original map output")
    }

    private func expect(_ expected: GroundedSummaryError, file: StaticString = #filePath,
                        line: UInt = #line, _ operation: () throws -> GroundedSummary) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? GroundedSummaryError, expected, file: file, line: line)
        }
    }
}

private struct GroundedFixture {
    let meetingID = UUID(uuidString: "20000000-0000-0000-0000-000000000018")!
    let manualNotes = "Original manual note — e\u{301} ≠ é 📝\nKeep this user-authored text."
    let provenance = SummaryGenerationProvenance(modelRevision: String(repeating: "a", count: 40),
                                                  promptVersion: "extractive-v1", mapIndex: 0)
    let decision = SummaryEvidenceSegment(id: "decision", startSample: 0, endSample: 16_000,
        text: "Maya: We decided to ship the prototype on Friday.")
    let commitment = SummaryEvidenceSegment(id: "commitment", startSample: 16_000, endSample: 32_000,
        text: "Leo: I will write the installation guide by Thursday.")
    let unknown = SummaryEvidenceSegment(id: "unknown", startSample: 32_000, endSample: 48_000,
        text: "The deployment checklist needs work. Nobody has accepted it, and its deadline is unknown.")
    let unicode = SummaryEvidenceSegment(id: "unicode", startSample: 48_000, endSample: 64_000,
        text: "Résumé — e\u{301} ≠ é; चर्चा 中文 📝")
    let mentions = SummaryEvidenceSegment(id: "mentions", startSample: 64_000, endSample: 80_000,
        text: "Leo: I will send Maya the notes by Thursday.")
    let echo0 = SummaryEvidenceSegment(id: "echo-0", startSample: 80_000, endSample: 96_000,
        text: "Original shared extractive point.")
    let echo1 = SummaryEvidenceSegment(id: "echo-1", startSample: 96_000, endSample: 112_000,
        text: "Original shared extractive point.")
    var source: GroundedSummarySource {
        .init(meetingID: meetingID, segments: [decision, commitment, unknown, unicode, mentions, echo0, echo1],
              originalManualNotes: manualNotes)
    }
    func evidence(_ segment: SummaryEvidenceSegment) -> GroundedSummaryEvidence {
        .init(sourceID: segment.id, startSample: segment.startSample, endSample: segment.endSample, quote: segment.text)
    }
    func citation(_ segment: SummaryEvidenceSegment) -> [String: Any] {
        ["source_id": segment.id, "start_sample": segment.startSample, "end_sample": segment.endSample, "quote": segment.text]
    }
    func point(_ text: String, citation: [String: Any]) -> [String: Any] { ["text": text, "evidence": [citation]] }
    func action(task: String, owner: String?, due: String?, segment: SummaryEvidenceSegment) -> [String: Any] {
        ["task": task, "owner": owner.map { $0 as Any } ?? NSNull(),
         "due": due.map { $0 as Any } ?? NSNull(), "evidence": [citation(segment)]]
    }
    func validJSON() -> [String: Any] {
        ["meeting_id": meetingID.uuidString, "summary_points": [point(unicode.text, citation: citation(unicode))],
         "decisions": [point(decision.text, citation: citation(decision))],
         "actions": [action(task: "I will write the installation guide by Thursday.", owner: "Leo", due: "Thursday", segment: commitment),
                     action(task: unknown.text, owner: nil, due: nil, segment: unknown)]]
    }
    func decode(_ json: [String: Any], source: GroundedSummarySource? = nil,
                provenance: SummaryGenerationProvenance? = nil, limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        try decodeBytes(JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
                        source: source, provenance: provenance, limits: limits)
    }
    func decodeBytes(_ data: Data, source: GroundedSummarySource? = nil,
                     provenance: SummaryGenerationProvenance? = nil, limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        try GroundedSummaryDecoder.decode(data, selectedMeetingID: meetingID, source: source ?? self.source,
                                          provenance: provenance ?? self.provenance, limits: limits)
    }
}
