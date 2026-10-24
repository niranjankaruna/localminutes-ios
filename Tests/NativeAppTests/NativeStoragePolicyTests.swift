#if os(iOS)
import AVFoundation
import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import LocalMinutes

// Expanded coverage of existing policy behavior after its recorded RED. These
// cases verify real Simulator-supported filesystem/SQLite/CAF operations. They
// never stand in for the unchanged physical protection-class oracle.
@MainActor
private final class StoragePolicyFixture {
    let parent: URL
    let root: URL
    init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .resolvingSymlinksInPath().standardizedFileURL
        parent = support.appendingPathComponent("LocalMinutesStoragePolicyTests", isDirectory: true)
        root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func cleanup(file: StaticString = #filePath, line: UInt = #line) {
        guard parent.lastPathComponent == "LocalMinutesStoragePolicyTests",
              root.deletingLastPathComponent().standardizedFileURL == parent,
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              UUID(uuidString: root.lastPathComponent) != nil else {
            XCTFail("Unsafe storage-policy fixture cleanup target", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned storage-policy fixture cleanup failed", file: file, line: line) }
    }
}

@MainActor
private final class StoragePolicyWALConnection {
    private var handle: OpaquePointer?
    init(database: URL) throws {
        var opened: OpaquePointer?
        guard sqlite3_open_v2(database.path, &opened,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
            let opened else {
            if let opened { sqlite3_close_v2(opened) }
            throw MeetingStoreError.databaseFailure
        }
        handle = opened
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA wal_autocheckpoint=0")
        } catch { close(); throw error }
    }
    private func execute(_ sql: String) throws {
        guard let handle, sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw MeetingStoreError.databaseFailure
        }
    }
    func close() {
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }
}

@MainActor
final class NativeStoragePolicyTests: XCTestCase {
    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func excludedDirectly(_ url: URL) throws -> Bool {
        try URL(fileURLWithPath: url.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    private func assertPolicy(_ url: URL, within root: URL,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let item = URL(fileURLWithPath: url.path)
        let metadata = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        XCTAssertNotEqual(metadata.isSymbolicLink, true, file: file, line: line)
        XCTAssertTrue(metadata.isDirectory == true || metadata.isRegularFile == true,
                      "The actual persistent item must exist", file: file, line: line)
        XCTAssertEqual(try permissions(item), metadata.isDirectory == true ? 0o700 : 0o600,
                       file: file, line: line)
        let boundary = root.standardizedFileURL
        var ancestor = item.standardizedFileURL
        guard ancestor.path == boundary.path || ancestor.path.hasPrefix(boundary.path + "/") else {
            XCTFail("Policy assertion escaped the fixture boundary", file: file, line: line); return
        }
        var excluded = false
        while ancestor.path == boundary.path || ancestor.path.hasPrefix(boundary.path + "/") {
            if try excludedDirectly(ancestor) { excluded = true; break }
            if ancestor == boundary { break }
            ancestor.deleteLastPathComponent()
        }
        XCTAssertTrue(excluded, "Backup exclusion must be present on the item or an owned ancestor",
                      file: file, line: line)
    }

    private func setBackupExcluded(_ value: Bool, on item: URL) throws {
        var url = URL(fileURLWithPath: item.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = value
        try url.setResourceValues(values)
    }

    private func signal(frames: Int) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format,
                                                  frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<frames { samples[index] = Float(index % 16) / 128 }
        return buffer
    }

    private func sourceFixture(in root: URL) throws -> (URL, ModelManifest, [String: Data]) {
        let source = root.appendingPathComponent("Import", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o750])
        try setBackupExcluded(false, on: source)
        let revision = String(repeating: "e", count: 40)
        let names: [(ModelFileRole, String)] = [(.encoder, "encoder.onnx"), (.decoder, "decoder.onnx"),
                                               (.joiner, "joiner.onnx"), (.tokens, "tokens.txt")]
        var originals: [String: Data] = [:]
        let artifacts = try names.map { role, name in
            // Original bytes validate copy/hash/metadata behavior only. They
            // are explicitly not an inference model and never enter a runtime.
            let data = Data("Original non-model storage-policy fixture: \(name)".utf8)
            let path = source.appendingPathComponent(name)
            try data.write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path.path)
            try setBackupExcluded(false, on: path)
            originals[name] = data
            return ModelArtifact(role: role, fileName: name, byteCount: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                downloadURL: URL(string: "https://huggingface.co/example/storage-fixture/resolve/\(revision)/\(name)")!,
                digestProvenance: .independentlyDownloaded)
        }
        let manifest = ModelManifest(modelID: "storage-fixture", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/example/storage-fixture")!,
            revision: revision, licenseIdentifier: "CC0-1.0",
            licenseNotice: "Original LocalMinutes non-model storage-policy fixture, CC0-1.0.",
            runtimeVersion: "fixture-only", sampleRate: 16_000, featureDimension: 80, artifacts: artifacts)
        return (source, manifest, originals)
    }

