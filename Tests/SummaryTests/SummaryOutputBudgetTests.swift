import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class SummaryOutputBudgetTests: XCTestCase {
    func testLargerOutputBudgetAllowsMoreThanTwoFindingsFromOneParagraph() async throws {
        let meeting = UUID()
        let sentences = (0..<8).map { "Topic \($0) needs review." }
        let source = SummaryEvidenceSegment(id: "source", startSample: 0, endSample: 16_000,
            text: sentences.joined(separator: " "))
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            contextTokenLimit: 32_768, reservedOutputTokens: 8_192, tokenizer: { _ in 500 },
            generator: { _, schema, maximum in
                XCTAssertEqual(maximum, 8_192)
                let field = try XCTUnwrap(schema.fields.first { $0.name == "summary_points" })
                guard case .array(_, let limit) = field.type else { throw GroundedSummaryError.invalidJSON }
                XCTAssertGreaterThanOrEqual(limit, sentences.count)
                let points: [[String: Any]] = sentences.map {
                    ["text": $0, "evidence": [["source_id": source.id, "start_sample": source.startSample,
                                               "end_sample": source.endSample, "quote": $0]]]
                }
                let bytes = try JSONSerialization.data(withJSONObject: ["meeting_id": meeting.uuidString,
                    "summary_points": points, "decisions": [], "actions": []])
                return String(decoding: bytes, as: UTF8.self)
            })
        let result = try await pipeline.summarize(selectedMeetingID: meeting,
            source: .init(meetingID: meeting, segments: [source], originalManualNotes: ""))
        XCTAssertEqual(Set(result.summaryPoints.map(\.text)), Set(sentences))
    }

    func testCompactBatchesAreConsolidatedWithoutDroppingTheEndOfTheTranscript() async throws {
        let meeting = UUID()
        let source = SummaryEvidenceSegment(id: "source", startSample: 0, endSample: 32_000,
            text: (0..<600).map { "Topic \($0) needs review." }.joined(separator: " "))
        let calls = OutputBudgetCalls()
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            contextTokenLimit: 32_768, reservedOutputTokens: 16_384, tokenizer: { _ in 500 },
            generator: { try await calls.generate(schema: $1, maximum: $2) })
        let result = try await pipeline.summarize(selectedMeetingID: meeting,
            source: .init(meetingID: meeting, segments: [source], originalManualNotes: ""))
        let offered = await calls.offered
        let consolidations = await calls.consolidations
        XCTAssertEqual(offered, (0..<600).map { Int64($0) })
        XCTAssertGreaterThan(consolidations, 0)
        XCTAssertGreaterThan(result.summaryPoints.count, 2)
        XCTAssertLessThanOrEqual(result.summaryPoints.count, 128)
        XCTAssertTrue(result.summaryPoints.contains { $0.text == "Topic 599 needs review." })
        XCTAssertTrue(result.summaryPoints.allSatisfy { $0.evidence.first?.sourceID == "source" })
    }

    func testExpandedCitationsCanExceedTheOldSixtyFourKByteMapLimit() async throws {
        let meeting = UUID()
        let sentences = (0..<16).map { "Topic \($0): " + String(repeating: "detail ", count: 300) + "." }
        let source = SummaryEvidenceSegment(id: "source", startSample: 0, endSample: 16_000,
            text: sentences.joined(separator: " "))
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            contextTokenLimit: 32_768, reservedOutputTokens: 8_192, tokenizer: { _ in 500 },
            generator: { _, _, maximum in
                XCTAssertGreaterThan(maximum, 256)
                return "{\"summary_points\":[\((0..<16).map(String.init).joined(separator: ","))],\"decisions\":[],\"actions\":[]}"
            })
        let result = try await pipeline.summarize(selectedMeetingID: meeting,
            source: .init(meetingID: meeting, segments: [source], originalManualNotes: ""))
        XCTAssertEqual(result.summaryPoints.count, 16)
        XCTAssertGreaterThan(result.summaryPoints.reduce(0) { $0 + $1.text.utf8.count * 2 }, 65_536)
        XCTAssertEqual(Set(result.summaryPoints.map(\.text)), Set(sentences))
    }
}

private actor OutputBudgetCalls {
    private(set) var offered: [Int64] = []
    private(set) var consolidations = 0
    func generate(schema: StructuredJSONSchema, maximum: Int) throws -> String {
        let field = try XCTUnwrap(schema.fields.first)
        guard case .array(let element, let limit) = field.type,
              case .integerEnumeration(let ids) = element else { throw GroundedSummaryError.invalidJSON }
        if field.name == "keep" {
            consolidations += 1
            let selected = Array(ids.prefix(max(0, limit - 1))) + Array(ids.suffix(1))
            return "{\"keep\":[\(selected.map(String.init).joined(separator: ","))]}"
        }
        XCTAssertGreaterThan(maximum, 256)
        offered += ids
        return "{\"summary_points\":[\(ids.suffix(limit).map(String.init).joined(separator: ","))],\"decisions\":[],\"actions\":[]}"
    }
}
