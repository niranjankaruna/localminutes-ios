import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesSummary

/// Boundary doubles exercise orchestration and evidence preservation. These
/// tests do not measure the selected models' narrative or reasoning quality.
@MainActor
final class AdaptiveSummaryPipelineTests: XCTestCase {
    func testProgressCoversDirectAndIndexedWritingAndEverySourceReview() async throws {
        for count in [2, 12] {
            let source = adaptiveSource(count: count)
            let events = SummaryWorkRecorder()
            let pipeline = adaptivePipeline(boundary: AdaptiveBoundary(), unitTokens: count == 2 ? 100 : 400,
                workProgress: { events.append($0) })
            _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
            let reports = events.values
            XCTAssertEqual(reports.first?.completedFraction, 0)
            XCTAssertEqual(try XCTUnwrap(reports.last).completedFraction, 1, accuracy: 0.000001)
            XCTAssertTrue(reports.contains { $0.phase == .writing && $0.operationFraction > 0 })
            XCTAssertGreaterThan(reports.filter { $0.phase == .checking && $0.operationFraction > 0 }.count, 1)
            XCTAssertEqual(reports.contains { $0.phase == .indexing }, count > 2)
            for (previous, next) in zip(reports, reports.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next.completedFraction + 0.000001, previous.completedFraction)
                XCTAssertLessThanOrEqual(next.completedFraction + next.operationFraction, 1.000001)
            }
            if count == 2 {
                let firstDraft = try XCTUnwrap(reports.first { $0.phase == .writing && $0.operationFraction > 0 })
                XCTAssertEqual(firstDraft.completedFraction, 0, "An instant direct index must not consume generation progress")
            }
        }
    }

    func testFittingTopicsKeepTheirOwnSourcesAndAddNeighborsOnlyWhenBudgetAllows() async throws {
        let source = adaptiveSource(count: 3)
        let boundary = NeighborTopicBoundary()
        let pipeline = AdaptiveSummaryPipeline(modelRevision: String(repeating: "a", count: 40),
            tokenizer: { prompt in
                if prompt.hasPrefix("NARRATIVE_DRAFT"),
                   try adaptiveRows(prompt, marker: "SOURCE_UNITS_JSON").count > 2 { return 4_096 }
                return 500
            }, generator: { prompt, _, _ in try await boundary.generate(prompt) })
        let result = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let drafts = await boundary.drafts
        XCTAssertEqual(drafts.count, 3, "Each distinct indexed topic is still drafted")
        XCTAssertEqual(result.bullets.count, 3)
        XCTAssertTrue(drafts.allSatisfy { $0.ids.contains($0.topicID) },
            "Neighbor expansion cannot replace a topic's own source")
        XCTAssertTrue(drafts.allSatisfy { $0.ids.count <= 2 },
            "A third source exceeds this fixture's writing budget")
        XCTAssertTrue(drafts.contains { $0.topicID == 0 && $0.ids.contains(1) },
            "A fitting topic should receive its following original context")
        XCTAssertTrue(drafts.contains { $0.topicID == 2 && $0.ids.contains(1) },
            "A fitting topic should receive its preceding original context")
    }

    func testShortMeetingUsesReviewedDirectParaphraseWithOriginalEvidence() async throws {
        let source = adaptiveSource(count: 2, compact: true)
        let boundary = AdaptiveBoundary()
        let pipeline = adaptivePipeline(boundary: boundary)
        let result = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        XCTAssertFalse(result.bullets.isEmpty)
        XCTAssertNotNil(result.overview)
        XCTAssertEqual(result.provenance.promptVersion, AdaptiveSummaryPipeline.currentPromptVersion)
        XCTAssertFalse(source.segments.contains { $0.text == result.bullets[0].text },
                       "Displayed minutes are paraphrases; citation quotes remain original")
        for evidence in result.bullets.flatMap(\.evidence) {
            let original = try XCTUnwrap(source.segments.first { $0.id == evidence.sourceID })
            XCTAssertNotNil(Data(original.text.utf8).range(of: Data(evidence.quote.utf8)))
            XCTAssertEqual(evidence.startSample, original.startSample)
            XCTAssertEqual(evidence.endSample, original.endSample)
        }
        let calls = await boundary.calls
        XCTAssertFalse(calls.contains { $0.marker == "NARRATIVE_INDEX" })
        XCTAssertTrue(calls.contains { $0.marker == "NARRATIVE_REVIEW" })
        let snapshot = await pipeline.snapshot()
        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertEqual(snapshot.result, result)
    }

    func testLongMeetingReadsEveryUnitAndRetainsLastRevisionAcrossTopicPackets() async throws {
        let source = adaptiveSource(count: 12)
        let units = try NarrativeSourcePlanner.units(source: source)
        let boundary = AdaptiveBoundary()
        let pipeline = adaptivePipeline(boundary: boundary, unitTokens: 400)
        let result = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let calls = await boundary.calls
        let reading = calls.filter { $0.marker == "NARRATIVE_INDEX" }
        XCTAssertGreaterThan(reading.count, 1)
        XCTAssertEqual(Set(reading.flatMap(\.ids)), Set(units.map(\.id)))
        XCTAssertTrue(calls.contains { $0.marker == "NARRATIVE_RECONCILE" })
        let writing = calls.filter { $0.marker == "NARRATIVE_DRAFT" }
        XCTAssertTrue(writing.contains { $0.ids.contains(units.first!.id) && $0.ids.contains(units.last!.id) },
                      "Distant opening and latest source must reach the same topic writer")
        XCTAssertTrue(result.bullets.contains { $0.text.contains("Friday") })
        XCTAssertTrue(result.bullets.flatMap(\.evidence).contains { $0.sourceID == source.segments.last!.id })
        XCTAssertNotNil(result.overview)
    }

    func testUnassignedIndexedSpeechIsRetainedAndEachStageUsesItsOwnBudget() async throws {
        let source = adaptiveSource(count: 10)
        let boundary = AdaptiveBoundary(omitLastIndexedID: true)
        let pipeline = adaptivePipeline(boundary: boundary, unitTokens: 400)
        _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let units = try NarrativeSourcePlanner.units(source: source)
        let calls = await boundary.calls
        let written = Set(calls.filter { $0.marker == "NARRATIVE_DRAFT" }.flatMap(\.ids))
        XCTAssertEqual(written, Set(units.map(\.id)), "Omitted index references must not erase original input")
        let budget = try NarrativeSummaryBudget(contextTokenLimit: 4_096, outputTokenLimit: 1_024)
        for call in calls {
            switch call.marker {
            case "NARRATIVE_INDEX", "NARRATIVE_RECONCILE": XCTAssertEqual(call.maximum, budget.readingTokens)
            case "NARRATIVE_DRAFT", "NARRATIVE_OVERVIEW", "NARRATIVE_REPAIR": XCTAssertEqual(call.maximum, budget.writingTokens)
            case "NARRATIVE_REVIEW": XCTAssertEqual(call.maximum, budget.checkingTokens)
            default: XCTFail("Unexpected generation phase")
            }
        }
    }

    func testLateTopicRepairRechecksEarlierOriginalSources() async throws {
        let source = adaptiveSource(count: 12)
        let boundary = AdaptiveBoundary(repairLateReview: true)
        let events = SummaryWorkRecorder()
        let pipeline = adaptivePipeline(boundary: boundary, unitTokens: 400, workProgress: { events.append($0) })
        _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let calls = await boundary.calls
        let repair = try XCTUnwrap(calls.firstIndex { $0.marker == "NARRATIVE_REPAIR" })
        XCTAssertTrue(calls.dropFirst(repair + 1).contains { $0.marker == "NARRATIVE_REVIEW" && $0.ids.contains(1) },
                      "A late repair must be rechecked against an earlier non-anchor source")
        XCTAssertTrue(events.values.contains { $0.phase == .correcting })
        for (previous, next) in zip(events.values, events.values.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.completedFraction + 0.000001, previous.completedFraction)
        }
    }

    func testCancellationLeavesOnlyValidatedIndexAndResumeSkipsIt() async throws {
        let source = adaptiveSource(count: 12)
        let store = AdaptiveCheckpointBoundary()
        let firstBoundary = AdaptiveBoundary(holdSecondIndex: true)
        let first = adaptivePipeline(boundary: firstBoundary, unitTokens: 400, store: store)
        let task = Task { try await first.summarize(selectedMeetingID: source.meetingID, source: source) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await firstBoundary.held), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await firstBoundary.held
        XCTAssertTrue(held)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work must not publish a partial result") }
        catch is CancellationError {}
        let saved = await store.snapshot()
        XCTAssertEqual(saved?.maps.count, 1)
        let cancelled = await first.snapshot()
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertNil(cancelled.result)

        let secondBoundary = AdaptiveBoundary()
        let second = adaptivePipeline(boundary: secondBoundary, unitTokens: 400, store: store)
        let result = try await second.summarize(selectedMeetingID: source.meetingID, source: source)
        XCTAssertFalse(result.bullets.isEmpty)
        let savedComplete = await store.snapshot()
        let complete = try XCTUnwrap(savedComplete)
        let calls = await secondBoundary.calls
        XCTAssertEqual(calls.filter { $0.marker == "NARRATIVE_INDEX" }.count, complete.identity.totalChunks - 1)
        XCTAssertEqual(complete.maps.count, complete.identity.totalChunks)
    }

    func testRecoveredIndexRejectsInventedOrMissingSourceReferencesBeforeGeneration() async throws {
        for removeCoverage in [false, true] {
            let source = adaptiveSource(count: 12)
            let store = AdaptiveCheckpointBoundary()
            let seedBoundary = AdaptiveBoundary()
            _ = try await adaptivePipeline(boundary: seedBoundary, unitTokens: 400, store: store)
                .summarize(selectedMeetingID: source.meetingID, source: source)
            try await store.corruptFirstMap(removeCoverage: removeCoverage)
            let boundary = AdaptiveBoundary()
            let pipeline = adaptivePipeline(boundary: boundary, unitTokens: 400, store: store)
            do {
                _ = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
                XCTFail("Persisted index references must be revalidated")
            } catch {
                XCTAssertEqual(error as? NarrativeSummaryError, removeCoverage ? .unsupportedEvidence : .invalidResponse)
            }
            let calls = await boundary.calls
            XCTAssertTrue(calls.isEmpty)
            let snapshot = await pipeline.snapshot()
            XCTAssertNil(snapshot.result)
            XCTAssertEqual(snapshot.phase, .failed)
        }
    }

    func testResumeIdentityBindsNotesModelAndBudgets() async throws {
        let source = adaptiveSource(count: 6)
        let store = AdaptiveCheckpointBoundary()
        _ = try await adaptivePipeline(boundary: AdaptiveBoundary(), unitTokens: 400, store: store)
            .summarize(selectedMeetingID: source.meetingID, source: source)
        for variant in 0..<3 {
            let boundary = AdaptiveBoundary()
            let changed = GroundedSummarySource(meetingID: source.meetingID, segments: source.segments,
                originalManualNotes: variant == 0 ? "Changed original notes." : source.originalManualNotes)
            let pipeline = adaptivePipeline(boundary: boundary, unitTokens: 400, store: store,
                revision: variant == 1 ? String(repeating: "b", count: 40) : String(repeating: "a", count: 40),
                outputTokens: variant == 2 ? 900 : 1_024)
            do {
                _ = try await pipeline.summarize(selectedMeetingID: changed.meetingID, source: changed)
                XCTFail("A changed job must require a fresh start")
            } catch { XCTAssertEqual(error as? SummaryCheckpointError, .identityMismatch) }
            let calls = await boundary.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }
}

