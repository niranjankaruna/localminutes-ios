import Foundation
import XCTest
@testable import LocalMinutesModels

@MainActor
final class RetiredSummarySelectionTests: XCTestCase {
    func testRetiredAppleSelectionIsExplicitlyUnequippedAndCanBeReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("localminutes-retired-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models", isDirectory: true),
            availableBytes: { _ in 8_000_000_000 }, downloader: { _, _ in XCTFail("Migration must not download a model") })
        let selectionRoot = root.appendingPathComponent("Selections", isDirectory: true)
        let choices = ModelSelectionStore(rootURL: selectionRoot, models: models,
            availableProfiles: [.llamaGGUF], canChangeSelection: { true })
        try await choices.clear(for: .summary)
        let pointer = selectionRoot.appendingPathComponent("summary.json")
        let old = Data(#"{"schemaVersion":1,"purpose":"summary","provider":"apple-intelligence-on-device"}"#.utf8)
        try old.write(to: pointer)
        let hasRecord = try await choices.hasSelectionRecord(for: .summary)
        let selected = try await choices.selected(for: .summary)
        let resolved = try await choices.resolve(for: .summary)
        XCTAssertTrue(hasRecord, "Do not silently restore the legacy default")
        XCTAssertNil(selected)
        XCTAssertNil(resolved)
        try await choices.clear(for: .summary)
        let replacement = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pointer)) as? [String: Any])
        XCTAssertEqual(replacement["unequipped"] as? Bool, true)
        XCTAssertNil(replacement["provider"])
        try Data(#"{"schemaVersion":1,"purpose":"summary","provider":"unknown"}"#.utf8).write(to: pointer)
        do { _ = try await choices.selected(for: .summary); XCTFail("Unknown providers must remain invalid") }
        catch { XCTAssertEqual(error as? ModelSelectionError, .invalidSelection) }
    }
}
