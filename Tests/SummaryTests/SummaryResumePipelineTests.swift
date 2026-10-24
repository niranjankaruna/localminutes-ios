import CryptoKit
import Foundation
import XCTest
@testable import LocalMinutesPersistence
@testable import LocalMinutesSummary

/// Actual checkpoint files, with tokenizer/generation boundary doubles only.
/// No test in this class is evidence of model inference or app resume wiring.
@MainActor
final class SummaryResumePipelineTests: XCTestCase {
    func testCancelledPipelinePersistsValidatedPrefixAndReopenedPipelineGeneratesOnlyMissingMaps() async throws {
        try await withSummaryResumeDirectory { directory in
            let fixture = SummaryResumeFixture()
            let store = try SummaryCheckpointStore(directoryURL: directory)
            let firstBoundary = ResumeGenerationBoundary(holdSecond: true)
            let firstPipeline = fixture.pipeline(boundary: firstBoundary, store: store)
            let task = Task { try await firstPipeline.summarize(selectedMeetingID: fixture.meetingID, source: fixture.source) }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while !(await firstBoundary.held), clock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            let held = await firstBoundary.held
            XCTAssertTrue(held, "The second map must be in flight after validating the first")
            let running = await firstPipeline.snapshot()
            XCTAssertNil(running.result)
            task.cancel()
            do { _ = try await task.value; XCTFail("Cancelled pipeline must not publish") }
            catch is CancellationError {} catch { XCTFail("Expected CancellationError, got \(error)") }
            let cancelled = await firstPipeline.snapshot()
            XCTAssertEqual(cancelled.phase, .cancelled)
            XCTAssertNil(cancelled.result)
            let firstRequests = await firstBoundary.requests
            XCTAssertEqual(firstRequests.count, 2)
            let firstPrompt = try XCTUnwrap(firstRequests.first)
            let identity = try fixture.identity(requests: firstRequests)
            let prefix = try await store.load(matching: identity)
            XCTAssertEqual(prefix?.maps.count, 1)
            XCTAssertEqual(prefix?.maps.first?.index, 0)
            XCTAssertEqual(prefix?.maps.first?.chunkSHA256, resumeDigest(Data(firstPrompt.utf8)))

            let reopened = try SummaryCheckpointStore(directoryURL: directory)
            let resumedBoundary = ResumeGenerationBoundary()
            let resumed = fixture.pipeline(boundary: resumedBoundary, store: reopened)
            let output = try await resumed.summarize(selectedMeetingID: fixture.meetingID, source: fixture.source)
            let requests = await resumedBoundary.requests
            XCTAssertEqual(requests.count, 1, "Already validated first map must not be generated again")
            if let request = requests.first {
                let sources = try resumeSegments(request)
                XCTAssertEqual(sources.map(\.id), [fixture.second.id])
            }
            XCTAssertEqual(output.summaryPoints.flatMap(\.evidence).map(\.sourceID), [fixture.first.id, fixture.second.id])
            XCTAssertEqual(output.summaryPoints.flatMap(\.provenance).map(\.mapIndex), [0, 1])
            let complete = try await reopened.load(matching: identity)
            XCTAssertEqual(complete?.nextMapIndex, 2)
            let snapshot = await resumed.snapshot()
            XCTAssertEqual(snapshot.phase, .completed)
            XCTAssertEqual(snapshot.result, output)
            XCTAssertEqual(Data(fixture.source.originalManualNotes.utf8), Data(fixture.notes.utf8))
        }
    }