    func testSimulatorProtectionCapabilityIsReportedWithoutPhysicalVerification() throws {
        let h = try StoragePolicyFixture(); defer { h.cleanup() }
        let sample = h.root.appendingPathComponent("capability.txt")
        let original = Data("Original public capability fixture".utf8)
        try original.write(to: sample)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: sample.path)
        try PersistentFilePolicy.protectDirectory(h.root)
        let attributes = try FileManager.default.attributesOfItem(atPath: sample.path)
        let value = attributes[.protectionKey]
        let reported = (value as? FileProtectionType)?.rawValue ?? (value as? String)
        if let reported {
            XCTAssertEqual(reported, FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            print("PROTECTION_CAPABILITY SDK_METADATA_ONLY=\(reported); physical locked access=UNVERIFIED")
        } else {
            print("PROTECTION_CAPABILITY UNVERIFIED: SDK protection getter returned nil; physical gate NOT_RUN")
        }
        // These remain concrete assertions even when the SDK cannot expose a
        // protection class. No replacement metadata or skipped test is used.
        XCTAssertEqual(try Data(contentsOf: sample), original)
        try assertPolicy(h.root, within: h.root)
        try assertPolicy(sample, within: h.root)
    }

    func testDefaultServicesUseExcludedPrivatePersistentRoots() async throws {
        let services = try LocalMinutesServices()
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("LocalMinutes", isDirectory: true)
        XCTAssertEqual(services.meetingsDirectory.standardizedFileURL,
            root.appendingPathComponent("Meetings", isDirectory: true).standardizedFileURL)
        XCTAssertFalse(root.path.contains("/Caches/"))
        XCTAssertFalse(root.path.contains("/tmp/"))
        for item in [root, root.appendingPathComponent("Models"), root.appendingPathComponent("Meetings"),
                     root.appendingPathComponent("meetings.sqlite")] {
            try assertPolicy(item, within: root)
        }
        try await services.store.close()
    }

    func testVerifiedModelCopyAndAtomicPointerPreserveSourceBytesAndPermissions() async throws {
        let h = try StoragePolicyFixture(); defer { h.cleanup() }
        let models = h.root.appendingPathComponent("Models", isDirectory: true)
        let (source, manifest, originals) = try sourceFixture(in: h.root)
        let manager = ModelInstallationManager(rootURL: models,
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        let first = try await manager.importDirectory(source, manifest: manifest)
        let pointer = models.appendingPathComponent(manifest.modelID).appendingPathComponent("current.json")
        let firstPointer = try Data(contentsOf: pointer)
        let second = try await manager.importDirectory(source, manifest: manifest)
        XCTAssertNotEqual(first.installationID, second.installationID)
        XCTAssertNotEqual(try Data(contentsOf: pointer), firstPointer)
        let current = try await manager.current(modelID: manifest.modelID)
        XCTAssertEqual(current?.installationID, second.installationID)
        try assertPolicy(models, within: models)
        try assertPolicy(pointer, within: models)
        for installed in [first, second] {
            try assertPolicy(installed.directoryURL, within: models)
            let metadata = installed.directoryURL.appendingPathComponent("manifest.json")
            try assertPolicy(metadata, within: models)
            let persisted = try JSONDecoder().decode(ModelManifest.self, from: Data(contentsOf: metadata))
            XCTAssertEqual(persisted, manifest)
            for artifact in manifest.artifacts {
                let copied = try XCTUnwrap(installed.files[artifact.role])
                let original = try XCTUnwrap(originals[artifact.fileName])
                try assertPolicy(copied, within: models)
                XCTAssertEqual(try Data(contentsOf: copied), original)
            }
        }
        XCTAssertEqual(try permissions(source), 0o750)
        XCTAssertFalse(try excludedDirectly(source))
        for (name, original) in originals {
            let path = source.appendingPathComponent(name)
            XCTAssertEqual(try Data(contentsOf: path), original)
            XCTAssertEqual(try permissions(path), 0o640)
            XCTAssertFalse(try excludedDirectly(path))
        }
        let temporary = try FileManager.default.subpathsOfDirectory(atPath: models.path)
            .filter { $0.contains(".localminutes-write-") || $0.hasSuffix(".partial") }
        XCTAssertTrue(temporary.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: models.appendingPathComponent(".staging").path).isEmpty)
    }