private struct NeighborTopicDraft: Sendable {
    let topicID: Int
    let ids: [Int]
}

private actor NeighborTopicBoundary {
    private(set) var drafts: [NeighborTopicDraft] = []
    func generate(_ prompt: String) throws -> String {
        if prompt.hasPrefix("NARRATIVE_RECONCILE") {
            let rows = try adaptiveRows(prompt, marker: "TOPICS_JSON")
            return try adaptiveJSON(["groups": try rows.map { row -> [String: Any] in
                let id = try XCTUnwrap(row["id"] as? Int)
                return ["label": "Topic \(id)", "topic_ids": [id]]
            }])
        }
        if prompt.hasPrefix("NARRATIVE_REVIEW") { return #"{"supported":true,"issues":[]}"# }
        let ids = try adaptiveRows(prompt, marker: "SOURCE_UNITS_JSON").compactMap { $0["id"] as? Int }
        if prompt.hasPrefix("NARRATIVE_INDEX") {
            return try adaptiveJSON(["topics": ids.map { id -> [String: Any] in ["label": "Topic \(id)", "source_ids": [id]] }])
        }
        if prompt.hasPrefix("NARRATIVE_DRAFT") {
            let topicID = try XCTUnwrap((0..<3).first { prompt.contains("TOPIC_JSON: \"Topic \($0)\"") })
            drafts.append(.init(topicID: topicID, ids: ids))
            let paragraph: [String: Any] = ["text": "The group reviewed Project Alpha's release planning.",
                                            "source_ids": [topicID]]
            return try adaptiveJSON(["bullets": [paragraph], "overview": paragraph])
        }
        guard prompt.hasPrefix("NARRATIVE_OVERVIEW") else { throw NarrativeSummaryError.invalidResponse }
        return try adaptiveJSON(["text": "The discussion covered Project Alpha's release planning.", "source_ids": ids])
    }
}

private func adaptiveSource(count: Int, compact: Bool = false) -> GroundedSummarySource {
    let segments = (0..<count).map { index -> SummaryEvidenceSegment in
        let text: String
        if index == 0 { text = "The team initially planned to launch Project Alpha on Monday." }
        else if index == count - 1 { text = "After the security discussion, the team changed the Project Alpha launch from Monday to Friday." }
        else { text = "Project Alpha review \(index) examined migration risks and the supporting security evidence." }
        let start = Int64(index) * (compact ? 16_000 : 160_000)
        return .init(id: "source-\(index)", startSample: start, endSample: start + 16_000, text: text)
    }
    return .init(meetingID: UUID(), segments: segments, originalManualNotes: "Keep the release discussion connected.")
}

private func adaptivePipeline(boundary: AdaptiveBoundary, unitTokens: Int = 100,
                              store: AdaptiveCheckpointBoundary? = nil,
                              revision: String = String(repeating: "a", count: 40),
                              outputTokens: Int = 1_024,
                              workProgress: (@Sendable (SummaryWorkProgress) -> Void)? = nil) -> AdaptiveSummaryPipeline {
    let resume = store.map {
        SummaryPipelineResumeConfiguration(jobID: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            modelID: "test-narrative", modelSHA256: String(repeating: "c", count: 64), runtimeVersion: "test-runtime", checkpoints: $0)
    }
    return .init(modelRevision: revision, contextTokenLimit: 4_096, reservedOutputTokens: outputTokens,
        tokenizer: { prompt in
            let primary = (try? adaptiveRows(prompt, marker: "SOURCE_UNITS_JSON"))?.count ?? 0
            let context = (try? adaptiveRows(prompt, marker: "CONTEXT_UNITS_JSON"))?.count ?? 0
            // Synthetic phase-aware counts intentionally force multiple reading
            // and writing packets without depending on any downloaded model.
            if prompt.contains("TOPICS_JSON:") { return 100 + ((try? adaptiveRows(prompt, marker: "TOPICS_JSON"))?.count ?? 0) * 80 }
            if primary > 0 { return 100 + (primary + context) * unitTokens }
            return 20
        }, generator: { try await boundary.generate($0, schema: $1, maximum: $2) }, resume: resume,
        workProgress: workProgress)
}

private final class SummaryWorkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SummaryWorkProgress] = []
    func append(_ value: SummaryWorkProgress) { lock.withLock { storage.append(value) } }
    var values: [SummaryWorkProgress] { lock.withLock { storage } }
}

