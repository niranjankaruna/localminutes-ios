import Foundation
import XCTest
@testable import LocalMinutesPersistence

// A store owns its DB, exact SQLite sidecars, and necessary parent attributes.
// Whole-app-root recursive privacy migration belongs to default App Services;
// opening a database URL does not authorize mutating unrelated sibling sources.
@MainActor
final class SQLitePolicyScopeTests: XCTestCase {
    func testOpeningAndReopeningSQLitePreservesUnrelatedSiblingBytesPermissionsAndBackupFlags() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let name = "localminutes-sqlite-policy-scope-\(UUID().uuidString)"
        let root = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer {
            if root.deletingLastPathComponent().standardizedFileURL.path == parent.path,
               root.lastPathComponent == name,
               root.resolvingSymlinksInPath().standardizedFileURL.path == root.path {
                do { try FileManager.default.removeItem(at: root) }
                catch { XCTFail("Owned SQLite policy-scope fixture cleanup failed") }
            } else { XCTFail("Unsafe SQLite policy-scope cleanup target") }
        }
        let source = root.appendingPathComponent("UnrelatedSourceSibling", isDirectory: true)
        let nested = source.appendingPathComponent("Keep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let originalFile = nested.appendingPathComponent("original-source.txt")
        let rootSibling = root.appendingPathComponent("unrelated-source.bin")
        let original = Data("Original source data — Café 📝\nNever change on database open.\n".utf8)
        let other = Data([0, 1, 2, 3, 255, 128, 64])
        try original.write(to: originalFile)
        try other.write(to: rootSibling)
        try setScopeMetadata(source, permissions: 0o750, excluded: false)
        try setScopeMetadata(nested, permissions: 0o755, excluded: false)
        try setScopeMetadata(originalFile, permissions: 0o640, excluded: false)
        try setScopeMetadata(rootSibling, permissions: 0o644, excluded: false)
        let observed = [source, nested, originalFile, rootSibling]
        let before = try observed.map { try scopeMetadata($0) }
        let sourceEntriesBefore = try FileManager.default.subpathsOfDirectory(atPath: source.path).sorted()

        func assertPreserved(file: StaticString = #filePath, line: UInt = #line) throws {
            for (url, metadata) in zip(observed, before) {
                XCTAssertEqual(try scopeMetadata(url), metadata,
                               "DB initialization must preserve unrelated sibling \(url.lastPathComponent)",
                               file: file, line: line)
            }
            XCTAssertEqual(try Data(contentsOf: originalFile), original, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: rootSibling), other, file: file, line: line)
            XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: source.path).sorted(),
                           sourceEntriesBefore, file: file, line: line)
        }

        let database = root.appendingPathComponent("meetings.sqlite")
        let record = MeetingRecord(id: UUID(), title: "Original SQLite policy scope fixture",
            createdAt: Date(timeIntervalSince1970: 1_234), recordingState: .completed,
            capturedSampleCount: 16_000)
        let store = try SQLiteMeetingStore(databaseURL: database)
        do {
            try assertPreserved()
            try await store.createMeeting(record)
            try await store.close()
        } catch {
            try? await store.close()
            throw error
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path))
        try assertPreserved()
        let reopened = try SQLiteMeetingStore(databaseURL: database)
        do {
            let actual = try await reopened.meeting(id: record.id)
            XCTAssertEqual(actual, record, "Narrowing privacy scope must retain real durable SQLite behavior")
            try assertPreserved()
            try await reopened.close()
        } catch {
            try? await reopened.close()
            throw error
        }
        try assertPreserved()
    }
}

private struct ScopeMetadata: Equatable {
    let permissions: Int
    let directlyExcludedFromBackup: Bool?
}

private func scopeMetadata(_ url: URL) throws -> ScopeMetadata {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    let backup = try URL(fileURLWithPath: url.path)
        .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    return ScopeMetadata(permissions: mode, directlyExcludedFromBackup: backup)
}

private func setScopeMetadata(_ url: URL, permissions: Int, excluded: Bool) throws {
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    var item = URL(fileURLWithPath: url.path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = excluded
    try item.setResourceValues(values)
}
