import Foundation
import XCTest
import LocalMinutesPersistence
@testable import LocalMinutesSummary

@MainActor
final class SummarySelectionRecoveryTests: XCTestCase {
    func testOutputLimitRetriesWithCompactReferencesAndValidatesExpandedOriginalEvidence() async throws {
        let meeting = UUID()
        let sentences = ["The release preserves cafe\u{301} and 📝 exactly.",
                         "We decided to ship on Friday.", "Leo: I will write the guide by Thursday."]
        let segment = SummaryEvidenceSegment(id: "original-source", startSample: 32_000, endSample: 3_840_000,
            text: sentences.joined(separator: " "))
        let source = GroundedSummarySource(meetingID: meeting, segments: [segment], originalManualNotes: "Original notes.")
        let calls = RecoveryCalls(response: #"{"summary_points":[0],"decisions":[1],"actions":[2]}"#)
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) })
        let result = try await pipeline.summarize(selectedMeetingID: meeting, source: source)
        let requests = await calls.requests
        XCTAssertEqual(requests.map(\.maximum), [1_024, 256])
        XCTAssertEqual(requests[1].schema.fields.map(\.name), ["summary_points", "decisions", "actions"])
        XCTAssertTrue(requests[1].schema.compactWhitespace, "Compact recovery must also bound whitespace-only output")
        XCTAssertTrue(requests[1].prompt.contains("Original notes."))
        XCTAssertFalse(requests[1].prompt.contains(segment.id), "The model need not regenerate original UUID/range metadata")
        for field in requests[1].schema.fields {
            guard case .array(let element, let maximum) = field.type,
                  case .integerEnumeration(let ids) = element else { return XCTFail("Compact output must use bounded references") }
            XCTAssertEqual(ids, [0, 1, 2]); XCTAssertEqual(maximum, 2)
        }
        XCTAssertEqual(result.summaryPoints.first.map { Data($0.text.utf8) }, Data(sentences[0].utf8))
        XCTAssertEqual(result.decisions.first?.text, sentences[1])
        let action = try XCTUnwrap(result.actions.first)
        XCTAssertEqual(action.task, sentences[2]); XCTAssertEqual(action.owner, "Leo"); XCTAssertEqual(action.due, "Thursday")
        for evidence in result.summaryPoints.flatMap(\.evidence) + result.decisions.flatMap(\.evidence) + result.actions.flatMap(\.evidence) {
            XCTAssertEqual(evidence.sourceID, segment.id)
            XCTAssertEqual(evidence.startSample, segment.startSample); XCTAssertEqual(evidence.endSample, segment.endSample)
            XCTAssertNotNil(Data(segment.text.utf8).range(of: Data(evidence.quote.utf8)))
        }
        let state = await pipeline.snapshot()
        XCTAssertEqual(state.phase, .completed)
        XCTAssertEqual(source.segments, [segment])
    }

    func testLongUnpunctuatedSpeechUsesCompactOutputImmediatelyWithoutDiscardingLaterText() async throws {
        let meeting = UUID()
        let text = String(repeating: "Original cafe\u{301} 📝 discussion without punctuation ", count: 140) + "distinctive ending"
        let segment = SummaryEvidenceSegment(id: "long-source", startSample: 0, endSample: 3_840_000, text: text)
        let calls = RecoveryCalls(response: #"{"summary_points":[0,1],"decisions":[],"actions":[]}"#)
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) })
        let result = try await pipeline.summarize(selectedMeetingID: meeting,
            source: .init(meetingID: meeting, segments: [segment], originalManualNotes: ""))
        let requests = await calls.requests
        XCTAssertEqual(requests.map(\.maximum), [256])
        XCTAssertTrue(try XCTUnwrap(requests.first).prompt.contains("distinctive ending"))
        XCTAssertFalse(result.summaryPoints.isEmpty)
        XCTAssertTrue(result.summaryPoints.allSatisfy { $0.text.utf8.count <= 4_096 })
        XCTAssertTrue(result.summaryPoints.flatMap(\.evidence).allSatisfy {
            $0.sourceID == segment.id && Data(text.utf8).range(of: Data($0.quote.utf8)) != nil
        })
    }

    func testCompactSelectionRejectsInventedIDsNonIntegerReferencesAndExtraGeneratedText() async throws {
        for response in [#"{"summary_points":[99],"decisions":[],"actions":[]}"#,
                         #"{"summary_points":[true],"decisions":[],"actions":[]}"#,
                         #"{"summary_points":[0],"decisions":[],"actions":[],"text":"invented"}"#] {
            let meeting = UUID()
            let calls = RecoveryCalls(response: response)
            let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
                generator: { try await calls.generate($0, schema: $1, maximum: $2) })
            do {
                _ = try await pipeline.summarize(selectedMeetingID: meeting, source: .init(meetingID: meeting,
                    segments: [.init(id: "source", startSample: 0, endSample: 16_000, text: "Original evidence.")], originalManualNotes: ""))
                XCTFail("An invalid compact response must not publish a summary")
            } catch is GroundedSummaryError { }
            let state = await pipeline.snapshot()
            XCTAssertEqual(state.phase, .failed); XCTAssertNil(state.result)
            let requests = await calls.requests
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testSecondOutputLimitStopsAfterOneRecoveryRatherThanRetryingForever() async throws {
        let meeting = UUID()
        let calls = RecoveryCalls(response: nil)
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) })
        do {
            _ = try await pipeline.summarize(selectedMeetingID: meeting, source: .init(meetingID: meeting,
                segments: [.init(id: "source", startSample: 0, endSample: 16_000, text: "Original evidence.")], originalManualNotes: ""))
            XCTFail("Repeated native output failure must remain a failure")
        } catch { XCTAssertEqual(error as? LocalSummaryRuntimeError, .outputLimitExceeded) }
        let requests = await calls.requests
        XCTAssertEqual(requests.map(\.maximum), [1_024, 256])
    }

    func testRecoveredMapIsCheckpointedInTheOriginalFormatAndResumesWithoutAnotherModelCall() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = parent.appendingPathComponent("summary-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        guard root.deletingLastPathComponent() == parent, root.resolvingSymlinksInPath() == root else {
            return XCTFail("Refuse a checkpoint fixture outside its owned temporary root")
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let meeting = UUID(), job = UUID()
        let checkpoints = try SummaryCheckpointStore(directoryURL: root.appendingPathComponent("checkpoints", isDirectory: true))
        let resume = SummaryPipelineResumeConfiguration(jobID: job, modelID: "selection-fixture",
            modelSHA256: String(repeating: "b", count: 64), runtimeVersion: "fixture-runtime", checkpoints: checkpoints)
        let source = GroundedSummarySource(meetingID: meeting, segments: [
            .init(id: "original-source", startSample: 0, endSample: 16_000, text: "Original evidence.")
        ], originalManualNotes: "")
        let calls = RecoveryCalls(response: #"{"summary_points":[0],"decisions":[],"actions":[]}"#)
        let original = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) }, resume: resume)
        let first = try await original.summarize(selectedMeetingID: meeting, source: source)
        let data = try Data(contentsOf: root.appendingPathComponent("checkpoints/\(job.uuidString).json"))
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let checkpoint = try XCTUnwrap(envelope["checkpoint"] as? [String: Any])
        let maps = try XCTUnwrap(checkpoint["maps"] as? [[String: Any]])
        let mapData = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(maps.first?["mapJSON"] as? String)))
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: mapData) as? [String: Any])
        let points = try XCTUnwrap(stored["summary_points"] as? [[String: Any]])
        XCTAssertEqual(points.first?["text"] as? String, "Original evidence.")
        XCTAssertNotNil(points.first?["evidence"])
        let restored = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { _, _, _ in XCTFail("A validated recovered map must not rerun inference"); throw LocalSummaryRuntimeError.generationFailed },
            resume: resume)
        let replay = try await restored.summarize(selectedMeetingID: meeting, source: source)
        XCTAssertEqual(replay, first)
    }

    func testCompactBatchesKeepEverySourceChoiceIncludingTheLastOne() async throws {
        let meeting = UUID()
        let text = (0..<140).map { "Original source sentence \($0)." }.joined(separator: " ")
        let calls = SelectionBatchCalls()
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) })
        let result = try await pipeline.summarize(selectedMeetingID: meeting, source: .init(meetingID: meeting,
            segments: [.init(id: "source", startSample: 0, endSample: 3_840_000, text: text)], originalManualNotes: ""))
        let offered = await calls.offered
        XCTAssertEqual(offered.count, 2)
        XCTAssertEqual(offered.flatMap { $0 }, (0..<140).map { Int64($0) })
        XCTAssertTrue(result.summaryPoints.contains { $0.text == "Original source sentence 139." })
    }

    func testCancellationAfterOriginalFailureDoesNotStartCompactRecovery() async throws {
        let meeting = UUID()
        let calls = RecoveryCalls(response: #"{"summary_points":[0],"decisions":[],"actions":[]}"#, holdOriginal: true)
        let pipeline = SummaryPipeline(modelRevision: String(repeating: "a", count: 40), tokenizer: { _ in 20 },
            generator: { try await calls.generate($0, schema: $1, maximum: $2) })
        let operation = Task { try await pipeline.summarize(selectedMeetingID: meeting, source: .init(meetingID: meeting,
            segments: [.init(id: "source", startSample: 0, endSample: 16_000, text: "Original evidence.")], originalManualNotes: "")) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await calls.waiting), ContinuousClock.now < deadline { await Task.yield() }
        let waiting = await calls.waiting
        XCTAssertTrue(waiting)
        operation.cancel()
        await calls.release()
        do { _ = try await operation.value; XCTFail("Cancelled work must not publish recovered content") }
        catch is CancellationError { }
        let requests = await calls.requests
        XCTAssertEqual(requests.count, 1)
        let state = await pipeline.snapshot()
        XCTAssertEqual(state.phase, .cancelled); XCTAssertNil(state.result)
    }
}