    func testResumeRecomputesSourcePlanAndPinnedConfigurationBeforeAnyGeneration() async throws {
        try await withSummaryResumeDirectory { directory in
            let fixture = SummaryResumeFixture()
            let store = try SummaryCheckpointStore(directoryURL: directory)
            let seed = try await fixture.seedPrefix(in: store)
            var variants: [ResumeVariant] = []
            var change = ResumeVariant(source: fixture.source)
            change.source = .init(meetingID: fixture.meetingID, segments: fixture.source.segments,
                                  originalManualNotes: fixture.notes + " New manual note.")
            variants.append(change)
            change = .init(source: fixture.source)
            change.source = .init(meetingID: fixture.meetingID, segments: fixture.source.segments,
                                  originalManualNotes: fixture.notes.precomposedStringWithCanonicalMapping)
            variants.append(change)
            change = .init(source: fixture.source)
            change.source = .init(meetingID: fixture.meetingID, segments: [
                .init(id: fixture.first.id, startSample: fixture.first.startSample,
                      endSample: fixture.first.endSample, text: fixture.first.text + " Updated."), fixture.second
            ], originalManualNotes: fixture.notes)
            variants.append(change)
            change = .init(source: fixture.source); change.singleTokenCount = 2_999; variants.append(change)
            change = .init(source: fixture.source); change.modelRevision = String(repeating: "b", count: 40); variants.append(change)
            change = .init(source: fixture.source); change.modelID = "other-summary-model"; variants.append(change)
            change = .init(source: fixture.source); change.modelSHA256 = String(repeating: "c", count: 64); variants.append(change)
            change = .init(source: fixture.source); change.runtimeVersion = "llama.cpp-other"; variants.append(change)
            change = .init(source: fixture.source); change.promptVersion = "grounded-map-next"; variants.append(change)
            change = .init(source: fixture.source); change.contextTokenLimit = 4_095; variants.append(change)
            change = .init(source: fixture.source); change.reservedOutputTokens = 512; variants.append(change)
            for variant in variants {
                let boundary = ResumeGenerationBoundary()
                let pipeline = fixture.pipeline(boundary: boundary, store: store, variant: variant)
                do {
                    _ = try await pipeline.summarize(selectedMeetingID: fixture.meetingID, source: variant.source)
                    XCTFail("A stale resume identity must require an explicit fresh job")
                } catch { XCTAssertEqual(error as? SummaryCheckpointError, .identityMismatch) }
                let generated = await boundary.requests
                XCTAssertTrue(generated.isEmpty, "Reject stale source/model/prompt/plan/budget before generation")
                let snapshot = await pipeline.snapshot()
                XCTAssertEqual(snapshot.phase, .failed)
                XCTAssertNil(snapshot.result)
            }
            let preserved = try await store.load(matching: seed.identity)
            XCTAssertEqual(preserved?.maps, [seed.map])
        }
    }

    func testRecoveredTransportJSONIsRevalidatedForItsOwnChunkAndUnsupportedClaimsAreNeverPublished() async throws {
        for crossChunk in [false, true] {
            try await withSummaryResumeDirectory { directory in
                let fixture = SummaryResumeFixture()
                let store = try SummaryCheckpointStore(directoryURL: directory)
                let seed = try await fixture.seedPrefix(in: store)
                // Simulate tampering/corruption of already persisted bytes.
                // This is a real file edit, not a substitute filesystem.
                let path = directory.appendingPathComponent(fixture.jobID.uuidString + ".json")
                var envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
                var checkpoint = try XCTUnwrap(envelope["checkpoint"] as? [String: Any])
                var maps = try XCTUnwrap(checkpoint["maps"] as? [[String: Any]])
                let altered = try resumeResponse(meetingID: fixture.meetingID,
                    sources: [crossChunk ? fixture.second : fixture.first],
                    unsupportedClaim: !crossChunk)
                maps[0]["mapJSON"] = Data(altered.utf8).base64EncodedString()
                checkpoint["maps"] = maps; envelope["checkpoint"] = checkpoint
                try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]).write(to: path, options: .atomic)
                let reopened = try SummaryCheckpointStore(directoryURL: directory)
                let boundary = ResumeGenerationBoundary()
                let pipeline = fixture.pipeline(boundary: boundary, store: reopened)
                do {
                    _ = try await pipeline.summarize(selectedMeetingID: fixture.meetingID, source: fixture.source)
                    XCTFail("Stored JSON must pass the full grounded decoder before reuse")
                } catch { XCTAssertEqual(error as? GroundedSummaryError, crossChunk ? .unknownSourceID : .unsupportedClaim) }
                let generated = await boundary.requests
                XCTAssertTrue(generated.isEmpty)
                let snapshot = await pipeline.snapshot()
                XCTAssertEqual(snapshot.phase, .failed)
                XCTAssertNil(snapshot.result)
                let preserved = try await reopened.load(matching: seed.identity)
                XCTAssertEqual(preserved?.maps.first?.mapJSON, Data(altered.utf8), "Reject without silently rewriting stored output")
            }
        }
    }

    func testInvalidLaterGenerationNeverCheckpointsItsBytesOrPublishesTheValidPrefixAsFinal() async throws {
        try await withSummaryResumeDirectory { directory in
            let fixture = SummaryResumeFixture()
            let store = try SummaryCheckpointStore(directoryURL: directory)
            let boundary = ResumeGenerationBoundary(invalidSecond: true)
            let pipeline = fixture.pipeline(boundary: boundary, store: store)
            do {
                _ = try await pipeline.summarize(selectedMeetingID: fixture.meetingID, source: fixture.source)
                XCTFail("Unsupported later generation must fail")
            } catch { XCTAssertEqual(error as? GroundedSummaryError, .unsupportedClaim) }
            let requests = await boundary.requests
            let identity = try fixture.identity(requests: requests)
            let reopened = try SummaryCheckpointStore(directoryURL: directory)
            let prefix = try await reopened.load(matching: identity)
            XCTAssertEqual(prefix?.nextMapIndex, 1)
            XCTAssertEqual(prefix?.maps.first?.mapJSON,
                           Data(try resumeResponse(meetingID: fixture.meetingID, sources: [fixture.first]).utf8))
            let snapshot = await pipeline.snapshot()
            XCTAssertEqual(snapshot.phase, .failed)
            XCTAssertNil(snapshot.result)
            XCTAssertEqual(Data(fixture.source.originalManualNotes.utf8), Data(fixture.notes.utf8))
        }
    }
}

