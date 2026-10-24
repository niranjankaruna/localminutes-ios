import AVFoundation
import AudioToolbox
import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import LocalMinutesCore

/// Native SQLite/CAF bytes, never a mocked store or audio encoder. The table
/// is a small archive-layer fixture, not an assertion of app schema migration
/// compatibility. Persistence/app admission integration is a separate slice.
final class MeetingArchiveTests: XCTestCase {
    func testVersionedArchiveRoundTripsClosedSQLiteOriginalsGeneratedNotesAndActual16BitCAF() throws {
        try fixture { f in
            let originals = try f.fileBytes()
            let manifest = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive)
            XCTAssertEqual(manifest.schemaVersion, 1)
            XCTAssertEqual(manifest.databaseUserVersion, 4)
            XCTAssertEqual(Set(manifest.files.map(\.relativePath)), Set(f.paths))
            XCTAssertEqual(manifest.totalByteCount, originals.values.reduce(0) { $0 + Int64($1.count) })
            for entry in manifest.files {
                let original = try XCTUnwrap(originals[entry.relativePath])
                XCTAssertEqual(entry.byteCount, Int64(original.count))
                XCTAssertEqual(entry.sha256, archiveDigest(original))
                XCTAssertEqual(try Data(contentsOf: f.archive.appendingPathComponent("payload/" + entry.relativePath)), original)
            }
            XCTAssertEqual(try MeetingArchive.inspect(f.archive), manifest)
            let serialized = try Data(contentsOf: f.archive.appendingPathComponent("manifest.json"))
            let text = try XCTUnwrap(String(data: serialized, encoding: .utf8))
            XCTAssertFalse(text.contains(f.root.path), "Never publish a workstation/private sandbox path in package metadata")
            XCTAssertFalse(text.contains(ArchiveFixture.originalNote))
            XCTAssertFalse(text.contains(ArchiveFixture.generatedNote))
            XCTAssertEqual(try MeetingArchive.restore(from: f.archive, to: f.restored), manifest)
            XCTAssertEqual(try f.fileBytes(at: f.restored), originals)
            XCTAssertEqual(try f.readRows(at: f.restored), [ArchiveFixture.originalNote, ArchiveFixture.transcript, ArchiveFixture.generatedNote])
            try f.assertNativeCAF(at: f.restored)
            XCTAssertEqual(try f.fileBytes(), originals, "Export/restore must not rewrite the source meeting snapshot")
        }
    }

    func testRestoreAndInspectionAcceptAnIndependentlyConstructedHashedDirectoryPackage() throws {
        try fixture { f in
            let expected = try f.makePackage()
            XCTAssertEqual(try MeetingArchive.inspect(f.archive), expected)
            XCTAssertEqual(try MeetingArchive.restore(from: f.archive, to: f.restored), expected)
            XCTAssertEqual(try f.readRows(at: f.restored), [ArchiveFixture.originalNote, ArchiveFixture.transcript, ArchiveFixture.generatedNote])
            try f.assertNativeCAF(at: f.restored)
            for path in f.paths {
                let original = f.snapshot.appendingPathComponent(path)
                let restored = f.restored.appendingPathComponent(path)
                XCTAssertEqual(try Data(contentsOf: restored), try Data(contentsOf: original))
                let permissions = try FileManager.default.attributesOfItem(atPath: restored.path)[.posixPermissions] as? NSNumber
                XCTAssertEqual(permissions?.intValue, 0o600)
                let links = try FileManager.default.attributesOfItem(atPath: restored.path)[.referenceCount] as? NSNumber
                XCTAssertEqual(links?.intValue, 1, "Restored files must not share an inode with source or external files")
            }
        }
    }

    func testCorruptMissingOrTruncatedPayloadCannotPublishAnyRestoreOrLeaveStagingFiles() throws {
        for fault in ["corrupt", "missing", "truncate"] {
            try fixture { f in
                _ = try f.makePackage()
                let payload = f.archive.appendingPathComponent("payload/" + f.paths[1])
                if fault == "missing" { try FileManager.default.removeItem(at: payload) }
                else {
                    var data = try Data(contentsOf: payload)
                    if fault == "truncate" { data.removeLast() } else { data[data.startIndex] ^= 0xff }
                    try data.write(to: payload)
                }
                let before = try f.children()
                expect(.integrityMismatch) { _ = try MeetingArchive.restore(from: f.archive, to: f.restored) }
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.restored.path))
                XCTAssertEqual(try f.children(), before, "Failed restore cleans only its own staging, publishing no partial package")
                XCTAssertEqual(try f.readRows(), [ArchiveFixture.originalNote, ArchiveFixture.transcript, ArchiveFixture.generatedNote])
            }
        }
    }

    func testManifestTraversalAbsoluteDuplicateAndUnknownSchemaAreRejectedBeforeMutation() throws {
        for fault in ["../outside.sqlite", "/absolute.sqlite", "duplicate", "version"] {
            try fixture { f in
                _ = try f.makePackage()
                try f.changeManifest { object in
                    var files = try XCTUnwrap(object["files"] as? [[String: Any]])
                    if fault == "duplicate" { files.append(files[0]) }
                    else if fault == "version" { object["schemaVersion"] = 99 }
                    else { files[0]["relativePath"] = fault }
                    object["files"] = files
                }
                let before = try f.children()
                expect(fault == "version" ? .unsupportedVersion : .invalidManifest) {
                    _ = try MeetingArchive.restore(from: f.archive, to: f.restored)
                }
                XCTAssertEqual(try f.children(), before)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.restored.path))
            }
        }
    }

    func testUnlistedPayloadAndPrivateOrModelFilesAreNeverSilentlyIncluded() throws {
        try fixture { f in
            _ = try f.makePackage()
            try Data("Original synthetic extra file".utf8).write(to: f.archive.appendingPathComponent("payload/credentials.txt"))
            expect(.unexpectedFile) { _ = try MeetingArchive.inspect(f.archive) }
        }
        for path in ["credentials.txt", ".env", "Models/private-model.gguf", "Diagnostics/raw-device-log.txt"] {
            try fixture { f in
                let extra = f.snapshot.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("Original synthetic forbidden export fixture".utf8).write(to: extra)
                expect(.unexpectedFile) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive) }
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.archive.path))
                XCTAssertEqual(try Data(contentsOf: extra), Data("Original synthetic forbidden export fixture".utf8))
            }
        }
    }

    func testRealUncheckpointedSQLiteWALIsRejectedInsteadOfLosingDurableNotes() throws {
        try fixture { f in
            try archiveDatabase(f.snapshot.appendingPathComponent("meetings.sqlite")) { db in
                try archiveSQL(db, "PRAGMA journal_mode=WAL; INSERT INTO archive_fixture VALUES(3,'Uncheckpointed original note');")
                let wal = f.snapshot.appendingPathComponent("meetings.sqlite-wal")
                XCTAssertTrue(FileManager.default.fileExists(atPath: wal.path), "Actual SQLite WAL creation is a setup prerequisite")
                let walBefore = try Data(contentsOf: wal)
                XCTAssertFalse(walBefore.isEmpty)
                let mainBefore = try Data(contentsOf: f.snapshot.appendingPathComponent("meetings.sqlite"))
                expect(.snapshotNotClosed) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive) }
                XCTAssertEqual(try Data(contentsOf: wal), walBefore)
                XCTAssertEqual(try Data(contentsOf: f.snapshot.appendingPathComponent("meetings.sqlite")), mainBefore,
                               "Reject without checkpointing or changing the caller-owned live main database")
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.archive.path))
            }
            XCTAssertEqual(try f.readRows().last, "Uncheckpointed original note", "Export must not checkpoint/delete a caller-owned live WAL")
        }
    }

    func testSymlinkOrHardlinkInSnapshotOrArchiveCannotReadOutsideTheOwnedPackage() throws {
        for mode in ["sourceSymlink", "sourceHardlink", "payloadSymlink"] {
            try fixture { f in
                let outside = f.root.appendingPathComponent("outside-private.bin")
                let marker = Data("Original private boundary marker".utf8)
                try marker.write(to: outside)
                if mode == "payloadSymlink" { _ = try f.makePackage() }
                let target = (mode == "payloadSymlink" ? f.archive.appendingPathComponent("payload") : f.snapshot)
                    .appendingPathComponent(f.paths[1])
                try FileManager.default.removeItem(at: target)
                if mode == "sourceHardlink" { try FileManager.default.linkItem(at: outside, to: target) }
                else { try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside) }
                if mode == "payloadSymlink" {
                    expect(.unsafeItem) { _ = try MeetingArchive.restore(from: f.archive, to: f.restored) }
                    XCTAssertFalse(FileManager.default.fileExists(atPath: f.restored.path))
                } else {
                    expect(.unsafeItem) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive) }
                    XCTAssertFalse(FileManager.default.fileExists(atPath: f.archive.path))
                }
                XCTAssertEqual(try Data(contentsOf: outside), marker)
            }
        }
    }

    func testExistingDestinationOrArchiveIsNeverOverwrittenOrMerged() throws {
        try fixture { f in
            _ = try f.makePackage()
            let archiveBefore = try Data(contentsOf: f.archive.appendingPathComponent("manifest.json"))
            expect(.destinationExists) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive) }
            XCTAssertEqual(try Data(contentsOf: f.archive.appendingPathComponent("manifest.json")), archiveBefore)
            try FileManager.default.createDirectory(at: f.restored, withIntermediateDirectories: false)
            let sentinel = f.restored.appendingPathComponent("existing-private-notes.txt")
            let marker = Data("Existing original notes must remain intact".utf8)
            try marker.write(to: sentinel)
            let before = try f.children()
            expect(.destinationExists) { _ = try MeetingArchive.restore(from: f.archive, to: f.restored) }
            XCTAssertEqual(try Data(contentsOf: sentinel), marker)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.restored.path), [sentinel.lastPathComponent])
            XCTAssertEqual(try f.children(), before)
        }
    }

    func testInsideSourceOutputsAndInvalidLocationsCannotStartRecursiveCopies() throws {
        try fixture { f in
            let nested = f.snapshot.appendingPathComponent("backup.localminutesbackup")
            expect(.invalidLocation) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: nested) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
            expect(.invalidLocation) {
                _ = try MeetingArchive.export(snapshotRoot: URL(string: "https://example.invalid/snapshot")!, to: f.archive)
            }
            _ = try f.makePackage()
            let inside = f.archive.appendingPathComponent("restored")
            expect(.invalidLocation) { _ = try MeetingArchive.restore(from: f.archive, to: inside) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path))
        }
    }

    func testFileTotalAndManifestCapsRejectBeforePublishingPartialOutput() throws {
        try fixture { f in
            let originals = try f.fileBytes()
            let total = originals.values.reduce(0) { $0 + Int64($1.count) }
            let limits = [MeetingArchiveLimits(maximumFiles: 2),
                MeetingArchiveLimits(maximumTotalBytes: total - 1),
                MeetingArchiveLimits(maximumFileBytes: 16),
                MeetingArchiveLimits(maximumManifestBytes: 32)]
            for cap in limits {
                let before = try f.children()
                expect(.limitExceeded) { _ = try MeetingArchive.export(snapshotRoot: f.snapshot, to: f.archive, limits: cap) }
                XCTAssertEqual(try f.children(), before)
                XCTAssertFalse(FileManager.default.fileExists(atPath: f.archive.path))
            }
            _ = try f.makePackage()
            expect(.limitExceeded) { _ = try MeetingArchive.inspect(f.archive, limits: .init(maximumManifestBytes: 32)) }
            XCTAssertEqual(try f.fileBytes(), originals)
        }
    }

    private func expect(_ expected: MeetingArchiveError, _ body: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) {
        do { try body(); XCTFail("Expected archive rejection: \(expected)", file: file, line: line) }
        catch let actual as MeetingArchiveError { XCTAssertEqual(actual, expected, file: file, line: line) }
        catch { XCTFail("Unexpected archive error category: \(type(of: error))", file: file, line: line) }
    }

    private func fixture(_ body: (ArchiveFixture) throws -> Void) throws {
        let f = try ArchiveFixture()
        do { try body(f) }
        catch { try f.remove(); throw error }
        try f.remove()
    }
}

