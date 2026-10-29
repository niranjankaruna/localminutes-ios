#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

/// Real SQLite documents and the actual detail controller's citation parser.
/// No native inference, microphone or audio-playback success is inferred.
@MainActor
final class NativeMeetingCitationNavigationTests: XCTestCase {
    func testParaphrasedNarrativeRetainsOriginalEvidenceAndNavigationIdentity() async throws {
        try await fixture { f in
            let source = f.selectedSegments[1]
            let document = try await f.document(kind: .summary, source: source, start: source.startSample,
                end: source.endSample, narrative: true)
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let citations = try XCTUnwrap(controller.citations[document.id])
            XCTAssertEqual(citations.count, 1, "Overview and bullet references to the same original span are deduplicated")
            let citation = try XCTUnwrap(citations.first)
            XCTAssertEqual(citation.quote, source.text)
            XCTAssertNotEqual(document.editedText, citation.quote)
            let target = try XCTUnwrap(controller.citationNavigationTarget(documentID: document.id, citationID: citation.id))
            XCTAssertEqual(target.segmentID, source.id)
            XCTAssertEqual(target.startSample, source.startSample)
            XCTAssertEqual(target.endSample, source.endSample)
        }
    }

    func testNarrativeEvidenceCannotInventAWordAlignmentInsideAnOriginalSegment() async throws {
        try await fixture { f in
            let document = try await f.document(kind: .summary, source: f.selectedSegments[1],
                start: 40_000, end: 56_000, narrative: true)
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            XCTAssertEqual(controller.citations[document.id]?.count, 0)
        }
    }

    func testSummaryCitationRetainsMeetingAndExactSegmentIdentityAlongsideValidatedPlaybackOffset() async throws {
        try await fixture { f in
            let document = try await f.document(kind: .summary, source: f.selectedSegments[1], start: 40_000, end: 56_000)
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let citation = try XCTUnwrap(controller.citations[document.id]?.first,
                "The real stored summary must first produce a valid citation")
            XCTAssertEqual(citation.startSample, 40_000)
            let target = try XCTUnwrap(controller.citationNavigationTarget(documentID: document.id, citationID: citation.id),
                "Source activation must provide a transcript row identity, not just an audio offset")
            XCTAssertEqual(target.meetingID, f.selected)
            XCTAssertEqual(target.segmentID, f.selectedSegments[1].id)
            XCTAssertEqual(target.startSample, 40_000)
            XCTAssertEqual(target.endSample, 56_000)
            let originals = try await f.services.store.transcript(meetingID: f.selected)
            XCTAssertEqual(originals, f.selectedSegments)
        }
    }

    func testAnswerCitationWithSameOffsetAsAnotherMeetingStillTargetsOnlySelectedTranscriptRow() async throws {
        try await fixture { f in
            let document = try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: 0, end: 16_000)
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let citation = try XCTUnwrap(controller.citations[document.id]?.first)
            let target = try XCTUnwrap(controller.citationNavigationTarget(documentID: document.id, citationID: citation.id))
            XCTAssertEqual(target.meetingID, f.selected)
            XCTAssertEqual(target.segmentID, f.selectedSegments[0].id)
            XCTAssertNotEqual(target.segmentID, f.otherSegment.id)
            XCTAssertEqual(target.startSample, f.otherSegment.startSample,
                "Equal media offsets cannot establish transcript or meeting identity")
        }
    }

    func testForeignUnknownOutOfBoundsAndUnsupportedQuoteCitationsCannotCreateNavigationTargets() async throws {
        try await fixture { f in
            let valid = try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: 0, end: 16_000)
            let invalid = [
                try await f.document(kind: .questionAnswer, source: f.otherSegment, start: 0, end: 16_000),
                try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: -1, end: 16_000),
                try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: 0, end: 16_001),
                try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: 16_000, end: 16_000),
                try await f.document(kind: .questionAnswer, source: f.selectedSegments[0], start: 0, end: 16_000,
                                     quote: "Unsupported invented quote")
            ]
            let controller = MeetingIntelligenceController(services: f.services, meetingID: f.selected)
            await controller.load()
            let citation = try XCTUnwrap(controller.citations[valid.id]?.first)
            XCTAssertNil(controller.citationNavigationTarget(documentID: UUID(), citationID: citation.id))
            XCTAssertNil(controller.citationNavigationTarget(documentID: valid.id, citationID: "missing-citation"))
            for document in invalid {
                XCTAssertEqual(controller.citations[document.id]?.count, 0)
                XCTAssertNil(controller.citationNavigationTarget(documentID: document.id, citationID: citation.id))
            }
            let otherController = MeetingIntelligenceController(services: f.services, meetingID: f.other)
            await otherController.load()
            XCTAssertNil(otherController.citationNavigationTarget(documentID: valid.id, citationID: citation.id))
        }
    }

    private func fixture(_ body: @MainActor (CitationNavigationFixture) async throws -> Void) async throws {
        let f = try await CitationNavigationFixture.create()
        do { try await body(f) }
        catch { await f.cleanup(); throw error }
        await f.cleanup()
    }
}

