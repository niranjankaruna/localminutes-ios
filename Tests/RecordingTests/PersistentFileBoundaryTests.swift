import Foundation
import XCTest
import LocalMinutesCore
@testable import LocalMinutesRecording

// Real filesystem boundaries, with original public fixture bytes only. These
// macOS tests make no claim about iPhone protection classes or locked access.
final class PersistentFileBoundaryTests: XCTestCase {
    func testHardLinkedOutsideInodeIsRejectedBeforeAnyPolicyAttributeMutation() throws {
        let fixture = try PersistentBoundaryFixture()
        defer { fixture.cleanup() }
        let owned = fixture.root.appendingPathComponent("Owned", isDirectory: true)
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        for directory in [owned, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try setBoundaryMetadata(directory, permissions: 0o755, excluded: false)
        }
        let sentinel = outside.appendingPathComponent("source.txt")
        let original = Data("Original outside inode — Café 📝\n".utf8)
        try original.write(to: sentinel)
        try setBoundaryMetadata(sentinel, permissions: 0o640, excluded: false)
        let inside = owned.appendingPathComponent("hard-linked-source.txt")
        try FileManager.default.linkItem(at: sentinel, to: inside)
        let inode = try FileManager.default.attributesOfItem(atPath: sentinel.path)[.systemFileNumber] as? NSNumber
        let linkedInode = try FileManager.default.attributesOfItem(atPath: inside.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(inode)
        XCTAssertEqual(linkedInode, inode, "Fixture must be a real shared inode, not a copy")
        let rootBefore = try boundaryMetadata(owned)
        let outsideBefore = try boundaryMetadata(outside)
        let sentinelBefore = try boundaryMetadata(sentinel)
        let insideBefore = try boundaryMetadata(inside)

        XCTAssertThrowsError(try PersistentFilePolicy.protectDirectory(owned),
                             "A regular hard link cannot confer authority over its outside inode")

        XCTAssertEqual(try boundaryMetadata(owned), rootBefore,
                       "Whole-tree preflight must reject the alias before mutating even the owned root")
        XCTAssertEqual(try boundaryMetadata(outside), outsideBefore)
        XCTAssertEqual(try boundaryMetadata(sentinel), sentinelBefore,
                       "Outside permissions and direct backup attributes must remain exact")
        XCTAssertEqual(try boundaryMetadata(inside), insideBefore)
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
        XCTAssertEqual(try Data(contentsOf: inside), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: owned.path),
                       [inside.lastPathComponent])
    }

    func testCAFConstructorRejectsSymlinkedParentWithoutCreatingOutsideSession() throws {
        let fixture = try PersistentBoundaryFixture()
        defer { fixture.cleanup() }
        let owned = fixture.root.appendingPathComponent("Owned", isDirectory: true)
        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        for directory in [owned, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try setBoundaryMetadata(directory, permissions: 0o755, excluded: false)
        }
        let sentinel = outside.appendingPathComponent("source.txt")
        let original = Data("Original outside CAF-parent fixture\n".utf8)
        try original.write(to: sentinel)
        try setBoundaryMetadata(sentinel, permissions: 0o640, excluded: false)
        let link = owned.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        let sessionID = UUID()
        let proposed = link.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let outsideSession = outside.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let ownedBefore = try boundaryMetadata(owned)
        let outsideBefore = try boundaryMetadata(outside)
        let sentinelBefore = try boundaryMetadata(sentinel)
        let outsideEntriesBefore = try FileManager.default.contentsOfDirectory(atPath: outside.path).sorted()

        XCTAssertThrowsError(try SegmentCAFWriter(directory: proposed, sessionID: sessionID),
                             "Validate the owned parent before creating a recording directory")

        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideSession.path),
                       "Rejecting a path after creating its outside directory is already too late")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path).sorted(), outsideEntriesBefore)
        XCTAssertEqual(try boundaryMetadata(owned), ownedBefore)
        XCTAssertEqual(try boundaryMetadata(outside), outsideBefore)
        XCTAssertEqual(try boundaryMetadata(sentinel), sentinelBefore)
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), outside.path)
    }
}

private struct BoundaryMetadata: Equatable {
    let permissions: Int
    let directlyExcludedFromBackup: Bool?
}

private func boundaryMetadata(_ url: URL) throws -> BoundaryMetadata {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    let backup = try URL(fileURLWithPath: url.path)
        .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
    return BoundaryMetadata(permissions: mode, directlyExcludedFromBackup: backup)
}

private func setBoundaryMetadata(_ url: URL, permissions: Int, excluded: Bool) throws {
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    var item = URL(fileURLWithPath: url.path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = excluded
    try item.setResourceValues(values)
}

private struct PersistentBoundaryFixture {
    let parent: URL
    let root: URL
    let name: String

    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        name = "localminutes-persistent-boundary-\(UUID().uuidString)"
        root = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) {
        guard root.deletingLastPathComponent().standardizedFileURL.path == parent.path,
              root.lastPathComponent == name,
              root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            XCTFail("Unsafe persistent-boundary fixture cleanup", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned persistent-boundary cleanup failed", file: file, line: line) }
    }
}
