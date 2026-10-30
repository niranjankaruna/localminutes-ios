import Foundation
import XCTest
@testable import LocalMinutesPersistence

/// Real owned files and real SQLite originals; boundary JSON is synthetic.
/// These cases prove neither inference nor semantic grounding of stored JSON.
@MainActor
final class SummaryCheckpointStoreTests: XCTestCase {
    func testNarrativeIndexesRoundTripOnlyUnderNarrativePromptIdentity() async throws {
        for version in ["narrative-v1", "narrative-v2", "narrative-v3"] {
            try await withSummaryCheckpointFixture { fixture in
                let identity = fixture.identity(promptVersion: version)
                let json = try JSONSerialization.data(withJSONObject: ["schema_version": 2,
                    "meeting_id": identity.meetingID.uuidString,
                    "topics": [["label": "Release preparation", "source_ids": [0, 1]]]])
                let map = SummaryMapCheckpoint(index: 0, chunkSHA256: String(repeating: "3", count: 64), mapJSON: json)
                try await fixture.checkpoints.save(map, matching: identity)
                let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
                let restored = try await reopened.load(matching: identity)
                XCTAssertEqual(restored?.maps, [map])
                await expectSummaryCheckpointError(.identityMismatch) {
                    _ = try await reopened.load(matching: fixture.identity(
                        promptVersion: version == "narrative-v1" ? "narrative-v2" : "narrative-v1"))
                }
                await expectSummaryCheckpointError(.identityMismatch) {
                    _ = try await reopened.load(matching: fixture.identity())
                }
                try await reopened.remove(jobID: identity.jobID, meetingID: identity.meetingID)
                await expectSummaryCheckpointError(.invalidInput) {
                    try await reopened.save(map, matching: fixture.identity())
                }
                await expectSummaryCheckpointError(.invalidInput) {
                    try await reopened.save(fixture.map(0), matching: identity)
                }
                try await fixture.assertOriginalsUnchanged()
            }
        }
    }