private struct AdaptiveCall: Sendable {
    let marker: String
    let ids: [Int]
    let maximum: Int
}

private actor AdaptiveBoundary {
    let holdSecondIndex: Bool
    let omitLastIndexedID: Bool
    let repairLateReview: Bool
    private(set) var held = false
    private(set) var calls: [AdaptiveCall] = []
    private var indexCount = 0
    init(holdSecondIndex: Bool = false, omitLastIndexedID: Bool = false, repairLateReview: Bool = false) {
        self.holdSecondIndex = holdSecondIndex; self.omitLastIndexedID = omitLastIndexedID
        self.repairLateReview = repairLateReview
    }

    func generate(_ prompt: String, schema: StructuredJSONSchema, maximum: Int) async throws -> String {
        let marker = ["NARRATIVE_INDEX", "NARRATIVE_RECONCILE", "NARRATIVE_DRAFT", "NARRATIVE_OVERVIEW",
                      "NARRATIVE_REPAIR", "NARRATIVE_REVIEW"].first { prompt.contains($0) } ?? "unknown"
        let rows = (try? adaptiveRows(prompt, marker: "SOURCE_UNITS_JSON")) ?? []
        let ids = rows.compactMap { $0["id"] as? Int }
        calls.append(.init(marker: marker, ids: ids, maximum: maximum))
        if marker == "NARRATIVE_INDEX" {
            indexCount += 1
            if holdSecondIndex, indexCount == 2 {
                held = true
                try await Task.sleep(for: .seconds(30))
            }
            let selected = omitLastIndexedID ? Array(ids.dropLast()) : ids
            let label = indexCount.isMultiple(of: 2) ? "Project Alpha release timing" : "Project Alpha launch"
            return try adaptiveJSON(["topics": selected.isEmpty ? [] : [["label": label, "source_ids": selected]]])
        }
        if marker == "NARRATIVE_RECONCILE" {
            let topics = try adaptiveRows(prompt, marker: "TOPICS_JSON")
            return try adaptiveJSON(["groups": [["label": "Project Alpha launch", "topic_ids": topics.compactMap { $0["id"] as? Int }]]])
        }
        if marker == "NARRATIVE_REVIEW" {
            if repairLateReview, prompt.contains("Condensed launch overview"), ids.contains(5) {
                return #"{"supported":false,"issues":["The source at unit 5 qualifies the conclusion."]}"#
            }
            return #"{"supported":true,"issues":[]}"#
        }
        guard let first = ids.first, let last = ids.last else { throw NarrativeSummaryError.invalidResponse }
        let references = first == last ? [first] : [first, last]
        var body: [String: Any] = [
            "text": "The team reviewed the launch plan and moved the release to Friday after considering security.",
            "source_ids": references
        ]
        if repairLateReview, marker == "NARRATIVE_OVERVIEW" { body["text"] = "Condensed launch overview with its current outcome." }
        if repairLateReview, marker == "NARRATIVE_REPAIR" { body["text"] = "Reviewed launch narrative preserves the source qualification." }
        if marker == "NARRATIVE_DRAFT" { return try adaptiveJSON(["overview": body, "bullets": [body]]) }
        return try adaptiveJSON(body)
    }
}

