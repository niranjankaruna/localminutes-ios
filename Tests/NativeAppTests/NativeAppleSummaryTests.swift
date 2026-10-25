#if os(iOS)
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import XCTest
@testable import LocalMinutes

/// Real SQLite, generated-document validation and heavy admission. The runtime
/// boundary supplies fixed synthetic JSON; this does not claim Apple inference.
@MainActor
final class NativeAppleSummaryTests: XCTestCase {
    func testPersistedAppleSelectionBindsSystemSessionOnFreshStartupWithoutDefaultWeights() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let root = parent.appendingPathComponent("localminutes-apple-startup-\(UUID().uuidString)", isDirectory: true)
        let original = try LocalMinutesServices(rootURL: root)
        try await original.modelSelections.selectAppleIntelligence(available: true)
        try await original.store.close()
        let reopened = try LocalMinutesServices(rootURL: root)
        await reopened.initialize()
        do {
            let session = try XCTUnwrap(reopened.intelligence, "Persisted system selection must bind a real system session")
            let fields = Mirror(reflecting: session).children
            XCTAssertNil(fields.first(where: { $0.label == "manifest" })?.value as? ModelManifest,
                "System selection must never restore the default downloaded model")
            XCTAssertEqual(fields.first(where: { $0.label == "systemModelRevision" })?.value as? String,
                AppleSummaryModel.currentSystemRevision)
            XCTAssertEqual(reopened.summaryInstalled, AppleFoundationRuntime.availability() == .available)
        } catch { XCTFail("System startup composition failed: \(error)") }
        try await reopened.store.close()
        guard root.deletingLastPathComponent() == parent, root.resolvingSymlinksInPath() == root else {
            XCTFail("Refuse cleanup outside the owned fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }

    func testBundledV3DescriptorUsesTheSameValidatedPackAsNativeAdapterTests() throws {
        let pack = try XCTUnwrap(BundledParakeetPacks.manifests.first, "The actual app must include its browseable v3 model descriptor")
        XCTAssertEqual(try ParakeetModelPack.configuration(for: pack).decoderContract, "parakeet-tdt-v3")
        XCTAssertEqual(pack.artifacts.count, 21)
        XCTAssertEqual(pack.revision, "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe")
    }

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
#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Exercise actual framework schema construction using the pipeline's
            // real nested schema; only model generation remains a boundary double.
            var compiler = AppleGenerationSchemaCompiler()
            _ = try GenerationSchema(root: compiler.object(schema.fields), dependencies: [])
        }
#endif
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
