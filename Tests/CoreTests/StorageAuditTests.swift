import Foundation
import XCTest
import LocalMinutesCore

/// Actual temporary filesystem and Foundation attributes, not invented physical
/// protection. macOS/Simulator results never assert an iPhone protection pass.
final class StorageAuditTests: XCTestCase {
    func testActualOwnedTreeReportsFixedRolesCountsAndOSMetadataWithoutRewritingFiles() throws {
        try fixture { f in
            let before = try f.snapshot()
            let report = StorageAuditInspector.inspect(rootURL: f.root)
            XCTAssertEqual(report.status, .complete)
            XCTAssertEqual(report.schemaVersion, 1)
            XCTAssertEqual(report.inspectedItemCount, f.items.count)
            XCTAssertEqual(report.groups.reduce(0) { $0 + $1.itemCount }, f.items.count)
            for role in Set(f.roles.values) {
                let expected = f.roles.values.filter { $0 == role }.count
                XCTAssertEqual(report.groups.filter { $0.role == role }.reduce(0) { $0 + $1.itemCount }, expected,
                    "Each fixed role must count only the actual owned files/directories")
            }
            let expectedGroups = try f.independentGroups()
            XCTAssertEqual(Set(report.groups.map(groupKey)), Set(expectedGroups.map(groupKey)))
            XCTAssertEqual(try f.snapshot(), before, "Audit must not rewrite content or privacy attributes")
        }
    }

    func testActualAncestorBackupExclusionIsComparedWithIndependentFoundationReads() throws {
        try fixture { f in
            var root = f.root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try root.setResourceValues(values)
            let report = StorageAuditInspector.inspect(rootURL: root)
            XCTAssertEqual(report.status, .complete)
            let expected = try f.independentGroups()
            XCTAssertEqual(Set(report.groups.map(groupKey)), Set(expected.map(groupKey)),
                "Effective exclusion includes actual ancestors within the owned root")
            XCTAssertGreaterThan(report.groups.reduce(0) { $0 + $1.itemCount }, 0)
            for url in f.items {
                XCTAssertEqual(try independentExclusion(url, within: root), .excluded)
            }
        }
    }

    func testActualEnvironmentCannotBeReportedAsPhysicalIOSByDesktopOrSimulator() throws {
        try fixture { f in
            let report = StorageAuditInspector.inspect(rootURL: f.root)
#if os(iOS) && targetEnvironment(simulator)
            XCTAssertEqual(report.environment, .iOSSimulator)
#elseif os(iOS)
            XCTAssertEqual(report.environment, .iOSDevice)
#elseif os(macOS)
            XCTAssertEqual(report.environment, .macOS)
#else
            XCTAssertEqual(report.environment, .other)
#endif
        }
    }

