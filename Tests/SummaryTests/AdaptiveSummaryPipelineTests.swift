import Foundation
import XCTest
@testable import LocalMinutesSummary

@MainActor
final class AdaptiveSummaryPipelineTests: XCTestCase {
    func testFullTranscriptBeyondOldContextAndUnitLimitsUsesExactlyOneRequest() async throws {
        let source = singlePassSource(count: 300)
        let boundary = SinglePassBoundary()
        let pipeline = pipeline(boundary, inputTokens: 14_000)
        let result = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.ids, Array(0..<300))
        XCTAssertEqual(calls.first?.maximumTokens, 3_500)
        XCTAssertFalse(result.bullets.isEmpty)
        XCTAssertFalse(result.bullets.contains(where: \.isSourceExcerpt))
        XCTAssertEqual(result.bullets.last?.evidence.last?.sourceID, "source-299")
        let snapshot = await pipeline.snapshot()
        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertEqual(snapshot.result, result)
    }

    func testSelectedModelDeterminesWhetherTheSameTranscriptFits() async throws {
        let source = singlePassSource(count: 40)
        for context in [4_096, 32_768, 131_072] {
            let boundary = SinglePassBoundary()
            let pipeline = pipeline(boundary, context: context, inputTokens: 12_000)
            if context == 4_096 {
                do {
                    _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
                    XCTFail("Oversized input must fail before any inference")
                } catch { XCTAssertEqual(error as? NarrativeSummaryError, .contextExceeded) }
                let calls = await boundary.calls
                XCTAssertTrue(calls.isEmpty)
                let snapshot = await pipeline.snapshot()
                XCTAssertEqual(snapshot.phase, .failed)
                XCTAssertNil(snapshot.result)
            } else {
                _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
                let calls = await boundary.calls
                XCTAssertEqual(calls.count, 1)
                XCTAssertEqual(calls[0].ids.count, 40)
            }
        }
    }

    func testInputThatFitsAloneButNotWithExpectedOutputFailsBeforeGeneration() async throws {
        let source = singlePassSource(count: 2)
        let boundary = SinglePassBoundary()
        let pipeline = pipeline(boundary, inputTokens: 30_000)
        do {
            _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
            XCTFail("Do not shrink the output reserve or subdivide to force a fit")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .contextExceeded) }
        let calls = await boundary.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testGenerationFailuresNeverRetrySplitOrReturnExcerpts() async throws {
        let source = singlePassSource(count: 30)
        for failure in [LocalSummaryRuntimeError.outputLimitExceeded, .generationFailed, .contextUnavailable, .contextExceeded] {
            let boundary = SinglePassBoundary(failure: failure)
            let pipeline = pipeline(boundary)
            do {
                _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
                XCTFail("A failed attempt cannot become a successful excerpt document")
            } catch { XCTAssertEqual(error as? LocalSummaryRuntimeError, failure) }
            let calls = await boundary.calls
            XCTAssertEqual(calls.count, 1)
            let snapshot = await pipeline.snapshot()
            XCTAssertEqual(snapshot.phase, .failed)
            XCTAssertNil(snapshot.result)
        }
    }

    func testMalformedResponseFailsAfterOneAttempt() async throws {
        let source = singlePassSource(count: 2)
        let boundary = SinglePassBoundary(response: #"{"bullets":["#)
        let pipeline = pipeline(boundary)
        do {
            _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
            XCTFail("Partial JSON must not be repaired or saved")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidResponse) }
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 1)
        let snapshot = await pipeline.snapshot()
        XCTAssertNil(snapshot.result)
    }

    func testCancellationDoesNotGenerateOrProduceFallbackOutput() async throws {
        let source = singlePassSource(count: 2)
        let boundary = SinglePassBoundary()
        let pipeline = AdaptiveSummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            contextTokenLimit: 32_768, reservedOutputTokens: 16_384,
            tokenizer: { _ in throw CancellationError() },
            generator: { try await boundary.generate($0, $1, $2) })
        do {
            _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
            XCTFail("Cancellation must escape")
        } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await boundary.calls
        XCTAssertTrue(calls.isEmpty)
        let snapshot = await pipeline.snapshot()
        XCTAssertEqual(snapshot.phase, .cancelled)
        XCTAssertNil(snapshot.result)
    }

    func testWrongMeetingFailsBeforeGeneration() async throws {
        let boundary = SinglePassBoundary()
        do {
            _ = try await pipeline(boundary).summarize(selectedMeetingID: UUID(), source: singlePassSource(count: 2))
            XCTFail("Another meeting's transcript cannot be summarized")
        } catch { XCTAssertEqual(error as? GroundedSummaryError, .meetingMismatch) }
        let calls = await boundary.calls
        XCTAssertTrue(calls.isEmpty)
    }

    private func pipeline(_ boundary: SinglePassBoundary, context: Int = 32_768,
                          inputTokens: Int = 2_000) -> AdaptiveSummaryPipeline {
        AdaptiveSummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            contextTokenLimit: context, reservedOutputTokens: min(16_384, context / 2),
            tokenizer: { _ in inputTokens }, generator: { try await boundary.generate($0, $1, $2) })
    }
}

private func singlePassSource(count: Int) -> GroundedSummarySource {
    .init(meetingID: UUID(), segments: (0..<count).map { index in
        .init(id: "source-\(index)", startSample: Int64(index) * 200_000,
              endSample: Int64(index) * 200_000 + 80_000,
              text: "Discussion \(index): preserve this original point and its qualifications.")
    }, originalManualNotes: "Use the complete meeting.")
}

private actor SinglePassBoundary {
    struct Call: Sendable { let ids: [Int]; let maximumTokens: Int }
    private(set) var calls: [Call] = []
    let failure: LocalSummaryRuntimeError?
    let response: String?
    init(failure: LocalSummaryRuntimeError? = nil, response: String? = nil) {
        self.failure = failure; self.response = response
    }
    func generate(_ prompt: String, _ schema: StructuredJSONSchema, _ maximum: Int) throws -> String {
        guard let marker = prompt.range(of: "SOURCE_UNITS_JSON:\n", options: .backwards) else {
            throw NarrativeSummaryError.invalidResponse
        }
        struct Row: Decodable { let id: Int; let text: String }
        let rows = try JSONDecoder().decode([Row].self, from: Data(prompt[marker.upperBound...].utf8))
        calls.append(.init(ids: rows.map(\.id), maximumTokens: maximum))
        XCTAssertTrue(prompt.hasPrefix("NARRATIVE_DRAFT\n"))
        XCTAssertTrue(schema.promptIncludesSchema)
        _ = try schema.grammar()
        if let failure { throw failure }
        if let response { return response }
        let first = rows.first!.id, last = rows.last!.id
        return """
        {"bullets":[{"text":"The opening issue was discussed.","source_ids":[\(first)]},
        {"text":"The closing issue remained qualified.","source_ids":[\(last)]}],
        "overview":{"text":"The team discussed the issues and their qualifications.","source_ids":[\(first),\(last)]}}
        """
    }
}
