#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

// File-protection metadata checks only; simulator success is not locked-phone
// accessibility or actual device encryption evidence.
@MainActor
final class NativeModelStoragePolicyTests: XCTestCase {
    func testExistingPersistentModelsAndMetadataUseAfterFirstUnlockProtection() throws {
        let parent = FileManager.default.temporaryDirectory.standardizedFileURL
        let root = parent.appendingPathComponent("localminutes-protection-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("model/revision/installation", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fixture = nested.appendingPathComponent("original-fixture.txt")
        try Data("non-model fixture".utf8).write(to: fixture)
        try ModelStoragePolicy.protectPersistentDirectory(root)
        for url in [root, root.appendingPathComponent("model"), root.appendingPathComponent("model/revision"), nested, fixture] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let value = attributes[.protectionKey]
            let protection = (value as? FileProtectionType)?.rawValue ?? (value as? String)
            XCTAssertEqual(protection, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        }
    }
}
#endif