    func testSQLiteSidecarRecreationAndCAFCheckpointRemainExcludedPrivateAndReadable() async throws {
        let h = try StoragePolicyFixture(); defer { h.cleanup() }
        let database = h.root.appendingPathComponent("meetings.sqlite")
        let external = try StoragePolicyWALConnection(database: database)
        defer { external.close() }
        let first = try SQLiteMeetingStore(databaseURL: database)
        let original = MeetingRecord(id: UUID(), title: "Original storage-policy fixture",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recording)
        try await first.createMeeting(original)
        let sidecars = [URL(fileURLWithPath: database.path + "-wal"), URL(fileURLWithPath: database.path + "-shm")]
        XCTAssertTrue(sidecars.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        for item in [h.root, database] + sidecars { try assertPolicy(item, within: h.root) }
        try await first.close()
        external.close()
        XCTAssertTrue(sidecars.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
                      "The subsequent checks must exercise newly created sidecars")
        let reopened = try SQLiteMeetingStore(databaseURL: database)
        let later = MeetingRecord(id: UUID(), title: "Later original storage-policy fixture",
            createdAt: Date(timeIntervalSince1970: 2_000), recordingState: .completed)
        try await reopened.createMeeting(later)
        for item in [database] + sidecars { try assertPolicy(item, within: h.root) }
        let firstRestored = try await reopened.meeting(id: original.id)
        let laterRestored = try await reopened.meeting(id: later.id)
        XCTAssertEqual(firstRestored, original)
        XCTAssertEqual(laterRestored, later)
        try await reopened.close()

        let meetings = h.root.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: false)
        try PersistentFilePolicy.protectDirectory(meetings)
        let directory = meetings.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = try SegmentCAFWriter(directory: directory, sessionID: UUID(), maximumSegmentFrames: 16)
        try writer.append(signal(frames: 20))
        let checkpoint = directory.appendingPathComponent("capture-manifest.json")
        let initial = try JSONDecoder().decode(AudioCaptureManifest.self, from: Data(contentsOf: checkpoint))
        XCTAssertEqual(initial.totalFrames, 16)
        for item in [directory, checkpoint, directory.appendingPathComponent("segment-000000.caf")] {
            try assertPolicy(item, within: meetings)
        }
        let completed = try writer.finish()
        XCTAssertEqual(completed.totalFrames, 20)
        let durable = try JSONDecoder().decode(AudioCaptureManifest.self, from: Data(contentsOf: checkpoint))
        XCTAssertEqual(durable, completed)
        try assertPolicy(checkpoint, within: meetings)
        for segment in completed.segments {
            let path = directory.appendingPathComponent(segment.relativePath)
            try assertPolicy(path, within: meetings)
            XCTAssertEqual(try AVAudioFile(forReading: path).length, segment.frameCount)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.hasPrefix(".localminutes-write-") })
    }

    func testSymlinkPreflightAndAtomicReplacementPreserveOutsideFilesAndCleanTemporaryFiles() throws {
        let h = try StoragePolicyFixture(); defer { h.cleanup() }
        let inside = h.root.appendingPathComponent("Owned", isDirectory: true)
        let outside = h.root.appendingPathComponent("Outside", isDirectory: true)
        for item in [inside, outside] {
            try FileManager.default.createDirectory(at: item, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o755])
            try setBackupExcluded(false, on: item)
        }
        let sentinel = outside.appendingPathComponent("sentinel.txt")
        let original = Data("Original outside fixture remains byte-exact".utf8)
        try original.write(to: sentinel)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: sentinel.path)
        try setBackupExcluded(false, on: sentinel)
        let ownedFile = inside.appendingPathComponent("original.txt")
        try original.write(to: ownedFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ownedFile.path)
        try setBackupExcluded(false, on: ownedFile)
        let link = inside.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try PersistentFilePolicy.protectDirectory(inside))
        XCTAssertEqual(try permissions(inside), 0o755, "Tree preflight must fail before any attribute mutation")
        XCTAssertEqual(try permissions(ownedFile), 0o644)
        XCTAssertFalse(try excludedDirectly(inside))
        XCTAssertFalse(try excludedDirectly(ownedFile))
        XCTAssertThrowsError(try PersistentFilePolicy.writeAtomically(Data("Rejected".utf8),
            to: link.appendingPathComponent("new.txt"), within: inside))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("new.txt").path))
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
        XCTAssertEqual(try permissions(sentinel), 0o640)
        XCTAssertFalse(try excludedDirectly(sentinel))
        try FileManager.default.removeItem(at: link)

        let current = inside.appendingPathComponent("current.json")
        try original.write(to: current)
        let oldReader = try FileHandle(forReadingFrom: current)
        defer { try? oldReader.close() }
        let replacement = Data(repeating: 0x42, count: 8_193)
        try PersistentFilePolicy.writeAtomically(replacement, to: current, within: inside)
        XCTAssertEqual(try Data(contentsOf: current), replacement)
        XCTAssertEqual(try oldReader.readToEnd(), original,
            "The open original inode must survive a real atomic pathname replacement")
        try assertPolicy(current, within: inside)
        let overlong = inside.appendingPathComponent(String(repeating: "x", count: 300))
        XCTAssertThrowsError(try PersistentFilePolicy.writeAtomically(Data("Reject rename".utf8),
            to: overlong, within: inside)) { error in
            guard let policyError = error as? PersistentFilePolicyError,
                  case .posixFailure = policyError else {
                return XCTFail("Expected a real native publication failure after staging, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: current), replacement)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: inside.path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".localminutes-write-") },
                       "Both successful rename and failed native rename must remove owned temporary files")
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
    }
}
#endif
