import Foundation
import XCTest
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Exercises the exact fallback used by the Xcode 26.2 app, including the real
/// pipeline prompt. The JSON transport is a double, not Apple inference.
@MainActor
final class ApplePromptBudgetTests: XCTestCase {
    func testRecordedMeetingFitsConservativeAppleBudgetAndKeepsEverySource() async throws {
        let meeting = UUID()
        let segments = (0..<24).map { index in
            SummaryEvidenceSegment(id: UUID().uuidString,
                startSample: Int64(index * 80_000), endSample: Int64((index + 1) * 80_000),
                text: "Meeting update \(index): the local download screen needs review and the transcript is saved.")
        }
        let requests = AppleBudgetRequests()
        let pipeline = SummaryPipeline(modelRevision: "apple-system-ios-26.2.0",
            tokenizer: { AppleFoundationPromptBudget.conservativeTokenCount(prompt: $0) },
            generator: { prompt, schema, maximum in
                let marker = try XCTUnwrap(prompt.range(of: "\n\nEVIDENCE_JSON:\n"))
                let sources = try JSONDecoder().decode([SummaryEvidenceSegment].self,
                    from: Data(prompt[marker.upperBound...].utf8))
                let first = try XCTUnwrap(sources.first)
                XCTAssertTrue(schema.promptIncludesSchema, "Do not inject the repeated quote schema into Apple's context")
                XCTAssertLessThan(AppleFoundationPromptBudget.conservativeTokenCount(prompt: prompt) + maximum, 4_096)
                await requests.append(sources.map(\.id))
                let response: [String: Any] = ["meeting_id": meeting.uuidString,
                    "summary_points": [["text": first.text, "evidence": [[
                        "source_id": first.id, "start_sample": first.startSample,
                        "end_sample": first.endSample, "quote": first.text]]]],
                    "decisions": [], "actions": []]
                return String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
            })
        let result = try await pipeline.summarize(selectedMeetingID: meeting,
            source: .init(meetingID: meeting, segments: segments, originalManualNotes: "Review the download screen."))
        XCTAssertFalse(result.summaryPoints.isEmpty)
        let chunks = await requests.chunks
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.flatMap { $0 }, segments.map(\.id), "Chunking must never drop transcript text")
    }
}

private actor AppleBudgetRequests {
    private(set) var chunks: [[String]] = []
    func append(_ ids: [String]) { chunks.append(ids) }
}