    func testLegacyCheckpointStaysReadableAndRemovableButCannotResumeNarrativeGeneration() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let legacy = fixture.identity()
            let map = fixture.map(0)
            try await fixture.checkpoints.save(map, matching: legacy)
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            let saved = try await reopened.load(matching: legacy)
            XCTAssertEqual(saved?.maps, [map])
            await expectSummaryCheckpointError(.identityMismatch) {
                _ = try await reopened.load(matching: fixture.identity(promptVersion: "narrative-v1"))
            }
            let count = try await reopened.savedMapCount(jobID: legacy.jobID, meetingID: legacy.meetingID)
            XCTAssertEqual(count, 1)
            try await reopened.remove(jobID: legacy.jobID, meetingID: legacy.meetingID)
            let removed = try await reopened.load(matching: fixture.identity(promptVersion: "narrative-v1"))
            XCTAssertNil(removed)
        }
    }

    func testLargerOutputBudgetAndCitationPayloadSurviveCheckpointReopen() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let identity = fixture.identity(contextTokenLimit: 32_768, reservedOutputTokens: 16_384)
            // Transport fixture only; semantic grounding remains the pipeline's responsibility.
            let map = fixture.map(0, text: String(repeating: "Original evidence. ", count: 3_000))
            XCTAssertGreaterThan(map.mapJSON.count, 65_536)
            try await fixture.checkpoints.save(map, matching: identity)
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            let saved = try await reopened.load(matching: identity)
            XCTAssertEqual(saved?.maps, [map])
            XCTAssertEqual(saved?.identity.reservedOutputTokens, 16_384)
            await expectSummaryCheckpointError(.identityMismatch) {
                _ = try await reopened.load(matching: fixture.identity(contextTokenLimit: 32_768, reservedOutputTokens: 8_192))
            }
        }
    }

    func testPublishedContextSizesSurviveCheckpointSaveAndReopen() async throws {
        for limit in [32_768, 131_072, 262_144] {
            try await withSummaryCheckpointFixture { fixture in
                let identity = fixture.identity(contextTokenLimit: limit)
                try await fixture.checkpoints.save(fixture.map(0), matching: identity)
                let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
                let saved = try await reopened.load(matching: identity)
                XCTAssertEqual(saved?.identity.contextTokenLimit, limit)
                XCTAssertEqual(saved?.maps, [fixture.map(0)])
                await expectSummaryCheckpointError(.identityMismatch) {
                    _ = try await reopened.load(matching: fixture.identity(contextTokenLimit: 4_096))
                }
            }
        }
    }

    func testPresentationFindsSavedProgressAfterReopenWithoutAcceptingAnotherMeeting() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let identity = fixture.identity()
            let missing = try await fixture.checkpoints.savedMapCount(jobID: identity.jobID, meetingID: identity.meetingID)
            XCTAssertEqual(missing, 0)
            try await fixture.checkpoints.save(fixture.map(0), matching: identity)
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            let count = try await reopened.savedMapCount(jobID: identity.jobID, meetingID: identity.meetingID)
            XCTAssertEqual(count, 1)
            await expectSummaryCheckpointError(.identityMismatch) {
                _ = try await reopened.savedMapCount(jobID: identity.jobID, meetingID: fixture.otherMeetingID)
            }
            try await fixture.assertOriginalsUnchanged()
        }
    }

    func testContiguousMapsSurviveReopenAndIdenticalReplayWithoutPublishingGeneratedDocument() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let first = fixture.map(0)
            let second = fixture.map(1)
            try await fixture.checkpoints.save(first, matching: fixture.identity())
            try await fixture.checkpoints.save(second, matching: fixture.identity())
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            try await reopened.save(first, matching: fixture.identity())
            let restored = try await reopened.load(matching: fixture.identity())
            XCTAssertEqual(restored?.identity, fixture.identity())
            XCTAssertEqual(restored?.maps, [first, second])
            XCTAssertEqual(restored?.nextMapIndex, 2)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.path))
            let files = try FileManager.default.contentsOfDirectory(at: fixture.directory,
                                                                   includingPropertiesForKeys: nil)
            XCTAssertFalse(files.isEmpty, "A new store instance must recover actual persistent bytes")
            try await fixture.assertOriginalsUnchanged()
        }
    }

    func testResumeRejectsChangedSourcePlanModelPromptOrBudgetAndPreservesOriginalCheckpoint() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let identity = fixture.identity()
            let first = fixture.map(0)
            try await fixture.checkpoints.save(first, matching: identity)
            let mismatches = [
                fixture.identity(meetingID: fixture.otherMeetingID),
                fixture.identity(sourceSHA256: String(repeating: "b", count: 64)),
                fixture.identity(planSHA256: String(repeating: "c", count: 64)),
                fixture.identity(modelID: "another-model"),
                fixture.identity(modelRevision: String(repeating: "d", count: 40)),
                fixture.identity(modelSHA256: String(repeating: "e", count: 64)),
                fixture.identity(runtimeVersion: "llama.cpp-other"),
                fixture.identity(promptVersion: "grounded-map-next"),
                fixture.identity(contextTokenLimit: 2_048),
                fixture.identity(reservedOutputTokens: 512),
                fixture.identity(totalChunks: 4)
            ]
            for changed in mismatches {
                await expectSummaryCheckpointError(.identityMismatch) {
                    _ = try await fixture.checkpoints.load(matching: changed)
                }
                await expectSummaryCheckpointError(.identityMismatch) {
                    try await fixture.checkpoints.save(fixture.map(1), matching: changed)
                }
            }
            let restored = try await fixture.checkpoints.load(matching: identity)
            XCTAssertEqual(restored?.maps, [first])
            try await fixture.assertOriginalsUnchanged()
        }
    }

    func testGapsConflictsMalformedAndOversizedMapsCannotOverwriteTheDurablePrefix() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let identity = fixture.identity()
            let first = fixture.map(0)
            try await fixture.checkpoints.save(first, matching: identity)
            await expectSummaryCheckpointError(.nonContiguousMap) {
                try await fixture.checkpoints.save(fixture.map(2), matching: identity)
            }
            await expectSummaryCheckpointError(.conflictingMap) {
                try await fixture.checkpoints.save(fixture.map(0, text: "A different exact source."), matching: identity)
            }
            await expectSummaryCheckpointError(.conflictingMap) {
                let changed = SummaryMapCheckpoint(index: 0, chunkSHA256: String(repeating: "f", count: 64),
                                                   mapJSON: first.mapJSON)
                try await fixture.checkpoints.save(changed, matching: identity)
            }
            await expectSummaryCheckpointError(.invalidInput) {
                try await fixture.checkpoints.save(.init(index: 1, chunkSHA256: String(repeating: "1", count: 64),
                    mapJSON: Data("not JSON".utf8)), matching: identity)
            }
            await expectSummaryCheckpointError(.invalidInput) {
                try await fixture.checkpoints.save(fixture.map(1, meetingID: fixture.otherMeetingID), matching: identity)
            }
            await expectSummaryCheckpointError(.limitExceeded) {
                try await fixture.checkpoints.save(.init(index: 1, chunkSHA256: String(repeating: "1", count: 64),
                    mapJSON: Data(repeating: 32, count: 1_048_577)), matching: identity)
            }
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            let restored = try await reopened.load(matching: identity)
            XCTAssertEqual(restored?.maps, [first])
            XCTAssertEqual(restored?.nextMapIndex, 1)
            try await fixture.assertOriginalsUnchanged()
        }
    }

    func testCancelledAppendAndScopedRemovalPreserveOtherJobsAndOriginalMeetingData() async throws {
        try await withSummaryCheckpointFixture { fixture in
            let identity = fixture.identity()
            let other = fixture.identity(jobID: UUID(), meetingID: fixture.otherMeetingID)
            try await fixture.checkpoints.save(fixture.map(0), matching: identity)
            try await fixture.checkpoints.save(fixture.map(0, meetingID: other.meetingID), matching: other)
            let append = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await fixture.checkpoints.save(fixture.map(1), matching: identity)
            }
            do {
                try await append.value
                XCTFail("A task cancelled before append must throw CancellationError")
            } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
            let prefix = try await fixture.checkpoints.load(matching: identity)
            XCTAssertEqual(prefix?.nextMapIndex, 1)
            await expectSummaryCheckpointError(.identityMismatch) {
                try await fixture.checkpoints.remove(jobID: identity.jobID, meetingID: fixture.otherMeetingID)
            }
            try await fixture.checkpoints.remove(jobID: identity.jobID, meetingID: identity.meetingID)
            try await fixture.checkpoints.remove(jobID: identity.jobID, meetingID: identity.meetingID)
            let reopened = try SummaryCheckpointStore(directoryURL: fixture.directory)
            let removed = try await reopened.load(matching: identity)
            let remaining = try await reopened.load(matching: other)
            XCTAssertNil(removed)
            XCTAssertEqual(remaining?.maps, [fixture.map(0, meetingID: other.meetingID)])
            try await fixture.assertOriginalsUnchanged()
        }
    }
}

