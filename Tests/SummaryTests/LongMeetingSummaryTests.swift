import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesSummary

/// Full pipeline, source validation, context, consolidation, and real checkpoint
/// storage. Model/tokenizer boundaries are synthetic; these are scale and
/// orchestration checks, not evidence of on-phone inference speed or quality.
@MainActor
final class LongMeetingSummaryTests: XCTestCase {
    func testTwoHourTranscriptReachesEverySectionAndCombinesEarlyMiddleAndLateFindings() async throws {
        let source = twoHourSource()
        let original = source
        let calls = LongMeetingBoundary()
        let pipeline = makePipeline(calls: calls)
        let result = try await pipeline.summarize(selectedMeetingID: source.meetingID, source: source)
        let observed = await calls.observed()
        XCTAssertGreaterThan(observed.mapCalls, 128, "A long meeting must not hit the old aggregate/map ceiling")
        let expected = Set(source.segments.flatMap { $0.text.split(separator: ".").map {
            Data((String($0).trimmingCharacters(in: .whitespacesAndNewlines) + ".").utf8)
        } })
        XCTAssertEqual(observed.sentences, expected, "Every original sentence must reach actual model input")
        XCTAssertTrue(observed.contexts.dropFirst().contains { $0.contains("Monday") })
        XCTAssertTrue(observed.contexts.last?.contains("Project Alpha") == true)
        XCTAssertTrue(observed.finalContexts.contains { $0.contains("Monday") && $0.contains("Friday") },
                      "The final pass must see early decisions alongside their later revision")
        XCTAssertLessThanOrEqual(result.summaryPoints.count + result.decisions.count + result.actions.count, 48)
        XCTAssertTrue(result.decisions.contains { $0.text.contains("Friday") })
        XCTAssertTrue(result.actions.contains { $0.task.contains("review") })
        let ids = Set((result.summaryPoints.flatMap(\.evidence) + result.decisions.flatMap(\.evidence)
            + result.actions.flatMap(\.evidence)).map(\.sourceID))
        XCTAssertTrue(ids.contains("source-0"))
        XCTAssertTrue(ids.contains("source-720"))
        XCTAssertTrue(ids.contains("source-1439"))
        XCTAssertEqual(source, original)
    }

    func testTwoHourInterruptedJobRebuildsContextFromMoreThan128SavedSectionsWithoutRegeneratingThem() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("long-meeting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        guard root.deletingLastPathComponent() == parent, root.resolvingSymlinksInPath() == root else {
            return XCTFail("Refuse a long-meeting fixture outside its owned temporary root")
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let source = twoHourSource(), job = UUID()
        let directory = root.appendingPathComponent("checkpoints", isDirectory: true)
        let store = try SummaryCheckpointStore(directoryURL: directory)
        let interrupted = LongMeetingBoundary(holdMap: 150)
        let first = makePipeline(calls: interrupted, checkpoints: store, job: job)
        let operation = Task { try await first.summarize(selectedMeetingID: source.meetingID, source: source) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !(await interrupted.waiting), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let waiting = await interrupted.waiting
        XCTAssertTrue(waiting)
        operation.cancel(); await interrupted.release()
        do { _ = try await operation.value; XCTFail("An interrupted long meeting must not publish a partial summary") }
        catch is CancellationError { }
        let saved = try await store.savedMapCount(jobID: job, meetingID: source.meetingID)
        XCTAssertEqual(saved, 149)
        let stopped = await first.snapshot()
        XCTAssertEqual(stopped.phase, .cancelled); XCTAssertNil(stopped.result)
        let reopened = try SummaryCheckpointStore(directoryURL: directory)
        let remaining = LongMeetingBoundary()
        let resumed = makePipeline(calls: remaining, checkpoints: reopened, job: job)
        let result = try await resumed.summarize(selectedMeetingID: source.meetingID, source: source)
        let allSaved = try await reopened.savedMapCount(jobID: job, meetingID: source.meetingID)
        let observed = await remaining.observed()
        XCTAssertEqual(observed.mapCalls, allSaved - saved)
        XCTAssertTrue(observed.contexts.first?.contains("Project Alpha") == true,
                      "The first new section must recover its running context from validated cached maps")
        XCTAssertTrue(observed.finalContexts.contains { $0.contains("Monday") && $0.contains("Friday") })
        XCTAssertTrue(result.decisions.contains { $0.text.contains("Friday") })
    }

    func testOversizedParagraphSplitsWithoutLosingUnicodeBytesSourceIdentityOrAudioRanges() async throws {
        let text = String(repeating: "Original cafe\u{301} 📝 discussion stays intact. ", count: 140)
        let original = SummaryEvidenceSegment(id: "original-source", startSample: 32_000, endSample: 115_200_000, text: text)
        let planner = SummaryChunkPlanner(contextTokenLimit: 512, reservedOutputTokens: 64,
            promptPrefix: "Policy", splitOversizedSegments: true, tokenizer: { $0.utf8.count })
        let chunks = try await planner.plan([original])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(Data(chunks.flatMap(\.segments).map(\.text).joined().utf8), Data(text.utf8))
        for chunk in chunks {
            XCTAssertEqual(chunk.segments.count, 1)
            XCTAssertEqual(chunk.segments[0].id, original.id)
            XCTAssertEqual(chunk.segments[0].startSample, original.startSample)
            XCTAssertEqual(chunk.segments[0].endSample, original.endSample)
            XCTAssertLessThan(chunk.promptTokenCount + chunk.reservedOutputTokens, 512)
        }
    }

    private func makePipeline(calls: LongMeetingBoundary, checkpoints: SummaryCheckpointStore? = nil,
                              job: UUID = UUID()) -> SummaryPipeline {
        let resume = checkpoints.map { SummaryPipelineResumeConfiguration(jobID: job, modelID: "long-meeting-fixture",
            modelSHA256: String(repeating: "b", count: 64), runtimeVersion: "fixture-runtime", checkpoints: $0) }
        return SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { try await longMeetingTokenCount($0) },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) }, resume: resume)
    }

    private func twoHourSource() -> GroundedSummarySource {
        let segments = (0..<1_440).map { index -> SummaryEvidenceSegment in
            let text: String
            switch index {
            case 0: text = "Maya: We decided to launch Project Alpha on Monday."
            case 720: text = "The launch will wait for the security review. Leo: I will finish the review by Thursday."
            case 1_439: text = "We changed the Project Alpha launch from Monday to Friday."
            default: text = "Project Alpha checkpoint \(index) records the current migration review."
            }
            return .init(id: "source-\(index)", startSample: Int64(index) * 80_000,
                         endSample: Int64(index + 1) * 80_000, text: text)
        }
        return .init(meetingID: UUID(), segments: segments, originalManualNotes: "Keep the release and security review connected.")
    }
}

