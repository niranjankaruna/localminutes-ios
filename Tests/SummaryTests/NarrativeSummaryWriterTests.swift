import Foundation
import XCTest
@testable import LocalMinutesSummary

/// These tests exercise the orchestration and trust boundary using scripted
/// generations. They do not measure a real model's semantic accuracy.
@MainActor
final class NarrativeSummaryWriterTests: XCTestCase {
    func testOverviewPointsKeepTheirLineBreaksThroughGenerationAndSourceReview() async throws {
        let bullet = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let overview = NarrativeDraftParagraph(text: "Discussed launch timing.\nRevised the plan after a supplier delay.", sourceIDs: [41, 73])
        let boundary = NarrativeWriterBoundary(replies: [try draftJSON(bullet, overview), approved, approved])
        let result = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
        XCTAssertEqual(SummaryOverviewFormatting.points(result.overview.text),
            ["Discussed launch timing.", "Revised the plan after a supplier delay."])
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 3, "The overview points must still pass source review")
        XCTAssertTrue(calls[0].prompt.contains("Do not write an overview paragraph"))
        XCTAssertTrue(calls[2].prompt.contains(try paragraphJSON(overview)))
    }

    func testAcceptsParaphrasedProseAndReviewsWithCompleteOriginalContext() async throws {
        let units = revisedLaunchUnits()
        let bullet = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let overview = NarrativeDraftParagraph(text: "The team revised its launch timing after a supplier delay.", sourceIDs: [41, 73])
        let boundary = NarrativeWriterBoundary(replies: [try draftJSON(bullet, overview), approved, approved])
        let result = try await writer(boundary).draft(units: units, notes: "Focus on the launch.")
        XCTAssertEqual(result.bullets, [bullet])
        XCTAssertEqual(result.overview, overview)
        XCTAssertFalse(units.contains { $0.text.contains(bullet.text) }, "Synthesis must not require verbatim transcript wording")
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls[0].prompt.hasPrefix("NARRATIVE_DRAFT"))
        for call in calls.dropFirst() {
            XCTAssertTrue(call.prompt.hasPrefix("NARRATIVE_REVIEW"))
            XCTAssertEqual(call.schema.fields.map(\.name), ["issues"],
                "Approval is derived from issues; the model cannot emit a contradictory boolean verdict")
            XCTAssertTrue(call.prompt.contains(units[0].segments[0].text), "Review includes the earlier proposal")
            XCTAssertTrue(call.prompt.contains(units[1].segments[0].text), "Review includes the later correction")
        }
    }

    func testChangedDateGetsOneTargetedRepairAndTheRepairIsRechecked() async throws {
        let stale = NarrativeDraftParagraph(text: "The launch is scheduled for Friday.", sourceIDs: [41])
        let corrected = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let boundary = NarrativeWriterBoundary(replies: [
            try draftJSON(stale, corrected),
            #"{"issues":["Source 73 explicitly replaces Friday with Tuesday."]}"#,
            try paragraphJSON(corrected), approved, approved
        ])
        let result = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
        XCTAssertEqual(result.bullets, [corrected])
        let calls = await boundary.calls
        XCTAssertEqual(calls.filter { $0.prompt.hasPrefix("NARRATIVE_REPAIR") }.count, 1)
        XCTAssertEqual(calls.filter { $0.prompt.hasPrefix("NARRATIVE_REVIEW") }.count, 3)
        XCTAssertTrue(calls[3].prompt.contains(try paragraphJSON(corrected)))
    }

    func testConditionalCommitmentCannotBecomeAnUnqualifiedPromiseAfterRejectedReview() async throws {
        let units = [NarrativeSourceUnit(id: 9, segments: [.init(id: "condition", startSample: 0, endSample: 16_000,
            text: "Maya: If security approves, I can deploy on Friday; approval is still pending.")])]
        let unconditional = NarrativeDraftParagraph(text: "Maya will deploy on Friday.", sourceIDs: [9])
        let conditional = NarrativeDraftParagraph(text: "Maya may deploy on Friday if security approves; approval remains pending.", sourceIDs: [9])
        let boundary = NarrativeWriterBoundary(replies: [
            try draftJSON(unconditional, conditional),
            #"{"issues":["The deployment depends on pending security approval in source 9."]}"#,
            try paragraphJSON(conditional), approved, approved
        ])
        let result = try await writer(boundary).draft(units: units, notes: "")
        XCTAssertEqual(result.bullets, [conditional])
        let calls = await boundary.calls
        XCTAssertTrue(calls[2].prompt.contains("pending security approval"))
    }

    func testRejectedRepairFailsVisiblyWithoutASecondRepairOrExtractiveFallback() async throws {
        let unsupported = NarrativeDraftParagraph(text: "The launch is scheduled for Friday.", sourceIDs: [41])
        let rejected = #"{"issues":["Friday was explicitly superseded by Tuesday in source 73."]}"#
        let boundary = NarrativeWriterBoundary(replies: [
            try draftJSON(unsupported, unsupported), rejected, try paragraphJSON(unsupported), rejected
        ])
        do {
            _ = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("A rejected repair must not publish the original claim or a quote fallback")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .unsupportedEvidence) }
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls.filter { $0.prompt.hasPrefix("NARRATIVE_REPAIR") }.count, 1)
    }

    func testInventedOrRepeatedReferencesFailBeforeAnyReview() async throws {
        for sourceIDs in [[999], [41, 41], []] {
            let invalid = NarrativeDraftParagraph(text: "The launch moved.", sourceIDs: sourceIDs)
            let boundary = NarrativeWriterBoundary(replies: [try draftJSON(invalid, invalid)])
            do {
                _ = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
                XCTFail("Invalid source membership must not reach semantic review")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .unsupportedEvidence) }
            let calls = await boundary.calls
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testEmptyBulletsAndAdditionalFieldsAreRejected() async throws {
        for json in [
            #"{"bullets":[],"overview":{"text":"Launch timing changed.","source_ids":[73]}}"#,
            #"{"bullets":[{"text":"Launch timing changed.","source_ids":[73],"action":"invented"}],"overview":{"text":"Launch timing changed.","source_ids":[73]}}"#,
            #"{"bullets":[{"text":"Launch timing changed.","source_ids":[73]}],"overview":{"text":"Launch timing changed.","source_ids":[73]},"decisions":[]}"#
        ] {
            let boundary = NarrativeWriterBoundary(replies: [json, json])
            do {
                _ = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
                XCTFail("Malformed prose structure must be rejected")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidResponse) }
            let calls = await boundary.calls
            XCTAssertEqual(calls.count, 2, "Malformed responses get one bounded retry, never silent acceptance")
        }
    }

    func testMalformedOrLegacyContradictoryReviewResponsesAreNotTreatedAsApproval() async throws {
        let paragraph = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        for review in [
            #"{"supported":true,"issues":["An unsupported date."]}"#,
            #"{"supported":false,"issues":[]}"#,
            #"{"supported":true,"issues":[],"confidence":1}"#,
            #"{"supported":"yes","issues":[]}"#
        ] {
            let boundary = NarrativeWriterBoundary(replies: [try draftJSON(paragraph, paragraph), review])
            do {
                _ = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
                XCTFail("Only a consistent structured verdict may approve prose")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidResponse) }
        }
    }

    func testOverviewRemainsParaphrasedAndGroundedInOriginalSources() async throws {
        let bullet = NarrativeDraftParagraph(text: "The launch moved from Friday to Tuesday after a supplier delay.", sourceIDs: [41, 73])
        let overview = NarrativeDraftParagraph(text: "A supplier delay prompted a revised launch plan.", sourceIDs: [73])
        let boundary = NarrativeWriterBoundary(replies: [try paragraphJSON(overview), approved])
        let result = try await writer(boundary).overview(bullets: [bullet], units: revisedLaunchUnits(), notes: "")
        XCTAssertEqual(result, overview)
        let calls = await boundary.calls
        XCTAssertTrue(calls[0].prompt.hasPrefix("NARRATIVE_OVERVIEW"))
        XCTAssertTrue(calls[0].prompt.contains("BULLETS_JSON"))
        XCTAssertTrue(calls[1].prompt.hasPrefix("NARRATIVE_REVIEW"))
    }

    func testPromptsExposeCompleteJoinedTextWithoutMetadataOrAnswerExamples() async throws {
        let units = [NarrativeSourceUnit(id: 9, segments: [
            .init(id: "private-segment-a", startSample: 0, endSample: 8_000, text: "Maya: Security approval is pending."),
            .init(id: "private-segment-b", startSample: 8_000, endSample: 16_000, text: "Deployment depends on that approval.")
        ])]
        let paragraph = NarrativeDraftParagraph(text: "Deployment remains conditional on pending security approval.", sourceIDs: [9])
        let boundary = NarrativeWriterBoundary(replies: [try draftJSON(paragraph, paragraph), approved, approved])
        _ = try await writer(boundary).draft(units: units, notes: "")
        let calls = await boundary.calls
        for call in calls {
            let marker = try XCTUnwrap(call.prompt.range(of: "SOURCE_UNITS_JSON:\n"))
            let data = Data(call.prompt[marker.upperBound...].utf8)
            let rows = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(Set(rows[0].keys), ["id", "text"])
            XCTAssertEqual(rows[0]["id"] as? Int, 9)
            XCTAssertEqual(rows[0]["text"] as? String, units[0].text)
            XCTAssertFalse(call.prompt.contains("private-segment-a"))
            XCTAssertFalse(call.prompt.contains("startSample"))
            XCTAssertFalse(call.prompt.contains("ticket queue"), "A style example must not become fabricated meeting content")
            XCTAssertFalse(call.prompt.contains("concise overview paragraph"), "Do not supply a literal answer placeholder")
        }
    }

    func testFitChecksUseExactlyTheSameWritingPromptsThatGenerationReceives() async throws {
        let paragraph = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let boundary = NarrativeWriterBoundary(replies: [
            try draftJSON(paragraph, paragraph), approved, approved, try paragraphJSON(paragraph), approved
        ])
        let counter = NarrativeWriterCounter()
        let instance = try writer(boundary, tokenizer: { await counter.count($0) })
        let fitsDraft = try await instance.canDraft(units: revisedLaunchUnits(), notes: "Keep context.", topic: "Launch")
        XCTAssertTrue(fitsDraft)
        _ = try await instance.draft(units: revisedLaunchUnits(), notes: "Keep context.", topic: "Launch")
        let fitsOverview = try await instance.canOverview(bullets: [paragraph], units: revisedLaunchUnits(), notes: "")
        XCTAssertTrue(fitsOverview)
        _ = try await instance.overview(bullets: [paragraph], units: revisedLaunchUnits(), notes: "")
        let counted = await counter.prompts
        let calls = await boundary.calls
        let drafts = counted.filter { $0.hasPrefix("NARRATIVE_DRAFT") }
        let overviews = counted.filter { $0.hasPrefix("NARRATIVE_OVERVIEW") }
        XCTAssertEqual(drafts.count, 3, "Admission, invocation admission, and actual generation use the same writing prompt")
        XCTAssertTrue(drafts.allSatisfy { $0 == calls[0].prompt })
        XCTAssertEqual(overviews.count, 3)
        XCTAssertTrue(overviews.allSatisfy { $0 == calls[3].prompt })
        XCTAssertTrue(counted.contains { $0.hasPrefix("NARRATIVE_REPAIR") }, "Admission also reserves potential repair input")
    }

    func testReviewContextOverflowFailsAdmissionRatherThanDroppingLaterSources() async throws {
        let boundary = NarrativeWriterBoundary(replies: [])
        let instance = try writer(boundary, tokenizer: { prompt in prompt.hasPrefix("NARRATIVE_REVIEW") ? 10_000 : 20 })
        let fits = try await instance.canDraft(units: revisedLaunchUnits(), notes: "")
        XCTAssertFalse(fits)
        do {
            _ = try await instance.draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("An oversized review must not silently narrow its source context")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .contextExceeded) }
        let calls = await boundary.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testRepairHeadroomIsReservedBeforeGeneratingAUsableDraft() async throws {
        let boundary = NarrativeWriterBoundary(replies: [])
        let instance = try writer(boundary, tokenizer: { prompt in prompt.hasPrefix("NARRATIVE_REPAIR") ? 3_000 : 20 })
        let fits = try await instance.canDraft(units: revisedLaunchUnits(), notes: "")
        XCTAssertFalse(fits, "Repair must reserve both prior writing/checking responses as input plus a new writing response")
        let calls = await boundary.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testStageOutputCapsArePassedToTheRuntimeAndOversizedTransportIsRejected() async throws {
        let paragraph = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let boundary = NarrativeWriterBoundary(replies: [try draftJSON(paragraph, paragraph), approved, approved])
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 700)
        let instance = NarrativeSummaryWriter(tokenizer: { _ in 20 },
            generator: { try await boundary.generate($0, $1, $2) }, budget: budget)
        _ = try await instance.draft(units: revisedLaunchUnits(), notes: "")
        let calls = await boundary.calls
        XCTAssertEqual(calls.map(\.maximumOutputTokens), [budget.writingTokens, budget.checkingTokens, budget.checkingTokens])
        let oversized = NarrativeWriterBoundary(replies: [String(repeating: "x", count: 65_537)])
        do {
            _ = try await writer(oversized).draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("Unbounded transport must be rejected before JSON decoding")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .limitExceeded) }
    }

    func testRuntimeOutputLimitAndCancellationDoNotPublishPartialProse() async throws {
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 512)
        let limited = NarrativeSummaryWriter(tokenizer: { _ in 20 }, generator: { _, _, _ in
            throw LocalSummaryRuntimeError.outputLimitExceeded
        }, budget: budget)
        do {
            _ = try await limited.draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("Truncated model output must propagate as failure")
        } catch { XCTAssertEqual(error as? LocalSummaryRuntimeError, .outputLimitExceeded) }
        let cancelled = NarrativeSummaryWriter(tokenizer: { _ in 20 }, generator: { _, _, _ in
            throw CancellationError()
        }, budget: budget)
        do {
            _ = try await cancelled.draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testOutputLimitRetriesBoundedProseWithAllOriginalSourcesAndTheSameTokenCap() async throws {
        let paragraph = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let boundary = NarrativeWriterBoundary(replies: ["", try draftJSON(paragraph, paragraph), approved, approved],
            outputLimitCalls: [1])
        let result = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "Keep qualifications.")
        XCTAssertEqual(result.bullets, [paragraph])
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 4)
        XCTAssertTrue(calls[1].prompt.hasPrefix("NARRATIVE_DRAFT\nRESPONSE_RECOVERY:"))
        XCTAssertEqual(calls[0].maximumOutputTokens, calls[1].maximumOutputTokens)
        XCTAssertTrue(try calls[1].schema.grammar().contains("json-char{0,"))
        for unit in revisedLaunchUnits() { XCTAssertTrue(calls[1].prompt.contains(unit.text)) }
        XCTAssertTrue(calls[1].prompt.contains("Keep qualifications."))
        XCTAssertTrue(calls.dropFirst(2).allSatisfy { $0.prompt.hasPrefix("NARRATIVE_REVIEW") })
    }

    func testMalformedCheckingResponsesRetryWithoutTreatingTheFailureAsApproval() async throws {
        let paragraph = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        for malformed in [
            "{\"supported\":",
            #"{"supported":true,"issues":["The date is unsupported."]}"#,
            #"{"supported":false,"issues":[]}"#,
            #"{"supported":"yes","issues":[]}"#,
            #"{"issues":[" "]}"#,
            #"{"issues":"none"}"#
        ] {
            let boundary = NarrativeWriterBoundary(replies: [try draftJSON(paragraph, paragraph), malformed, approved, approved])
            let result = try await writer(boundary).draft(units: revisedLaunchUnits(), notes: "")
            XCTAssertEqual(result.bullets, [paragraph])
            let calls = await boundary.calls
            XCTAssertEqual(calls.count, 4)
            XCTAssertTrue(calls[2].prompt.hasPrefix("NARRATIVE_REVIEW\nRESPONSE_RECOVERY:"))
            XCTAssertTrue(calls[2].prompt.contains("ALL original source units"))
            XCTAssertEqual(calls[1].maximumOutputTokens, calls[2].maximumOutputTokens)
            for unit in revisedLaunchUnits() { XCTAssertTrue(calls[2].prompt.contains(unit.text)) }
        }
    }

    func testCheckingRepairAndOverviewOutputLimitsEachRecoverBeforePublishing() async throws {
        let stale = NarrativeDraftParagraph(text: "The launch is scheduled for Friday.", sourceIDs: [41])
        let corrected = NarrativeDraftParagraph(text: "A supplier delay moved the launch to Tuesday.", sourceIDs: [73])
        let rejected = #"{"issues":["Source 73 replaces Friday with Tuesday."]}"#
        let repair = NarrativeWriterBoundary(replies: ["", rejected, "", try paragraphJSON(corrected), approved],
            outputLimitCalls: [1, 3])
        let checked = try await writer(repair).checked(stale, units: revisedLaunchUnits(), notes: "")
        XCTAssertEqual(checked, corrected)
        let repairCalls = await repair.calls
        XCTAssertEqual(repairCalls.count, 5)
        XCTAssertTrue(repairCalls[1].prompt.hasPrefix("NARRATIVE_REVIEW\nRESPONSE_RECOVERY:"))
        XCTAssertTrue(repairCalls[3].prompt.hasPrefix("NARRATIVE_REPAIR\nRESPONSE_RECOVERY:"))
        XCTAssertTrue(repairCalls[4].prompt.hasPrefix("NARRATIVE_REVIEW"), "A recovered correction must still be checked")

        let overview = NarrativeWriterBoundary(replies: ["", try paragraphJSON(corrected), approved], outputLimitCalls: [1])
        let result = try await writer(overview).overview(bullets: [corrected], units: revisedLaunchUnits(), notes: "")
        XCTAssertEqual(result, corrected)
        let overviewCalls = await overview.calls
        XCTAssertTrue(overviewCalls[1].prompt.hasPrefix("NARRATIVE_OVERVIEW\nRESPONSE_RECOVERY:"))
    }

    func testRetryCannotApproveAnUnsupportedRepairOrInventedReference() async throws {
        let stale = NarrativeDraftParagraph(text: "The launch is scheduled for Friday.", sourceIDs: [41])
        let rejected = #"{"issues":["Friday was replaced in source 73."]}"#
        let boundary = NarrativeWriterBoundary(replies: ["{}", rejected, try paragraphJSON(stale), rejected])
        do {
            _ = try await writer(boundary).checked(stale, units: revisedLaunchUnits(), notes: "")
            XCTFail("A format retry must not bypass a negative factual verdict")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .unsupportedEvidence) }
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 4)

        let invented = NarrativeDraftParagraph(text: "A launch was agreed.", sourceIDs: [999])
        let references = NarrativeWriterBoundary(replies: ["", try draftJSON(invented, invented)], outputLimitCalls: [1])
        do {
            _ = try await writer(references).draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("An invented reference is not a recoverable format error")
        } catch { XCTAssertEqual(error as? NarrativeSummaryError, .unsupportedEvidence) }
        let referenceCalls = await references.calls
        XCTAssertEqual(referenceCalls.count, 2)
    }

    func testRetryPromptMustFitAndLargeInputsAreLimitedByResponseCapacity() async throws {
        let boundary = NarrativeWriterBoundary(replies: [""], outputLimitCalls: [1])
        let instance = try writer(boundary, tokenizer: { $0.contains("RESPONSE_RECOVERY:") ? 10_000 : 20 })
        do {
            _ = try await instance.draft(units: revisedLaunchUnits(), notes: "")
            XCTFail("A retry cannot exceed the working context")
        } catch { XCTAssertEqual(error as? LocalSummaryRuntimeError, .outputLimitExceeded) }
        let calls = await boundary.calls
        XCTAssertEqual(calls.count, 1)
        let units = (0..<20).map { id in NarrativeSourceUnit(id: id, segments: [
            .init(id: "s\(id)", startSample: Int64(id) * 16_000, endSample: Int64(id + 1) * 16_000, text: "Topic \(id).")
        ]) }
        let fits = try await instance.canDraft(units: units, notes: "")
        XCTAssertFalse(fits, "Tiny input tokens do not imply that every topic will fit in the response")
    }

    private var approved: String { #"{"issues":[]}"# }

    private func writer(_ boundary: NarrativeWriterBoundary,
                        tokenizer: @escaping SummaryTokenCounter = { _ in 20 }) throws -> NarrativeSummaryWriter {
        .init(tokenizer: tokenizer, generator: { try await boundary.generate($0, $1, $2) },
              budget: try .init(contextTokenLimit: 4_096, outputTokenLimit: 512))
    }

    private func revisedLaunchUnits() -> [NarrativeSourceUnit] {
        [NarrativeSourceUnit(id: 41, segments: [.init(id: "proposal", startSample: 0, endSample: 16_000,
            text: "Nora: We are targeting Friday for the launch.")]),
         NarrativeSourceUnit(id: 73, segments: [.init(id: "revision", startSample: 16_000, endSample: 32_000,
            text: "Nora: The supplier is late, so we agreed to move the launch from Friday to Tuesday.")])]
    }

    private func draftJSON(_ bullet: NarrativeDraftParagraph, _ overview: NarrativeDraftParagraph) throws -> String {
        try json(NarrativeSummaryDraft(bullets: [bullet], overview: overview))
    }

    private func paragraphJSON(_ paragraph: NarrativeDraftParagraph) throws -> String { try json(paragraph) }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private actor NarrativeWriterBoundary {
    struct Call: Sendable {
        let prompt: String
        let maximumOutputTokens: Int
        let schema: StructuredJSONSchema
    }
    private let replies: [String]
    private let outputLimitCalls: Set<Int>
    private(set) var calls: [Call] = []
    init(replies: [String], outputLimitCalls: Set<Int> = []) {
        self.replies = replies; self.outputLimitCalls = outputLimitCalls
    }
    func generate(_ prompt: String, _ schema: StructuredJSONSchema, _ maximum: Int) throws -> String {
        _ = try schema.grammar()
        calls.append(.init(prompt: prompt, maximumOutputTokens: maximum, schema: schema))
        if outputLimitCalls.contains(calls.count) { throw LocalSummaryRuntimeError.outputLimitExceeded }
        guard calls.count <= replies.count else { throw NarrativeSummaryError.invalidResponse }
        return replies[calls.count - 1]
    }
}

private actor NarrativeWriterCounter {
    private(set) var prompts: [String] = []
    func count(_ prompt: String) -> Int { prompts.append(prompt); return 20 }
}