@MainActor
private func expectSummaryCheckpointError(_ expected: SummaryCheckpointError,
    file: StaticString = #filePath, line: UInt = #line,
    operation: @MainActor () async throws -> Void) async {
    do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
    catch let error as SummaryCheckpointError { XCTAssertEqual(error, expected, file: file, line: line) }
    catch { XCTFail("Expected \(expected), received \(error)", file: file, line: line) }
}

@MainActor
private struct SummaryCheckpointFixture {
    let directory: URL
    let database: URL
    let store: SQLiteMeetingStore
    let checkpoints: SummaryCheckpointStore
    let jobID = UUID()
    let meetingID = UUID()
    let otherMeetingID = UUID()
    let segmentID = UUID()

    func identity(jobID: UUID? = nil, meetingID: UUID? = nil,
                  sourceSHA256: String = String(repeating: "0", count: 64),
                  planSHA256: String = String(repeating: "1", count: 64),
                  modelID: String = "synthetic-summary-model",
                  modelRevision: String = String(repeating: "a", count: 40),
                  modelSHA256: String = String(repeating: "2", count: 64),
                  runtimeVersion: String = "llama.cpp-b5046", promptVersion: String = "grounded-map-v1",
                  contextTokenLimit: Int = 4_096, reservedOutputTokens: Int = 1_024,
                  totalChunks: Int = 3) -> SummaryCheckpointIdentity {
        .init(jobID: jobID ?? self.jobID, meetingID: meetingID ?? self.meetingID,
              sourceSHA256: sourceSHA256, planSHA256: planSHA256, modelID: modelID,
              modelRevision: modelRevision, modelSHA256: modelSHA256, runtimeVersion: runtimeVersion,
              promptVersion: promptVersion, contextTokenLimit: contextTokenLimit,
              reservedOutputTokens: reservedOutputTokens, totalChunks: totalChunks)
    }