private func longMeetingRows(_ prompt: String, marker: String) throws -> [[String: Any]] {
    guard let start = prompt.range(of: marker + ":\n") else { throw GroundedSummaryError.invalidJSON }
    let tail = prompt[start.upperBound...]
    let json = String(tail).components(separatedBy: "\n\n").first ?? String(tail)
    guard let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else {
        throw GroundedSummaryError.invalidJSON
    }
    return rows
}

private func longMeetingTokenCount(_ prompt: String) async throws -> Int {
    if prompt.contains("FINDINGS_JSON:\n") { return 600 + (try longMeetingRows(prompt, marker: "FINDINGS_JSON").count) * 100 }
    if prompt.contains("SENTENCES_JSON:\n") { return 500 + (try longMeetingRows(prompt, marker: "SENTENCES_JSON").count) * 80 }
    let rows = try longMeetingRows(prompt, marker: "EVIDENCE_JSON")
    let context = prompt.range(of: "MEETING_CONTEXT_JSON:\n").map { start in
        String(prompt[start.upperBound...]).components(separatedBy: "\n\n")[0].utf8.count / 4
    } ?? 0
    return 600 + rows.count * 480 + context
}

private actor LongMeetingBoundary {
    private let holdMap: Int?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false
    private var mapCalls = 0
    private var sentences: Set<Data> = []
    private var contexts: [String] = []
    private var finalContexts: [String] = []
    init(holdMap: Int? = nil) { self.holdMap = holdMap }

    func generate(_ prompt: String, schema: StructuredJSONSchema, maximum: Int) async throws -> String {
        if prompt.contains("FINDINGS_JSON:\n") {
            let rows = try longMeetingRows(prompt, marker: "FINDINGS_JSON")
            finalContexts.append(prompt)
            guard case .array(_, let keep) = schema.fields[0].type else { throw GroundedSummaryError.invalidJSON }
            let prioritized = rows.enumerated().sorted { first, second in
                func priority(_ row: [String: Any]) -> Int {
                    let text = row["excerpt"] as? String ?? ""
                    return text.contains("Monday") || text.contains("Friday") || text.contains("security") || text.contains("I will") ? 1 : 0
                }
                let a = priority(first.element), b = priority(second.element)
                return a != b ? a > b : first.offset < second.offset
            }
            let ids = prioritized.prefix(keep).compactMap { $0.element["id"] as? Int }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["keep": ids]), as: UTF8.self)
        }
        let rows = try longMeetingRows(prompt, marker: "SENTENCES_JSON")
        mapCalls += 1
        if let holdMap, mapCalls == holdMap, !released { waiting = true; await withCheckedContinuation { releaseWaiter = $0 } }
        try Task.checkCancellation()
        contexts.append(try longMeetingRows(prompt, marker: "MEETING_CONTEXT_JSON").description)
        for row in rows { if let text = row["text"] as? String { sentences.insert(Data(text.utf8)) } }
        let ids = rows.compactMap { $0["id"] as? Int }
        let points = Array(Set([ids.first, ids.last].compactMap { $0 })).sorted()
        let decisions = rows.filter {
            let text = $0["text"] as? String ?? ""; return text.contains("decided") || text.contains("changed")
        }.prefix(2).compactMap { $0["id"] as? Int }
        let actions = rows.filter { ($0["text"] as? String ?? "").contains("I will") }.prefix(2).compactMap { $0["id"] as? Int }
        return String(decoding: try JSONSerialization.data(withJSONObject:
            ["summary_points": points, "decisions": decisions, "actions": actions]), as: UTF8.self)
    }
    func release() { released = true; releaseWaiter?.resume(); releaseWaiter = nil }
    func observed() -> (mapCalls: Int, sentences: Set<Data>, contexts: [String], finalContexts: [String]) {
        (mapCalls, sentences, contexts, finalContexts)
    }
}
