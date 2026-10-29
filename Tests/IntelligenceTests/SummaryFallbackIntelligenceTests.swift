import Foundation
import XCTest
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

@MainActor
final class SummaryFallbackIntelligenceTests: XCTestCase {
    func testInvalidOutputFailsWithoutRetryFallbackOrSaveAndPreservesOriginals() async throws {
        let fixture = try await IntelligenceFixture.create()
        do {
            let runtime = IntelligenceBoundaryRuntime(replies: ["invalid JSON", try fixture.rawSummary()])
            let session = IntelligenceSession(store: fixture.store, models: fixture.models, admission: fixture.admission,
                manifest: fixture.manifest, runtimeLoader: { _ in runtime })
            do {
                _ = try await session.run(fixture.request(.summary))
                XCTFail("Invalid output must not be retried or replaced with transcript excerpts")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .invalidResponse) }
            XCTAssertEqual(session.snapshot().phase, .failed)
            XCTAssertNil(session.snapshot().document)
            XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
            let prompts = await runtime.prompts
            XCTAssertEqual(prompts.count, 1)
            let reopened = try SQLiteMeetingStore(databaseURL: fixture.database)
            let saved = try await reopened.generatedDocuments(meetingID: fixture.selected)
            let transcript = try await reopened.transcript(meetingID: fixture.selected)
            let notes = try await reopened.manualNote(meetingID: fixture.selected)
            try await reopened.close()
            XCTAssertTrue(saved.isEmpty)
            XCTAssertEqual(transcript, fixture.segments)
            XCTAssertEqual(notes, fixture.note)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
            try await fixture.closeAndRemove()
        } catch { try? await fixture.closeAndRemove(); throw error }
    }

    func testOversizedTranscriptFailsBeforeInferenceAndReleasesModel() async throws {
        let fixture = try await IntelligenceFixture.create()
        do {
            let runtime = IntelligenceBoundaryRuntime(replies: [try fixture.rawSummary()],
                contextTokenLimit: 32_768, tokenCount: 30_000, outputTokenLimit: 16_384)
            let session = IntelligenceSession(store: fixture.store, models: fixture.models, admission: fixture.admission,
                manifest: fixture.manifest, runtimeLoader: { _ in runtime })
            do {
                _ = try await session.run(fixture.request(.summary))
                XCTFail("Input plus expected output must fit before generation")
            } catch { XCTAssertEqual(error as? NarrativeSummaryError, .contextExceeded) }
            let prompts = await runtime.prompts
            XCTAssertTrue(prompts.isEmpty)
            let saved = try await fixture.store.generatedDocuments(meetingID: fixture.selected)
            XCTAssertTrue(saved.isEmpty)
            let unloaded = await runtime.unloaded
            XCTAssertTrue(unloaded)
            XCTAssertEqual(fixture.admission.snapshot().phase, .idle)
            try await fixture.closeAndRemove()
        } catch { try? await fixture.closeAndRemove(); throw error }
    }
}