    func map(_ index: Int, text: String = "Original planning café — 原文 📝.",
             meetingID: UUID? = nil) -> SummaryMapCheckpoint {
        let json: [String: Any] = ["meeting_id": (meetingID ?? self.meetingID).uuidString,
            "summary_points": [["text": text, "evidence": [["source_id": "s\(index)",
                "start_sample": index * 16_000, "end_sample": (index + 1) * 16_000, "quote": text]]]],
            "decisions": [], "actions": []]
        // Constant synthetic values are JSON-serializable; this is a transport
        // fixture only, not a stand-in for the actual generation implementation.
        let bytes = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return .init(index: index, chunkSHA256: String(repeating: String(index + 3), count: 64), mapJSON: bytes)
    }

    var segment: StoredTranscriptSegment {
        .init(id: segmentID, meetingID: meetingID, sequence: 0, startSample: 0, endSample: 16_000,
              text: "Original planning café — 原文 📝.", modelRevision: "synthetic-asr")
    }
    var note: StoredManualNote {
        .init(meetingID: meetingID, text: "Original manual note — unchanged.", editRevision: 0,
              modifiedAt: Date(timeIntervalSince1970: 1_000))
    }
    func assertOriginalsUnchanged(file: StaticString = #filePath, line: UInt = #line) async throws {
        let rows = try await store.transcript(meetingID: meetingID)
        let notes = try await store.manualNote(meetingID: meetingID)
        let generated = try await store.generatedDocuments(meetingID: meetingID)
        XCTAssertEqual(rows, [segment], file: file, line: line)
        XCTAssertEqual(notes, note, file: file, line: line)
        XCTAssertTrue(generated.isEmpty, "Checkpoint progress must not publish a partial final document", file: file, line: line)
    }
}

@MainActor
private func withSummaryCheckpointFixture(
    _ body: @MainActor (SummaryCheckpointFixture) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let directory = root.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let database = root.appendingPathComponent("meetings.sqlite")
    let store = try SQLiteMeetingStore(databaseURL: database)
    let checkpoints = try SummaryCheckpointStore(directoryURL: directory)
    let fixture = SummaryCheckpointFixture(directory: directory, database: database,
                                           store: store, checkpoints: checkpoints)
    do {
        for id in [fixture.meetingID, fixture.otherMeetingID] {
            try await store.createMeeting(.init(id: id, title: "Synthetic checkpoint meeting",
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
        }
        try await store.appendFinalizedSegments([fixture.segment], to: fixture.meetingID)
        try await store.saveManualNote(fixture.note)
        try await body(fixture)
        try await store.close()
        try FileManager.default.removeItem(at: root)
    } catch {
        try? await store.close()
        try? FileManager.default.removeItem(at: root)
        throw error
    }
}