/// Separate traversal-budget regression; the original ten archive oracles stay
/// unchanged. Exactly one regular DB file prevents a file-count false positive.
final class MeetingArchiveDirectoryLimitTests: XCTestCase {
    func testEmptyMeetingDirectoriesConsumeTraversalBudgetBeforeExportInspectionOrRestorePublication() throws {
        let f = try ArchiveFixture()
        defer { try? f.remove() }
        try FileManager.default.removeItem(at: f.snapshot.appendingPathComponent("Meetings", isDirectory: true))
        let database = f.snapshot.appendingPathComponent("meetings.sqlite")
        let original = try Data(contentsOf: database)
        let cap = MeetingArchiveLimits(maximumFiles: 2)
        let control = f.root.appendingPathComponent("one-file-control")
        let clean = try MeetingArchive.export(snapshotRoot: f.snapshot, to: control, limits: cap)
        XCTAssertEqual(clean.files.map(\.relativePath), ["meetings.sqlite"])
        try FileManager.default.removeItem(at: control)
        let ids = (1...3).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
        for id in ids {
            try FileManager.default.createDirectory(at: f.snapshot.appendingPathComponent("Meetings/" + id),
                withIntermediateDirectories: true)
        }
        let exportTarget = f.root.appendingPathComponent("must-not-export")
        XCTAssertThrowsError(try MeetingArchive.export(snapshotRoot: f.snapshot, to: exportTarget, limits: cap)) { error in
            XCTAssertEqual(error as? MeetingArchiveError, .limitExceeded)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportTarget.path))