private actor RecoveryCalls {
    struct Request: Sendable {
        let prompt: String
        let schema: StructuredJSONSchema
        let maximum: Int
    }
    private let response: String?
    private let holdOriginal: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var waiting = false
    private(set) var requests: [Request] = []
    init(response: String?, holdOriginal: Bool = false) { self.response = response; self.holdOriginal = holdOriginal }
    func generate(_ prompt: String, schema: StructuredJSONSchema, maximum: Int) async throws -> String {
        requests.append(.init(prompt: prompt, schema: schema, maximum: maximum))
        if schema.fields.first?.name == "meeting_id" {
            if holdOriginal, !released { waiting = true; await withCheckedContinuation { continuation = $0 } }
            throw LocalSummaryRuntimeError.outputLimitExceeded
        }
        guard let response else { throw LocalSummaryRuntimeError.outputLimitExceeded }
        return response
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor SelectionBatchCalls {
    private(set) var offered: [[Int64]] = []
    func generate(_ prompt: String, schema: StructuredJSONSchema, maximum: Int) throws -> String {
        guard let field = schema.fields.first, case .array(let type, _) = field.type,
              case .integerEnumeration(let ids) = type, let last = ids.last else { throw GroundedSummaryError.invalidJSON }
        offered.append(ids)
        return "{\"summary_points\":[\(last)],\"decisions\":[],\"actions\":[]}"
    }
}
