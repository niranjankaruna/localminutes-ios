import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
@testable import LocalMinutesIntelligence

/// Dedicated actual-model job only. No runtime injection, skipped environment,
/// network request, mocked output, answer correction or device claim.
@MainActor
final class ActualIntelligenceCompositionTests: XCTestCase {
    func testDefaultPinnedQwenServiceSavesSummaryAndSelectedAnswerThenReleasesActualInstallation() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_QWEN_MODEL_PATH"],
            "Dedicated actual-model job must supply the reviewed model; missing it fails")
        let available = try ModelStoragePolicy.availableBytes(at: FileManager.default.temporaryDirectory)
        XCTAssertGreaterThanOrEqual(available, 2_500_000_000, "Two owned model copies need reviewed temporary headroom")
        guard available >= 2_500_000_000 else { throw ModelInstallationError.insufficientSpace }
        // Fixture verifies all 1,117,320,736 bytes and the reviewed SHA before
        // the real manager imports/copies and verifies the artifact independently.
        let h = try await IntelligenceFixture.create(actualModel: URL(fileURLWithPath: path))
        var stage = "summary"
        do {
            let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                                              manifest: h.manifest) // mandatory DEFAULT actual loader
            let summary = try await session.run(h.request(.summary))
            let summaryJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: summary.originalJSON) as? [String: Any])
            let decisions = try XCTUnwrap(summaryJSON["decisions"] as? [[String: Any]])
            XCTAssertTrue(decisions.contains { ($0["text"] as? String)?.contains("prototype") == true
                && ($0["text"] as? String)?.contains("Friday") == true })
            let actions = try XCTUnwrap(summaryJSON["actions"] as? [[String: Any]])
            let action = try XCTUnwrap(actions.first { ($0["task"] as? String)?.contains("guide") == true })
            XCTAssertEqual(action["owner"] as? String, "Leo"); XCTAssertEqual(action["due"] as? String, "Thursday")
            XCTAssertEqual(summary.modelRevision, "91cad51170dc346986eccefdc2dd33a9da36ead9")
            XCTAssertEqual(summary.promptVersion, "grounded-map-v1")
            stage = "question-answer"
            let answer = try await session.run(h.request(.question("Who will write the guide?")))
            let answerJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: answer.originalJSON) as? [String: Any])
            XCTAssertEqual(answerJSON["status"] as? String, "supported_quote")
            let evidence = try XCTUnwrap(answerJSON["evidence"] as? [[String: Any]])
            XCTAssertTrue(evidence.contains { $0["source_id"] as? String == h.segments[1].id.uuidString
                && ($0["quote"] as? String)?.contains("guide") == true })
            XCTAssertFalse(String(decoding: answer.originalJSON, as: UTF8.self).contains("telescope"))
            XCTAssertFalse(String(decoding: summary.originalJSON, as: UTF8.self).contains("telescope"))
            stage = "persistence-verification"
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            try await h.models.remove(modelID: h.manifest.modelID)
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            let savedSummary = try await reopened.generatedDocument(id: summary.id, meetingID: h.selected)
            let savedAnswer = try await reopened.generatedDocument(id: answer.id, meetingID: h.selected)
            let transcript = try await reopened.transcript(meetingID: h.selected)
            let note = try await reopened.manualNote(meetingID: h.selected)
            let other = try await reopened.generatedDocuments(meetingID: h.other)
            XCTAssertEqual(savedSummary, summary); XCTAssertEqual(savedAnswer, answer)
            XCTAssertEqual(transcript, h.segments); XCTAssertEqual(note, h.note); XCTAssertTrue(other.isEmpty)
            try await reopened.close(); try await h.closeAndRemove()
        } catch {
            // Fixed synthetic corpus only; never include model output, prompt,
            // private paths, user source text or arbitrary error descriptions.
            print("SYNTHETIC_INTELLIGENCE_FAILURE stage=\(stage)")
            try? await h.closeAndRemove(); throw error
        }
    }
}
