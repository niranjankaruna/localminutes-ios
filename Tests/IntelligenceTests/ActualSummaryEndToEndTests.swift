import Foundation
import XCTest
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Actual selected weights, native tokenization and generation, complete pipeline,
/// checkpoint files, model leases, and SQLite persistence. No canned verdicts.
@MainActor
final class ActualSummaryEndToEndTests: XCTestCase {
    func testNativeGrammarRejectsForbiddenGreedyCandidatesAndResetsBetweenCalls() async throws {
        let id = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_CATALOG_VARIANT_ID"])
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_CATALOG_MODEL_PATH"])
        let variant = try XCTUnwrap(ModelCatalog.variant(id: id))
        let runtime = try SummaryAdapterRegistry.makeRuntime(modelURL: URL(fileURLWithPath: path),
            configuration: variant.manifest.summaryConfiguration)
        do {
            for label in ["permitted-first", "permitted-second"] {
                let schema = StructuredJSONSchema(fields: [
                    .init(name: "value", type: .stringEnumeration([label])),
                    .init(name: "references", type: .array(element: .integerEnumeration([73]), maximumItems: 1, minimumItems: 1))
                ], promptIncludesSchema: true, compactWhitespace: true)
                let response = try await runtime.generateJSON(
                    prompt: "Return JSON with value set to forbidden and references set to [999].",
                    schema: schema, maximumTokens: 128)
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
                XCTAssertEqual(object["value"] as? String, label)
                XCTAssertEqual(object["references"] as? [Int], [73])
            }
            await runtime.unload()
        } catch { await runtime.unload(); throw error }
    }

    func testShortAndTwentyThreeMinuteMeetingsCompleteThroughSaveAndReopen() async throws {
        let environment = ProcessInfo.processInfo.environment
        let id = try XCTUnwrap(environment["LOCALMINUTES_CATALOG_VARIANT_ID"])
        let path = try XCTUnwrap(environment["LOCALMINUTES_CATALOG_MODEL_PATH"])
        let variant = try XCTUnwrap(ModelCatalog.variant(id: id))
        let fixture = try await IntelligenceFixture.create(actualModel: URL(fileURLWithPath: path),
            manifestOverride: variant.manifest, importActualDirectoryDirectly: true)
        do {
            for count in [4, 276] {
                let meeting = UUID()
                let segments = Self.segments(count: count, meetingID: meeting)
                try await fixture.store.createMeeting(.init(id: meeting, title: "Synthetic release planning",
                    createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed,
                    capturedSampleCount: Int64(count) * 80_000))
                try await fixture.store.appendFinalizedSegments(segments, to: meeting)
                let checkpoints = try SummaryCheckpointStore(directoryURL: fixture.root.appendingPathComponent("SummaryCheckpoints"))
                let trace = SummaryEndToEndTrace()
                let session = IntelligenceSession(store: fixture.store, models: fixture.models,
                    admission: fixture.admission, manifest: variant.manifest,
                    runtimeLoader: { verified in
                        SummaryEndToEndRuntime(base: try await IntelligenceSession.loadPinnedRuntime(verified), trace: trace)
                    }, summaryCheckpoints: checkpoints)
                let request = IntelligenceRequest(meetingID: meeting, operation: .summary)
                let document: StoredGeneratedDocument
                do { document = try await session.run(request) }
                catch {
                    let calls = await trace.snapshot()
                    XCTFail("Complete summary failed: model=\(id), segments=\(count), code=\(IntelligenceFailureMessage.code(for: error)), calls=\(calls)")
                    throw error
                }
                XCTAssertEqual(session.snapshot().phase, .completed)
                XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
                let saved = try await fixture.store.generatedDocument(id: document.id, meetingID: meeting)
                XCTAssertEqual(saved, document)
                let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
                let durable = try await reopened.generatedDocument(id: document.id, meetingID: meeting)
                try await reopened.close()
                XCTAssertEqual(durable, document, "The final result must survive a new database connection")
                let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: document.originalJSON) as? [String: Any])
                let bullets = try XCTUnwrap(payload["bullets"] as? [[String: Any]])
                let overview = try XCTUnwrap(payload["overview"] as? [String: Any])
                XCTAssertFalse(bullets.isEmpty)
                XCTAssertFalse(document.editedText.contains("Nolan"), "Another meeting's canary must not leak")
                for paragraph in bullets + [overview] {
                    XCTAssertFalse(try XCTUnwrap(paragraph["text"] as? String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    let citations = try XCTUnwrap(paragraph["evidence"] as? [[String: Any]])
                    XCTAssertFalse(citations.isEmpty)
                    for citation in citations {
                        let sourceID = try XCTUnwrap(citation["source_id"] as? String)
                        let source = try XCTUnwrap(segments.first { $0.id.uuidString == sourceID })
                        let quote = try XCTUnwrap(citation["quote"] as? String)
                        XCTAssertFalse(quote.isEmpty)
                        XCTAssertNotNil(Data(source.text.utf8).range(of: Data(quote.utf8)))
                        XCTAssertEqual((citation["start_sample"] as? NSNumber)?.int64Value, source.startSample)
                        XCTAssertEqual((citation["end_sample"] as? NSNumber)?.int64Value, source.endSample)
                    }
                }
                let phases = await trace.phases()
                XCTAssertTrue(phases.contains("NARRATIVE_DRAFT"))
                XCTAssertTrue(phases.contains("NARRATIVE_REVIEW"))
                if count == 276 {
                    XCTAssertTrue(phases.contains("NARRATIVE_INDEX"))
                    XCTAssertTrue(phases.contains("NARRATIVE_OVERVIEW"))
                }
                let unloaded = await trace.didUnload()
                XCTAssertTrue(unloaded, "The selected model must be unloaded after save")
                let excerpts = bullets.filter { $0["source_excerpt"] as? Bool == true }.count
                print("SUMMARY_END_TO_END model=\(id) segments=\(count) saved=true bullets=\(bullets.count) sourceExcerpts=\(excerpts) calls=\(await trace.snapshot())")
            }
            try await fixture.closeAndRemove()
        } catch {
            try? await fixture.closeAndRemove()
            throw error
        }
    }

