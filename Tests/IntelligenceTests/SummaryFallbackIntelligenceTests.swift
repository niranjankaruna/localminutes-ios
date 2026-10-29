import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

@MainActor
final class SummaryFallbackIntelligenceTests: XCTestCase {
    func testRejectedRepairSavesExplicitOriginalExcerptsAndPreservesSources() async throws {
        let fixture = try await IntelligenceFixture.create()
        do {
            let claim = #"{"text":"The team approved an invented budget of 999 dollars.","source_ids":[0]}"#
            let draft = "{\"bullets\":[\(claim)],\"overview\":\(claim)}"
            let rejected = #"{"issues":["The original sources never mention a budget."]}"#
            let runtime = IntelligenceBoundaryRuntime(replies: [draft, rejected, claim, rejected])
            let session = IntelligenceSession(store: fixture.store, models: fixture.models, admission: fixture.admission,
                manifest: fixture.manifest, runtimeLoader: { _ in runtime })
            let document = try await session.run(fixture.request(.summary))
            XCTAssertEqual(session.snapshot().phase, .completed)
            XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
            XCTAssertFalse(document.editedText.contains("999"), "Rejected model claims must never be saved")
            XCTAssertTrue(document.editedText.contains("Transcript excerpt:"))
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: document.originalJSON) as? [String: Any])
            let bullets = try XCTUnwrap(payload["bullets"] as? [[String: Any]])
            XCTAssertFalse(bullets.isEmpty)
            XCTAssertTrue(bullets.allSatisfy { $0["source_excerpt"] as? Bool == true })
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            let saved = try await reopened.generatedDocument(id: document.id, meetingID: fixture.selected)
            let transcript = try await reopened.transcript(meetingID: fixture.selected)
            let notes = try await reopened.manualNote(meetingID: fixture.selected)
            try await reopened.close()
            XCTAssertEqual(saved, document)
            XCTAssertEqual(transcript, fixture.segments)
            XCTAssertEqual(notes, fixture.note)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
            try await fixture.closeAndRemove()
        } catch { try? await fixture.closeAndRemove(); throw error }
    }
}