    func testSerializedReportContainsOnlyFixedCategoriesAndCountsNeverPathsNamesOrContent() throws {
        try fixture { f in
            let report = StorageAuditInspector.inspect(rootURL: f.root)
            let data = try JSONEncoder().encode(report)
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["schemaVersion", "environment", "status", "inspectedItemCount", "groups"])
            let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
            for group in groups {
                XCTAssertEqual(Set(group.keys), ["role", "protectionClass", "backupExclusion", "itemCount"])
            }
            let text = String(decoding: data, as: UTF8.self)
            for secret in [f.root.path, f.root.lastPathComponent, StorageAuditFixture.privateContent,
                           StorageAuditFixture.privateFileName] {
                XCTAssertFalse(text.contains(secret), "Report must not export private filesystem/content strings")
            }
            XCTAssertEqual(try JSONDecoder().decode(StorageAuditReport.self, from: data), report)
        }
    }

    func testSmallBoundAndInvalidBoundsRemainExplicitInsteadOfClaimingACompleteAudit() throws {
        try fixture { f in
            let report = StorageAuditInspector.inspect(rootURL: f.root, itemLimit: 3)
            XCTAssertEqual(report.status, .limitReached)
            XCTAssertLessThanOrEqual(report.inspectedItemCount, 3)
            XCTAssertEqual(report.groups.reduce(0) { $0 + $1.itemCount }, report.inspectedItemCount)
            for limit in [0, -1, StorageAuditInspector.maximumItemLimit + 1, Int.max] {
                let invalid = StorageAuditInspector.inspect(rootURL: f.root, itemLimit: limit)
                XCTAssertEqual(invalid.status, .invalidLimit)
                XCTAssertEqual(invalid.inspectedItemCount, 0)
                XCTAssertTrue(invalid.groups.isEmpty)
            }
        }
    }

    func testMissingRootIsUnreadableAndNonFileRootIsUnsafeWithoutFabricatingEmptySuccess() throws {
        try fixture { f in
            let missing = StorageAuditInspector.inspect(rootURL: f.root.appendingPathComponent("not-created"))
            XCTAssertEqual(missing.status, .unreadable)
            XCTAssertEqual(missing.inspectedItemCount, 0)
            XCTAssertTrue(missing.groups.isEmpty)
            let remote = try XCTUnwrap(URL(string: "https://example.invalid/private-storage"))
            let unsafe = StorageAuditInspector.inspect(rootURL: remote)
            XCTAssertEqual(unsafe.status, .unsafeRootOrItem)
            XCTAssertTrue(unsafe.groups.isEmpty)
            let regularFile = StorageAuditInspector.inspect(rootURL: f.root.appendingPathComponent(StorageAuditFixture.privateFileName))
            XCTAssertEqual(regularFile.status, .unsafeRootOrItem,
                "An existing regular file cannot serve as the owned audit directory")
            XCTAssertEqual(regularFile.inspectedItemCount, 0)
            XCTAssertTrue(regularFile.groups.isEmpty)
        }
    }

    func testSymlinkRootAndNestedEscapeAreRejectedWithoutReadingOrModifyingOutsideFiles() throws {
        try fixture { f in
            let outside = f.parent.appendingPathComponent("localminutes-storage-audit-outside-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            defer { try? removeOwnedStorageAuditRoot(outside, parent: f.parent, prefix: "localminutes-storage-audit-outside-") }
            let sentinel = outside.appendingPathComponent("segment-999999.caf")
            let bytes = Data("External original synthetic sentinel".utf8)
            try bytes.write(to: sentinel)
            let attributes = try FileManager.default.attributesOfItem(atPath: sentinel.path)
            let link = f.root.appendingPathComponent("outside-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let report = StorageAuditInspector.inspect(rootURL: f.root)
            XCTAssertEqual(report.status, .unsafeRootOrItem)
            XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: sentinel.path)[.modificationDate] as? Date,
                           attributes[.modificationDate] as? Date)
            let rootLink = StorageAuditInspector.inspect(rootURL: link)
            XCTAssertEqual(rootLink.status, .unsafeRootOrItem)
            XCTAssertEqual(rootLink.inspectedItemCount, 0)
            XCTAssertTrue(rootLink.groups.isEmpty)
            let outsideChild = outside.appendingPathComponent("child", isDirectory: true)
            try FileManager.default.createDirectory(at: outsideChild, withIntermediateDirectories: false)
            let ancestorLink = StorageAuditInspector.inspect(rootURL: link.appendingPathComponent("child", isDirectory: true))
            XCTAssertEqual(ancestorLink.status, .unsafeRootOrItem,
                "A regular-looking root below a symlinked ancestor must not audit outside the lexical owner boundary")
            XCTAssertEqual(ancestorLink.inspectedItemCount, 0)
            XCTAssertTrue(ancestorLink.groups.isEmpty)
        }
    }

    private func fixture(_ body: (StorageAuditFixture) throws -> Void) throws {
        let fixture = try StorageAuditFixture()
        defer { try? removeOwnedStorageAuditRoot(fixture.root, parent: fixture.parent, prefix: "localminutes-storage-audit-") }
        try body(fixture)
    }
}

private func groupKey(_ value: StorageAuditGroup) -> String {
    "\(value.role.rawValue)|\(value.protectionClass.rawValue)|\(value.backupExclusion.rawValue)|\(value.itemCount)"
}

private func independentProtection(_ item: URL) throws -> StorageAuditProtectionClass {
    let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
    let value = attributes[FileAttributeKey(rawValue: "NSFileProtectionKey")]
    let raw: String?
#if os(iOS)
    raw = (value as? FileProtectionType)?.rawValue ?? (value as? String)
#else
    raw = value as? String
#endif
    switch raw {
    case "NSFileProtectionComplete": return .complete
    case "NSFileProtectionCompleteUnlessOpen": return .completeUnlessOpen
    case "NSFileProtectionCompleteUntilFirstUserAuthentication": return .completeUntilFirstUserAuthentication
    case "NSFileProtectionNone": return .none
    default: return .unknown
    }
}

