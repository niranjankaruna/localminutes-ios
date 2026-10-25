#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

/// Real SQLite, generated-document validation and heavy admission. The runtime
/// boundary supplies fixed synthetic JSON; this does not claim Apple inference.
@MainActor
final class NativeAppleSummaryTests: XCTestCase {
    func testAppleSummaryCompositionSavesWithExplicitSystemProvenanceAndNoInstalledWeights() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-apple-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { _ in 8_000_000_000 }, downloader: { _, _ in XCTFail("Apple summaries must not request model downloads") })
        let meeting = UUID(), sourceID = UUID()
        let original = "The team approved the launch."
        try await store.createMeeting(.init(id: meeting, title: "Synthetic Apple summary", createdAt: Date(timeIntervalSince1970: 1),
            recordingState: .completed, capturedSampleCount: 16_000))
        let segment = StoredTranscriptSegment(id: sourceID, meetingID: meeting, sequence: 0, startSample: 0,
            endSample: 16_000, text: original, modelRevision: "synthetic-asr")
        try await store.appendFinalizedSegments([segment], to: meeting)
        let runtime = AppleSummaryBoundaryRuntime(meetingID: meeting, sourceID: sourceID)
        let admission = HeavyModelAdmission()
        let revision = "apple-system-ios-27.0.1"
        let session = IntelligenceSession(store: store, models: models, admission: admission,
            appleSystemRevision: revision, systemRuntimeLoader: { runtime })
        do {
            let document = try await session.run(.init(meetingID: meeting, operation: .summary))
            XCTAssertEqual(document.modelRevision, revision, "OS-managed provenance must not pretend to be a pinned weight digest")
            let durable = try await store.generatedDocument(id: document.id, meetingID: meeting)
            XCTAssertEqual(durable, document)
            let originals = try await store.transcript(meetingID: meeting)
            XCTAssertEqual(originals, [segment])
            let installed = try await models.installedManifests()
            XCTAssertTrue(installed.isEmpty)
            XCTAssertEqual(admission.snapshot().phase, .idle)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
        } catch { XCTFail("An available system-runtime boundary must complete the real summary/storage flow: \(error)") }
        try await store.close()
    }
}

private actor AppleSummaryBoundaryRuntime: IntelligenceRuntime {
    let meetingID: UUID
    let sourceID: UUID
    private(set) var unloaded = false
    init(meetingID: UUID, sourceID: UUID) { self.meetingID = meetingID; self.sourceID = sourceID }
    func promptTokenCount(prompt: String) async throws -> Int { max(1, prompt.utf8.count / 4) }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        let object: [String: Any] = ["meeting_id": meetingID.uuidString,
            "summary_points": [["text": "The team approved the launch.", "evidence": [[
                "source_id": sourceID.uuidString, "start_sample": 0, "end_sample": 16_000,
                "quote": "The team approved the launch."
            ]]]], "decisions": [], "actions": []]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    func unload() async { unloaded = true }
}
#endif