        // Build the archive independently, including only the one real DB file.
        let payload = f.archive.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: database, to: payload.appendingPathComponent("meetings.sqlite"))
        let manifest = MeetingArchiveManifest(databaseUserVersion: 4, totalByteCount: Int64(original.count),
            files: [.init(relativePath: "meetings.sqlite", byteCount: Int64(original.count), sha256: archiveDigest(original))])
        try JSONEncoder().encode(manifest).write(to: f.archive.appendingPathComponent("manifest.json"))
        XCTAssertEqual(try MeetingArchive.inspect(f.archive, limits: cap), manifest,
            "The one-file independent package must be valid before empty directories are introduced")
        for id in ids {
            try FileManager.default.createDirectory(at: payload.appendingPathComponent("Meetings/" + id),
                withIntermediateDirectories: true)
        }
        XCTAssertThrowsError(try MeetingArchive.inspect(f.archive, limits: cap)) { error in
            XCTAssertEqual(error as? MeetingArchiveError, .limitExceeded)
        }
        XCTAssertThrowsError(try MeetingArchive.restore(from: f.archive, to: f.restored, limits: cap)) { error in
            XCTAssertEqual(error as? MeetingArchiveError, .limitExceeded)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.restored.path))
        XCTAssertEqual(try Data(contentsOf: database), original)
        XCTAssertEqual(try Data(contentsOf: payload.appendingPathComponent("meetings.sqlite")), original)
        XCTAssertEqual(try f.readRows(), [ArchiveFixture.originalNote, ArchiveFixture.transcript, ArchiveFixture.generatedNote])
    }
}