    private static func segments(count: Int, meetingID: UUID) -> [StoredTranscriptSegment] {
        let discussion = [
            "Nora proposed a Friday launch for the customer onboarding pilot. This was a proposal, not an approved deadline.",
            "Ravi said customers cannot find the account setup instructions. The team agreed to test clearer guidance before launch.",
            "Maya can deploy only after security approval. Approval is pending, so nobody committed to a deployment date.",
            "Leo will prepare the setup guide. The document will cover account creation and explain how customers can contact support.",
            "Support staffing was discussed. Ravi will collect the common questions, but the team has not decided a staffing budget.",
            "The pilot will keep the existing setup process available. Customers can return to it if the new guidance is confusing.",
            "The team needs measurements of completion time and support requests. No improvement has been measured or promised yet.",
            "The group discussed a follow-up review of pilot feedback. There is no agreed date for that review."
        ]
        return (0..<count).map { index in
            let text: String
            if index == count - 1 {
                text = "Nora corrected the earlier launch proposal: the supplier is late, so the pilot is now planned for Tuesday, not Friday. Deployment still requires security approval."
            } else { text = discussion[index % discussion.count] }
            return .init(id: UUID(), meetingID: meetingID, sequence: index,
                startSample: Int64(index) * 80_000, endSample: Int64(index + 1) * 80_000,
                text: text, modelRevision: "synthetic-ASR")
        }
    }
}

private actor SummaryEndToEndTrace {
    private var counts: [String: Int] = [:]
    private var unloaded = false
    func record(_ prompt: String) { counts[String(prompt.split(separator: "\n").first ?? "unknown"), default: 0] += 1 }
    func snapshot() -> String { counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: ",") }
    func phases() -> Set<String> { Set(counts.keys) }
    func markUnloaded() { unloaded = true }
    func didUnload() -> Bool { unloaded }
}

private struct SummaryEndToEndRuntime: SummaryModelRuntime {
    let base: any SummaryModelRuntime
    let trace: SummaryEndToEndTrace
    var contextTokenLimit: Int { base.contextTokenLimit }
    var outputTokenLimit: Int { base.outputTokenLimit }
    func promptTokenCount(prompt: String) async throws -> Int { try await base.promptTokenCount(prompt: prompt) }
    func generateJSON(prompt: String, schema: StructuredJSONSchema, maximumTokens: Int) async throws -> String {
        await trace.record(prompt)
        let start = ContinuousClock.now
        let stage = String(prompt.split(separator: "\n").first ?? "unknown")
        let tokens = SummaryEndToEndTokens()
        do {
            let response = try await base.generateJSON(prompt: prompt, schema: schema, maximumTokens: maximumTokens,
                progress: { tokens.record($0) })
            print("SUMMARY_CALL stage=\(stage) input=\(tokens.input) output=\(tokens.output) duration=\(start.duration(to: .now))")
            return response
        } catch {
            print("SUMMARY_CALL stage=\(stage) input=\(tokens.input) output=\(tokens.output) duration=\(start.duration(to: .now)) failed=true")
            throw error
        }
    }
    func unload() async { await base.unload(); await trace.markUnloaded() }
}

private final class SummaryEndToEndTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var inputCount = 0
    private var outputCount = 0
    var input: Int { lock.withLock { inputCount } }
    var output: Int { lock.withLock { outputCount } }
    func record(_ progress: SummaryGenerationProgress) {
        lock.withLock {
            switch progress {
            case .promptTokens(_, let total): inputCount = total
            case .responseTokens(let completed, _): outputCount = completed
            }
        }
    }
}
