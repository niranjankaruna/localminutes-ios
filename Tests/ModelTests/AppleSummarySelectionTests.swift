import Foundation
import XCTest
@testable import LocalMinutesModels

@MainActor
final class AppleSummarySelectionTests: XCTestCase {
    func testBuiltInAppleSelectionPersistsWithoutDownloadingOrInstallingSyntheticWeights() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { _ in 8_000_000_000 }, downloader: { _, _ in XCTFail("The Apple model is system-managed; this must never download it") })
        let selectionRoot = root.appendingPathComponent("Selections", isDirectory: true)
        let choices = ModelSelectionStore(rootURL: selectionRoot, models: models,
            availableProfiles: [.llamaGGUF], canChangeSelection: { true })
        do { try await choices.selectAppleIntelligence(available: true) }
        catch { XCTFail("An available Apple on-device model must be a persistent summary choice: \(error)"); return }
        let reopened = ModelSelectionStore(rootURL: selectionRoot, models: models,
            availableProfiles: [.llamaGGUF], canChangeSelection: { true })
        XCTAssertTrue(try reopened.isAppleIntelligenceSelected())
        let hasRecord = try await reopened.hasSelectionRecord(for: .summary)
        XCTAssertTrue(hasRecord)
        let installed = try await models.installedManifests()
        XCTAssertTrue(installed.isEmpty, "Built-in choice must not manufacture an installed model/weight checksum")
        try await reopened.clear(for: .summary)
        XCTAssertFalse(try reopened.isAppleIntelligenceSelected())
    }

    func testUnavailableAppleModelAndBusyAdmissionCannotReplaceAnExistingChoice() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true), availableBytes: { _ in 8_000_000_000 })
        let choices = ModelSelectionStore(rootURL: root.appendingPathComponent("Selections", isDirectory: true),
            models: models, availableProfiles: [.llamaGGUF], canChangeSelection: { false })
        do { try await choices.selectAppleIntelligence(available: true); XCTFail("Active use must prevent changing the summary engine") }
        catch { XCTAssertEqual(error as? ModelSelectionError, .selectionInUse) }
        do { try await choices.selectAppleIntelligence(available: false); XCTFail("Unavailable system model must not be selected") }
        catch { XCTAssertEqual(error as? ModelSelectionError, .unavailableRuntime) }
        XCTAssertFalse(try choices.isAppleIntelligenceSelected())
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-apple-selection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