private enum ArchiveFixtureError: Error { case sqlite(Int32), invalidAudio, unsafeCleanup }

final class MeetingArchiveRecoveryPayloadTests: XCTestCase {
    func testQuarantinedAudioAndRecoveryMetadataRemainExactBackupPayloadWithoutBeingTreatedAsHealthyAudio() throws {
        let fixture = try ArchiveFixture()
        defer { try? fixture.remove() }
        let prefix = "Meetings/\(fixture.meetingID.uuidString)/"
        let relative = prefix + "RecoveryQuarantine/segment-000002.caf"
        let brokenAudio = Data("Synthetic corrupt tail retained as recovery evidence".utf8)
        let target = fixture.snapshot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try brokenAudio.write(to: target)
        let report = Data(#"{"schemaVersion":1,"quarantinedFiles":["segment-000002.caf"],"reason":"corruptAudio"}"#.utf8)
        try report.write(to: fixture.snapshot.appendingPathComponent(prefix + "recovery-report.json"))
        let manifest = try MeetingArchive.export(snapshotRoot: fixture.snapshot, to: fixture.archive)
        let entry = try XCTUnwrap(manifest.files.first { $0.relativePath == relative })
        XCTAssertEqual(entry.byteCount, Int64(brokenAudio.count))
        XCTAssertEqual(entry.sha256, archiveDigest(brokenAudio))
        XCTAssertEqual(try MeetingArchive.inspect(fixture.archive), manifest)
        _ = try MeetingArchive.restore(from: fixture.archive, to: fixture.restored)
        XCTAssertEqual(try Data(contentsOf: fixture.restored.appendingPathComponent(relative)), brokenAudio)
        XCTAssertEqual(try Data(contentsOf: fixture.restored.appendingPathComponent(prefix + "recovery-report.json")), report)
        XCTAssertEqual(try Data(contentsOf: target), brokenAudio)
        try fixture.assertNativeCAF(at: fixture.restored)
        XCTAssertEqual(try fixture.readRows(at: fixture.restored),
            [ArchiveFixture.originalNote, ArchiveFixture.transcript, ArchiveFixture.generatedNote])
    }
}

private func archiveDatabase(_ file: URL, readOnly: Bool = false,
                             _ body: (OpaquePointer) throws -> Void) throws {
    var db: OpaquePointer?
    let status = sqlite3_open_v2(file.path, &db, readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard status == SQLITE_OK, let db else {
        if let db { sqlite3_close(db) }; throw ArchiveFixtureError.sqlite(status)
    }
    do { try body(db) }
    catch { sqlite3_close(db); throw error }
    let closed = sqlite3_close(db)
    guard closed == SQLITE_OK else { sqlite3_close_v2(db); throw ArchiveFixtureError.sqlite(closed) }
}

private func archiveSQL(_ db: OpaquePointer, _ sql: String) throws {
    let status = sqlite3_exec(db, sql, nil, nil, nil)
    guard status == SQLITE_OK else { throw ArchiveFixtureError.sqlite(status) }
}

private func archiveDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

private final class ArchiveFixture {
    static let originalNote = "Original manual note — café 📝"
    static let transcript = "Original synthetic finalized transcript."
    static let generatedNote = "Generated note, kept separate from the original."
    let root: URL
    let snapshot: URL
    let archive: URL
    let restored: URL
    let meetingID = UUID(uuidString: "00000000-0000-0000-0000-000000000081")!
    var paths: [String] { ["meetings.sqlite", "Meetings/\(meetingID.uuidString)/segment-000001.caf",
                           "Meetings/\(meetingID.uuidString)/capture-manifest.json"] }

    init() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        root = parent.appendingPathComponent("LocalMinutesArchive-\(UUID().uuidString)", isDirectory: true)
        snapshot = root.appendingPathComponent("Snapshot", isDirectory: true)
        archive = root.appendingPathComponent("meeting.localminutesbackup", isDirectory: true)
        restored = root.appendingPathComponent("Restored", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: snapshot.appendingPathComponent("Meetings/\(meetingID.uuidString)"),
                                                    withIntermediateDirectories: true)
            try archiveDatabase(snapshot.appendingPathComponent("meetings.sqlite")) { db in
                try archiveSQL(db, "PRAGMA user_version=4; CREATE TABLE archive_fixture(sequence INTEGER PRIMARY KEY, body TEXT NOT NULL);")
                for (index, text) in [Self.originalNote, Self.transcript, Self.generatedNote].enumerated() {
                    let escaped = text.replacingOccurrences(of: "'", with: "''")
                    try archiveSQL(db, "INSERT INTO archive_fixture VALUES(\(index),'\(escaped)');")
                }
            }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
            let writer = try AVAudioFile(forWriting: snapshot.appendingPathComponent(paths[1]), settings: settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
            do {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: 320),
                      let samples = buffer.floatChannelData?.pointee else { throw ArchiveFixtureError.invalidAudio }
                buffer.frameLength = 320
                for index in 0..<320 { samples[index] = index.isMultiple(of: 2) ? 0.25 : -0.125 }
                try writer.write(from: buffer); writer.close()
            } catch { writer.close(); throw error }
            let metadata: [String: Any] = ["schemaVersion": 1, "sessionID": meetingID.uuidString,
                "totalFrames": 320, "segments": [["relativePath": "segment-000001.caf", "startFrame": 0, "frameCount": 320]]]
            try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
                .write(to: snapshot.appendingPathComponent(paths[2]))
            try assertNativeCAF(at: snapshot)
        } catch { try? remove(); throw error }
    }