@MainActor
private struct CitationNavigationFixture {
    let root: URL
    let services: LocalMinutesServices
    let selected: UUID
    let other: UUID
    let selectedSegments: [StoredTranscriptSegment]
    let otherSegment: StoredTranscriptSegment

    static func create() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-citation-navigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let services = try LocalMinutesServices(rootURL: root)
        do {
            let selected = UUID(), other = UUID()
            for id in [selected, other] {
                try await services.store.createMeeting(.init(id: id, title: "Synthetic citation fixture",
                    createdAt: Date(timeIntervalSince1970: 1), recordingState: .completed, capturedSampleCount: 64_000))
            }
            let segments = [
                StoredTranscriptSegment(id: UUID(), meetingID: selected, sequence: 0, startSample: 0, endSample: 16_000,
                    text: "Maya: The launch budget is 42000 credits.", modelRevision: "synthetic-asr"),
                StoredTranscriptSegment(id: UUID(), meetingID: selected, sequence: 1, startSample: 32_000, endSample: 64_000,
                    text: "Leo: I will write the guide by Thursday.", modelRevision: "synthetic-asr")
            ]
            let otherSegment = StoredTranscriptSegment(id: UUID(), meetingID: other, sequence: 0,
                startSample: 0, endSample: 16_000, text: "Alex: Other meeting source.", modelRevision: "synthetic-other-asr")
            try await services.store.appendFinalizedSegments(segments, to: selected)
            try await services.store.appendFinalizedSegments([otherSegment], to: other)
            return Self(root: root, services: services, selected: selected, other: other,
                        selectedSegments: segments, otherSegment: otherSegment)
        } catch {
            try? await services.store.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func document(kind: GeneratedDocumentKind, source: StoredTranscriptSegment,
                  start: Int64, end: Int64, quote: String? = nil, narrative: Bool = false) async throws -> StoredGeneratedDocument {
        let evidence: [[String: Any]] = [["source_id": source.id.uuidString,
            "start_sample": start, "end_sample": end, "quote": quote ?? source.text]]
        var payload: [String: Any] = ["schema_version": 1, "meeting_id": selected.uuidString]
        if kind == .summary && narrative {
            payload["schema_version"] = 2
            payload["overview"] = ["text": "Documentation is scheduled for Thursday.", "evidence": evidence]
            payload["bullets"] = [["text": "Leo committed to preparing the guide for Thursday.", "evidence": evidence]]
        } else if kind == .summary {
            payload["summary_points"] = [["text": source.text, "evidence": evidence]]
            payload["decisions"] = []; payload["actions"] = []
        } else { payload["status"] = "supported_quote"; payload["evidence"] = evidence }
        let document = StoredGeneratedDocument(id: UUID(), meetingID: selected, kind: kind,
            originalJSON: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            question: kind == .questionAnswer ? "What does this source say?" : nil,
            editedText: "Original synthetic generated content", modelRevision: "synthetic-model",
            promptVersion: "synthetic-prompt", createdAt: Date(timeIntervalSince1970: 2),
            modifiedAt: Date(timeIntervalSince1970: 2))
        try await services.store.createGeneratedDocument(document)
        return document
    }

    func cleanup() async {
        do {
            try await services.store.close()
            guard root.lastPathComponent.hasPrefix("localminutes-citation-navigation-"),
                  UUID(uuidString: String(root.lastPathComponent.dropFirst("localminutes-citation-navigation-".count))) != nil else {
                XCTFail("Citation fixture ownership mismatch"); return
            }
            try FileManager.default.removeItem(at: root)
        } catch { XCTFail("Citation fixture cleanup failed") }
    }
}
#endif
