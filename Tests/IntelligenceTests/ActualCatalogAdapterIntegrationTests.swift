import Foundation
import XCTest
import LocalMinutesModels
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// CI supplies every bundled catalogue variant in a separate native macOS job.
/// Missing artifacts fail this dedicated suite rather than silently skipping it.
@MainActor
final class ActualCatalogAdapterIntegrationTests: XCTestCase {
    func testReviewedCatalogVariantLoadsThroughDefaultRegistryGeneratesJSONAndUnloads() async throws {
        let environment = ProcessInfo.processInfo.environment
        let id = try XCTUnwrap(environment["LOCALMINUTES_CATALOG_VARIANT_ID"])
        let path = try XCTUnwrap(environment["LOCALMINUTES_CATALOG_MODEL_PATH"])
        let variant = try XCTUnwrap(ModelCatalog.variant(id: id))
        let configuration = try XCTUnwrap(variant.manifest.summaryConfiguration)
        let fixture = try await IntelligenceFixture.create(actualModel: URL(fileURLWithPath: path),
            manifestOverride: variant.manifest, importActualDirectoryDirectly: true)
        do {
            let lease = try await fixture.models.acquire(modelID: variant.manifest.modelID)
            let runtime = try await IntelligenceSession.loadPinnedRuntime(lease.model)
            let expectedType: String
            switch configuration.family {
            case .qwen25: expectedType = "Qwen25SummaryAdapter"
            case .qwen3: expectedType = "Qwen3SummaryAdapter"
            case .phi3: expectedType = "Phi3SummaryAdapter"
            case .phi4: expectedType = "Phi4SummaryAdapter"
            case .gemma3: expectedType = "Gemma3SummaryAdapter"
            case .gemma4: expectedType = "Gemma4SummaryAdapter"
            }
            XCTAssertTrue(String(reflecting: type(of: runtime)).hasSuffix(expectedType))
            do {
                let prompt = "Evidence: Leo will write the guide by Thursday. Return a JSON object with owner and due."
                let schema = StructuredJSONSchema(fields: [
                    .init(name: "owner", type: .string), .init(name: "due", type: .string)
                ])
                let count = try await runtime.promptTokenCount(prompt: prompt)
                XCTAssertGreaterThan(count, 0)
                XCTAssertLessThan(count, 4_096 - 192)
                let cancelled = Task { try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: 192) }
                cancelled.cancel()
                do { _ = try await cancelled.value; XCTFail("Cancelled adapter generated output") }
                catch is CancellationError { }
                // Reuse after cancellation exercises native memory clearing.
                for _ in 0..<2 {
                    let progress = CatalogAdapterProgress()
                    let json = try await runtime.generateJSON(prompt: prompt, schema: schema, maximumTokens: 192,
                        progress: { progress.record($0) })
                    XCTAssertEqual(progress.values.first, .promptTokens(completed: 0, total: count))
                    XCTAssertTrue(progress.values.contains(.promptTokens(completed: count, total: count)))
                    let responseCounts = progress.values.compactMap { value -> Int? in
                        if case .responseTokens(let completed, _) = value { return completed }
                        return nil
                    }
                    XCTAssertGreaterThan(responseCounts.count, 1)
                    XCTAssertEqual(responseCounts, (0..<responseCounts.count).map { $0 + 1 })
                    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
                    XCTAssertEqual(Set(object.keys), ["owner", "due"])
                    XCTAssertEqual(object["owner"] as? String, "Leo")
                    XCTAssertEqual(object["due"] as? String, "Thursday")
                }
                // Recorded Parakeet chunks have no speaker labels. Exercise a
                // longer, unlabeled transcript instead of only two named lines.
                let meeting = UUID()
                let sentences = [
                    "We are reviewing the mobile app today.",
                    "The download icon is missing from the blue button.",
                    "The summary fails when Apple Intelligence is selected.",
                    "The other model loads and then shows the same error.",
                    "We need to inspect the prompt and model output.",
                    "The recording was two minutes long and the transcript is saved.",
                    "We need to check the prompt budget and add a regression test.",
                    "We decided to fix the download icon in this release.",
                    "Please keep all meeting data on the device.",
                    "The final test should use the actual downloaded model.",
                    "We need to test summaries while the phone is locked.",
                    "No owner or deadline was assigned for these tasks."
                ]
                let source = GroundedSummarySource(meetingID: meeting,
                    segments: sentences.enumerated().map { index, text in
                        .init(id: UUID().uuidString, startSample: Int64(index * 80_000),
                              endSample: Int64((index + 1) * 80_000), text: text)
                    }, originalManualNotes: "")
                let pipeline = SummaryPipeline(modelRevision: variant.manifest.revision,
                    tokenizer: { try await runtime.promptTokenCount(prompt: $0) },
                    generator: { try await runtime.generateJSON(prompt: $0, schema: $1, maximumTokens: $2) })
                let recordedSummary = try await pipeline.summarize(selectedMeetingID: meeting, source: source)
                XCTAssertFalse(recordedSummary.summaryPoints.isEmpty)
                XCTAssertTrue(recordedSummary.actions.allSatisfy { $0.owner == nil && $0.due == nil },
                    "Unknown metadata must remain null, not fail the entire meeting after hallucinated assignments")
                await runtime.unload()
                do { _ = try await runtime.promptTokenCount(prompt: prompt); XCTFail("Unloaded adapter retained the model") }
                catch { XCTAssertEqual(error as? LocalSummaryRuntimeError, .modelUnavailable) }
            } catch {
                await runtime.unload()
                try? await fixture.models.release(lease)
                throw error
            }
            try await fixture.models.release(lease)
            // Exercise the same default composition used by the app, including
            // evidence validation, persistence and native teardown for both jobs.
            let session = IntelligenceSession(store: fixture.store, models: fixture.models,
                admission: fixture.admission, manifest: variant.manifest)
            let summary = try await session.run(fixture.request(.summary))
            XCTAssertEqual(summary.kind, .summary)
            let answer = try await session.run(fixture.request(.question("Who will write the guide?")))
            XCTAssertEqual(answer.kind, .questionAnswer)
            XCTAssertEqual(summary.modelRevision, variant.manifest.revision)
            XCTAssertEqual(answer.modelRevision, variant.manifest.revision)
            XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
            let current = try await fixture.models.current(modelID: variant.manifest.modelID)
            let installed = try XCTUnwrap(current)
            try await fixture.models.remove(modelID: variant.manifest.modelID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: installed.directoryURL.path))
            let removed = try await fixture.models.current(modelID: variant.manifest.modelID)
            XCTAssertNil(removed)
            try await fixture.closeAndRemove()
        } catch {
            try? await fixture.closeAndRemove()
            throw error
        }
    }
}

private final class CatalogAdapterProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SummaryGenerationProgress] = []
    func record(_ value: SummaryGenerationProgress) { lock.withLock { events.append(value) } }
    var values: [SummaryGenerationProgress] { lock.withLock { events } }
}
