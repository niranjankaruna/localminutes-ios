import Foundation
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesSummary
@testable import LocalMinutesIntelligence

/// Mandatory real selected-model composition. The default loader must accept
/// the reviewed installed Phi model; no runtime/model-response injection exists.
@MainActor
final class ActualSelectedModelIntelligenceTests: XCTestCase {
    func testActualSelectedPhiDefaultLoaderSavesSummaryAndGuideAnswerWithOriginalsPreserved() async throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["LOCALMINUTES_PHI_MODEL_PATH"])
        let revision = "a64113399c2f6b8ad3e11c394733a2ddadaa7f33"
        let repository = "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf"
        let name = "Phi-3-mini-4k-instruct-q4.gguf"
        let manifest = ModelManifest(modelID: "phi-3-mini-4k-instruct-q4", purpose: .summary,
            upstreamRepository: URL(string: repository)!, revision: revision,
            licenseIdentifier: "MIT", licenseNotice: "Phi-3-mini-4k-instruct, Copyright Microsoft Corporation. MIT License: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/blob/\(revision)/LICENSE",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary, fileName: name,
                byteCount: 2_393_231_072, sha256: "8a83c7fb9049a9b2e92266fa7ad04933bb53aa1e85136b7b30f1b8000ff2edef",
                downloadURL: URL(string: repository + "/resolve/" + revision + "/" + name)!,
                digestProvenance: .independentlyDownloaded)])
        // The fixture computes streaming SHA and the real installer independently
        // checks copied bytes; nominal Qwen fixture pins remain unchanged.
        let h = try await IntelligenceFixture.create(actualModel: URL(fileURLWithPath: path), manifestOverride: manifest)
        var documents: [StoredGeneratedDocument] = []
        do {
            let session = IntelligenceSession(store: h.store, models: h.models, admission: h.admission,
                manifest: manifest) // Actual DEFAULT native loader, never injected.
            for (stage, operation) in [("summary", IntelligenceOperation.summary),
                                        ("question", IntelligenceOperation.question("Who will write the guide?"))] {
                Self.log(stage, "begin")
                do {
                    let saved = try await session.run(h.request(operation))
                    documents.append(saved)
                    XCTAssertEqual(saved.meetingID, h.selected)
                    XCTAssertEqual(saved.modelRevision, revision)
                    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved.originalJSON) as? [String: Any])
                    XCTAssertEqual(object["meeting_id"] as? String, h.selected.uuidString)
                    XCTAssertFalse(String(decoding: saved.originalJSON, as: UTF8.self).contains("telescope"))
                    if stage == "summary" {
                        XCTAssertEqual(saved.kind, .summary)
                        try assertNarrativeFixtureSummary(saved, fixture: h, revision: revision)
                    } else {
                        XCTAssertEqual(saved.kind, .questionAnswer)
                        XCTAssertEqual(saved.question, "Who will write the guide?")
                        XCTAssertEqual(saved.promptVersion, "meeting-qa-v1")
                        XCTAssertEqual(object["status"] as? String, "supported_quote")
                        let evidence = try XCTUnwrap(object["evidence"] as? [[String: Any]])
                        XCTAssertEqual(evidence.count, 1)
                        XCTAssertEqual(evidence.first?["source_id"] as? String, h.segments[1].id.uuidString)
                        XCTAssertEqual(evidence.first?["asr_model_revision"] as? String, h.segments[1].modelRevision)
                        XCTAssertTrue((evidence.first?["quote"] as? String)?.contains("Leo") == true)
                        try self.validate(evidence, fixture: h)
                    }
                    XCTAssertEqual(h.admission.snapshot().phase, .idle)
                    Self.log(stage, "saved")
                } catch {
                    Self.log(stage, "failed", error: error)
                    XCTFail("Actual selected Phi \(stage) must succeed through the default loader: \(Self.safeError(error))")
                }
            }
            XCTAssertEqual(documents.count, 2, "Both actual operations must produce durable generated documents")
            XCTAssertEqual(h.admission.snapshot().phase, .idle)
            try await h.models.remove(modelID: manifest.modelID)
            let removed = try await h.models.current(modelID: manifest.modelID)
            XCTAssertNil(removed, "Native summary/QA teardown must release the actual selected installation")
            try await h.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: h.database)
            do {
                let stored = try await reopened.generatedDocuments(meetingID: h.selected)
                XCTAssertEqual(Set(stored.map(\.id)), Set(documents.map(\.id)))
                XCTAssertEqual(stored.count, 2)
                for document in documents {
                    let row = try await reopened.generatedDocument(id: document.id, meetingID: h.selected)
                    XCTAssertEqual(row, document)
                }
                let selected = try await reopened.transcript(meetingID: h.selected)
                let other = try await reopened.transcript(meetingID: h.other)
                let note = try await reopened.manualNote(meetingID: h.selected)
                let unselectedDocuments = try await reopened.generatedDocuments(meetingID: h.other)
                XCTAssertEqual(selected, h.segments); XCTAssertEqual(other, h.otherSegments)
                XCTAssertEqual(note, h.note); XCTAssertTrue(unselectedDocuments.isEmpty)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
            try await h.closeAndRemove()
        } catch { try? await h.closeAndRemove(); throw error }
    }

    private func validate(_ raw: Any?, fixture h: IntelligenceFixture) throws {
        let evidence = try XCTUnwrap(raw as? [[String: Any]])
        XCTAssertFalse(evidence.isEmpty)
        for item in evidence {
            let id = try XCTUnwrap(item["source_id"] as? String)
            let source = try XCTUnwrap(h.segments.first { $0.id.uuidString == id })
            let quote = try XCTUnwrap(item["quote"] as? String)
            XCTAssertFalse(quote.isEmpty)
            XCTAssertNotNil(Data(source.text.utf8).range(of: Data(quote.utf8)))
            XCTAssertEqual((item["start_sample"] as? NSNumber)?.int64Value, source.startSample)
            XCTAssertEqual((item["end_sample"] as? NSNumber)?.int64Value, source.endSample)
        }
    }

    private static func safeError(_ error: any Error) -> String {
        if let error = error as? IntelligenceSessionError { return "IntelligenceSessionError.\(error)" }
        return String(reflecting: type(of: error))
    }
    private static func log(_ stage: String, _ event: String, error: (any Error)? = nil) {
        let line = "SELECTED_PHI {\"stage\":\"\(stage)\",\"event\":\"\(event)\",\"error\":\"\(error.map(safeError) ?? "none")\"}\n"
        try? FileHandle.standardOutput.write(contentsOf: Data(line.utf8))
    }
}