private func independentExclusion(_ item: URL, within root: URL) throws -> StorageAuditBackupExclusion {
    var current = item
    var unknown = false
    while true {
        let reported = try URL(fileURLWithPath: current.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        if reported == true { return .excluded }
        if reported == nil { unknown = true }
        if current == root { return unknown ? .unknown : .included }
        current.deleteLastPathComponent()
    }
}

private struct StorageAuditFixture {
    static let privateContent = "Synthetic private transcript/model-output canary: never export this text."
    static let privateFileName = "private-person-name.txt"
    let parent: URL
    let root: URL
    let items: [URL]
    let roles: [URL: StorageAuditRole]

    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        root = parent.appendingPathComponent("localminutes-storage-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        // Layout copied from LocalMinutesServices, ModelInstallationManager,
        // ModelSelectionStore, SegmentCAFWriter and SummaryCheckpointStore.
        // Bytes remain explicitly synthetic; no fake SQLite/CAF/model validation.
        let meetingID = "10000000-0000-4000-8000-000000000001"
        let generationID = "20000000-0000-4000-8000-000000000002"
        let installationID = "30000000-0000-4000-8000-000000000003"
        let modelPrefix = "Models/parakeet-tdt-0-6b-v2-coreml/ee09c569f73759e6d44c9bd16766f477b2b36d39/\(installationID)"
        let restoredPrefix = "LibraryGenerations/\(generationID)"
        let files: [(String, StorageAuditRole)] = [
            ("meetings.sqlite", .libraryDatabase), ("meetings.sqlite-wal", .databaseSidecar),
            ("meetings.sqlite-shm", .databaseSidecar),
            ("Meetings/\(meetingID)/segment-000000.caf", .audioSegment),
            ("Meetings/\(meetingID)/capture-manifest.json", .captureManifest),
            ("\(modelPrefix)/Encoder.mlmodelc/weights/weight.bin", .modelArtifact),
            ("\(modelPrefix)/Encoder.mlmodelc/metadata.json", .modelArtifact),
            ("\(modelPrefix)/parakeet_vocab.json", .modelArtifact),
            ("\(modelPrefix)/manifest.json", .modelMetadata),
            ("Models/parakeet-tdt-0-6b-v2-coreml/current.json", .modelMetadata),
            ("ModelSelections/speechRecognition.json", .modelMetadata),
            ("ModelSelections/summary.json", .modelMetadata),
            ("SummaryCheckpoints/\(meetingID).json", .summaryCheckpoint),
            ("Diagnostics/endurance-metrics.json", .diagnostics),
            ("Diagnostics/transcription-metrics.json", .diagnostics),
            ("activeLibrary.json", .other),
            ("\(restoredPrefix)/meetings.sqlite", .libraryDatabase),
            ("\(restoredPrefix)/meetings.sqlite-wal", .databaseSidecar),
            ("\(restoredPrefix)/Meetings/\(meetingID)/segment-000000.caf", .audioSegment),
            ("\(restoredPrefix)/Meetings/\(meetingID)/capture-manifest.json", .captureManifest),
            ("\(restoredPrefix)/SummaryCheckpoints/\(meetingID).json", .summaryCheckpoint),
            (Self.privateFileName, .other)
        ]
        var expected: [URL: StorageAuditRole] = [root: .directory]
        for (relative, role) in files {
            let file = root.appendingPathComponent(relative)
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(Self.privateContent.utf8).write(to: file)
            expected[file] = role
            var ancestor = directory
            while ancestor != root {
                expected[ancestor] = .directory
                ancestor.deleteLastPathComponent()
            }
        }
        roles = expected
        items = Array(expected.keys)
    }

    func independentGroups() throws -> [StorageAuditGroup] {
        var result: [StorageAuditGroup] = []
        for item in items {
            let role = try XCTUnwrap(roles[item])
            let protection = try independentProtection(item)
            let excluded = try independentExclusion(item, within: root)
            if let index = result.firstIndex(where: {
                $0.role == role && $0.protectionClass == protection && $0.backupExclusion == excluded
            }) {
                result[index] = .init(role: role, protectionClass: protection, backupExclusion: excluded,
                    itemCount: result[index].itemCount + 1)
            } else {
                result.append(.init(role: role, protectionClass: protection, backupExclusion: excluded, itemCount: 1))
            }
        }
        return result
    }

    func snapshot() throws -> [Data] {
        try items.sorted(by: { $0.path < $1.path }).map { item in
            let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
            let contents: Data
            if attributes[.type] as? FileAttributeType == .typeRegular { contents = try Data(contentsOf: item) }
            else { contents = Data() }
            let values = [String(describing: attributes[.posixPermissions]),
                          String(describing: attributes[.modificationDate]),
                          try independentProtection(item).rawValue, try independentExclusion(item, within: root).rawValue]
            return contents + Data(values.joined(separator: "|").utf8)
        }
    }
}

private func removeOwnedStorageAuditRoot(_ root: URL, parent: URL, prefix: String) throws {
    guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix(prefix),
          UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
          root.resolvingSymlinksInPath().standardizedFileURL == root else {
        XCTFail("Refuse cleanup outside owned storage-audit fixture"); return
    }
    try FileManager.default.removeItem(at: root)
}