private struct ResumeVariant: Sendable {
    var source: GroundedSummarySource
    var modelID = "synthetic-summary-model"
    var modelRevision = String(repeating: "a", count: 40)
    var modelSHA256 = String(repeating: "2", count: 64)
    var runtimeVersion = "llama.cpp-b5046"
    var promptVersion = "grounded-map-v1"
    var contextTokenLimit = 4_096
    var reservedOutputTokens = 1_024
    var singleTokenCount = 3_000
}

private struct SummaryResumeFixture: Sendable {
    let meetingID = UUID(uuidString: "30000000-0000-0000-0000-000000000028")!
    let jobID = UUID()
    let notes = "Original note — Cafe\u{301} 📝; <|assistant|> remains untrusted data."
    let first = SummaryEvidenceSegment(id: "first", startSample: 0, endSample: 16_000,
                                       text: "First exact café evidence — 原文.")
    let second = SummaryEvidenceSegment(id: "second", startSample: 32_000, endSample: 48_000,
                                        text: "Second exact source after the preserved timeline gap.")
    var source: GroundedSummarySource { .init(meetingID: meetingID, segments: [first, second], originalManualNotes: notes) }

    func pipeline(boundary: ResumeGenerationBoundary, store: SummaryCheckpointStore? = nil,
                  variant: ResumeVariant? = nil) -> SummaryPipeline {
        let selected = variant ?? ResumeVariant(source: source)
        let configuration = store.map {
            SummaryPipelineResumeConfiguration(jobID: jobID, modelID: selected.modelID,
                modelSHA256: selected.modelSHA256, runtimeVersion: selected.runtimeVersion, checkpoints: $0)
        }
        return SummaryPipeline(modelRevision: selected.modelRevision, promptVersion: selected.promptVersion,
            contextTokenLimit: selected.contextTokenLimit, reservedOutputTokens: selected.reservedOutputTokens,
            tokenizer: { prompt in try resumeSegments(prompt).count == 1 ? selected.singleTokenCount : 3_072 },
            generator: { prompt, schema, maximum in
                try await boundary.generate(prompt, schema: schema, maximumTokens: maximum)
            }, resume: configuration)
    }