    func fileBytes(at directory: URL? = nil) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: paths.map { ($0, try Data(contentsOf: (directory ?? snapshot).appendingPathComponent($0))) })
    }
    func children() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) }
    func makePackage() throws -> MeetingArchiveManifest {
        let payload = archive.appendingPathComponent("payload", isDirectory: true)
        let bytes = try fileBytes()
        let files = paths.sorted().map { MeetingArchiveFile(relativePath: $0,
            byteCount: Int64(bytes[$0]!.count), sha256: archiveDigest(bytes[$0]!)) }
        let manifest = MeetingArchiveManifest(databaseUserVersion: 4,
            totalByteCount: files.reduce(0) { $0 + $1.byteCount }, files: files)
        for path in paths {
            let output = payload.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: snapshot.appendingPathComponent(path), to: output)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: archive.appendingPathComponent("manifest.json"))
        return manifest
    }
    func changeManifest(_ body: (inout [String: Any]) throws -> Void) throws {
        let file = archive.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try body(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: file)
    }
    func readRows(at directory: URL? = nil) throws -> [String] {
        var rows: [String] = []
        try archiveDatabase((directory ?? snapshot).appendingPathComponent("meetings.sqlite"), readOnly: true) { db in
            var statement: OpaquePointer?
            let status = sqlite3_prepare_v2(db, "SELECT body FROM archive_fixture ORDER BY sequence", -1, &statement, nil)
            guard status == SQLITE_OK, let statement else { throw ArchiveFixtureError.sqlite(status) }
            defer { sqlite3_finalize(statement) }
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw ArchiveFixtureError.sqlite(step) }
                rows.append(String(cString: bytes))
            }
        }
        return rows
    }
    func assertNativeCAF(at directory: URL) throws {
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(paths[1]),
                                   commonFormat: .pcmFormatInt16, interleaved: false)
        defer { file.close() }
        XCTAssertEqual(file.length, 320)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 320) else {
            throw ArchiveFixtureError.invalidAudio
        }
        try file.read(into: buffer)
        XCTAssertEqual(buffer.frameLength, 320)
        let samples = try XCTUnwrap(buffer.int16ChannelData?.pointee)
        for index in 0..<320 { XCTAssertEqual(samples[index], index.isMultiple(of: 2) ? 8_192 : -4_096) }
    }
    func remove() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix("LocalMinutesArchive-"),
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              UUID(uuidString: String(root.lastPathComponent.dropFirst("LocalMinutesArchive-".count))) != nil else {
            throw ArchiveFixtureError.unsafeCleanup
        }
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
}