private actor AdaptiveCheckpointBoundary: SummaryCheckpointing {
    private var value: StoredSummaryCheckpoint?
    func save(_ map: SummaryMapCheckpoint, matching identity: SummaryCheckpointIdentity) throws {
        if let value, value.identity != identity { throw SummaryCheckpointError.identityMismatch }
        var maps = value?.maps ?? []
        guard map.index == maps.count else { throw SummaryCheckpointError.nonContiguousMap }
        maps.append(map)
        value = .init(identity: identity, maps: maps)
    }
    func load(matching identity: SummaryCheckpointIdentity) throws -> StoredSummaryCheckpoint? {
        if let value, value.identity != identity { throw SummaryCheckpointError.identityMismatch }
        return value
    }
    func snapshot() -> StoredSummaryCheckpoint? { value }
    func corruptFirstMap(removeCoverage: Bool) throws {
        guard let value, let first = value.maps.first else { throw SummaryCheckpointError.invalidInput }
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: first.mapJSON) as? [String: Any])
        if removeCoverage { object["topics"] = [] }
        else { object["topics"] = [["label": "Invented source", "source_ids": [999_999]]] }
        let corrupt = SummaryMapCheckpoint(index: first.index, chunkSHA256: first.chunkSHA256,
            mapJSON: try JSONSerialization.data(withJSONObject: object))
        self.value = .init(identity: value.identity, maps: [corrupt] + Array(value.maps.dropFirst()))
    }
}

private func adaptiveRows(_ prompt: String, marker: String) throws -> [[String: Any]] {
    guard let range = prompt.range(of: marker + ":\n") else { throw NarrativeSummaryError.invalidResponse }
    let tail = String(prompt[range.upperBound...])
    let json = tail.components(separatedBy: "\n\n").first ?? tail
    guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else {
        throw NarrativeSummaryError.invalidResponse
    }
    return value
}
private func adaptiveJSON(_ value: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
}