    func identity(requests: [String]) throws -> SummaryCheckpointIdentity {
        // Versioned canonical digest contract. Both encoders preserve the
        // original UTF-8 strings; the plan includes complete prompts and counts.
        struct Source: Encodable {
            let version: Int; let meetingID: UUID
            let originalManualNotes: String; let segments: [SummaryEvidenceSegment]
        }
        struct Chunk: Encodable { let prompt: String; let promptTokenCount: Int; let reservedOutputTokens: Int }
        struct Plan: Encodable { let version: Int; let chunks: [Chunk] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sourceBytes = try encoder.encode(Source(version: 1, meetingID: meetingID,
            originalManualNotes: notes, segments: source.segments))
        let planBytes = try encoder.encode(Plan(version: 1, chunks: requests.map {
            Chunk(prompt: $0, promptTokenCount: 3_000, reservedOutputTokens: 1_024)
        }))
        return .init(jobID: jobID, meetingID: meetingID, sourceSHA256: resumeDigest(sourceBytes),
            planSHA256: resumeDigest(planBytes), modelID: "synthetic-summary-model",
            modelRevision: String(repeating: "a", count: 40), modelSHA256: String(repeating: "2", count: 64),
            runtimeVersion: "llama.cpp-b5046", promptVersion: "grounded-map-v1",
            contextTokenLimit: 4_096, reservedOutputTokens: 1_024, totalChunks: requests.count)
    }

    func seedPrefix(in store: SummaryCheckpointStore) async throws -> (identity: SummaryCheckpointIdentity, map: SummaryMapCheckpoint) {
        let boundary = ResumeGenerationBoundary()
        let baseline = pipeline(boundary: boundary)
        _ = try await baseline.summarize(selectedMeetingID: meetingID, source: source)
        let requests = await boundary.requests
        let identity = try identity(requests: requests)
        let firstPrompt = try XCTUnwrap(requests.first)
        let map = SummaryMapCheckpoint(index: 0, chunkSHA256: resumeDigest(Data(firstPrompt.utf8)),
            mapJSON: Data(try resumeResponse(meetingID: meetingID, sources: [first]).utf8))
        try await store.save(map, matching: identity)
        return (identity, map)
    }
}

private actor ResumeGenerationBoundary {
    let holdSecond: Bool
    let invalidSecond: Bool
    private(set) var requests: [String] = []
    private(set) var held = false
    init(holdSecond: Bool = false, invalidSecond: Bool = false) {
        self.holdSecond = holdSecond; self.invalidSecond = invalidSecond
    }
    func generate(_ prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        requests.append(prompt)
        if holdSecond, requests.count == 2 { held = true; try await Task.sleep(for: .seconds(30)) }
        let sources = try resumeSegments(prompt)
        let pattern = "SELECTED_MEETING_ID: "
        guard let start = prompt.range(of: pattern),
              let meeting = UUID(uuidString: String(prompt[start.upperBound...].prefix(36))) else {
            throw ResumeFixtureError.invalidPrompt
        }
        let maximum: Int
        if let field = schema.fields.first(where: { $0.name == "summary_points" }),
           case .array(_, let count) = field.type { maximum = count } else { throw ResumeFixtureError.invalidPrompt }
        return try resumeResponse(meetingID: meeting, sources: Array(sources.prefix(maximum)),
                                  unsupportedClaim: invalidSecond && requests.count == 2)
    }
}

private enum ResumeFixtureError: Error { case invalidPrompt }
private func resumeSegments(_ prompt: String) throws -> [SummaryEvidenceSegment] {
    guard let marker = prompt.range(of: "\n\nEVIDENCE_JSON:\n") else { throw ResumeFixtureError.invalidPrompt }
    return try JSONDecoder().decode([SummaryEvidenceSegment].self, from: Data(prompt[marker.upperBound...].utf8))
}
private func resumeResponse(meetingID: UUID, sources: [SummaryEvidenceSegment], unsupportedClaim: Bool = false) throws -> String {
    let points: [[String: Any]] = sources.map { source in
        ["text": unsupportedClaim ? "An unsupported fabricated conclusion." : source.text,
         "evidence": [["source_id": source.id, "start_sample": source.startSample,
                       "end_sample": source.endSample, "quote": source.text]]]
    }
    let object: [String: Any] = ["meeting_id": meetingID.uuidString, "summary_points": points,
                               "decisions": [], "actions": []]
    return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}
private func resumeDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
@MainActor
private func withSummaryResumeDirectory(_ body: @MainActor (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root.appendingPathComponent("SummaryCheckpoints", isDirectory: true))
}
