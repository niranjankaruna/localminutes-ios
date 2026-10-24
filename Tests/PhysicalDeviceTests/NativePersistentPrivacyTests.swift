#if os(iOS)
import AVFoundation
import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import LocalMinutes

// Actual iOS filesystem attributes only. These cases neither lock a simulator
// nor establish physical encryption/accessibility, backup upload, or renewal.
@MainActor
private final class PrivacyOwnedDirectory {
    let support: URL
    let parent: URL
    let root: URL

    init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let parent = support.appendingPathComponent("LocalMinutesPrivacyTests", isDirectory: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.support = support; self.parent = parent; self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) {
        guard root.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL,
              parent.deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL,
              parent.lastPathComponent == "LocalMinutesPrivacyTests",
              UUID(uuidString: root.lastPathComponent) != nil else {
            XCTFail("Unsafe privacy fixture cleanup target", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned privacy fixture cleanup failed", file: file, line: line) }
    }
}

@MainActor
private final class PrivacyWALConnection {
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
final class NativePersistentPrivacyTests: XCTestCase {
    private func protection(_ url: URL) throws -> String? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = attributes[.protectionKey]
        return (value as? FileProtectionType)?.rawValue ?? (value as? String)
    }

    private func assertPrivacy(_ url: URL, within root: URL,
        file: StaticString = #filePath, line: UInt = #line) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Required persistent file/directory does not exist: \(url.lastPathComponent)", file: file, line: line)
            return
        }
        XCTAssertEqual(try protection(url), FileProtectionType.completeUntilFirstUserAuthentication.rawValue,
            "Every file needed during locked continuation must retain the explicit after-first-unlock class",
            file: file, line: line)
        var current = url.standardizedFileURL
        let boundary = root.standardizedFileURL
        var excluded = false
        // Backup exclusion on a containing directory applies to its contents.
        // Do not require redundant per-file flags when an owned ancestor has it.
        while current.path == boundary.path || current.path.hasPrefix(boundary.path + "/") {
            let fresh = URL(fileURLWithPath: current.path)
            if try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true {
                excluded = true; break
            }
            if current == boundary { break }
            current.deleteLastPathComponent()
        }
        XCTAssertTrue(excluded, "Persistent private content must be excluded from system backup",
                      file: file, line: line)
    }

    private func meeting(_ id: UUID = UUID()) -> MeetingRecord {
        MeetingRecord(id: id, title: "Original privacy test fixture",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recording)
    }

    private func signal(frames: Int) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<frames { samples[index] = Float(index % 16) / 128 }
        return buffer
    }

    private func modelSource(in root: URL) throws -> (URL, ModelManifest) {
        let source = root.appendingPathComponent("Import", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let revision = String(repeating: "e", count: 40)
        let files: [(ModelFileRole, String)] = [(.encoder, "encoder.onnx"), (.decoder, "decoder.onnx"),
                                                (.joiner, "joiner.onnx"), (.tokens, "tokens.txt")]
        let artifacts = try files.map { role, name in
            let data = Data("Original non-model privacy fixture: \(name)".utf8)
            let file = source.appendingPathComponent(name)
            try data.write(to: file)
            // Files import can carry stronger protection. The persistent copy
            // must receive the app's explicitly selected locked-use policy.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
            return ModelArtifact(role: role, fileName: name, byteCount: Int64(data.count),
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                downloadURL: URL(string: "https://huggingface.co/example/privacy-fixture/resolve/\(revision)/\(name)")!,
                digestProvenance: .independentlyDownloaded)
        }
        return (source, ModelManifest(modelID: "privacy-fixture", purpose: .speechRecognition,
            upstreamRepository: URL(string: "https://huggingface.co/example/privacy-fixture")!,
            revision: revision, licenseIdentifier: "CC0-1.0",
            licenseNotice: "Original LocalMinutes non-model privacy fixture, CC0-1.0.",
            runtimeVersion: "fixture-only", sampleRate: 16_000, featureDimension: 80, artifacts: artifacts))
    }

    func testDefaultServicesUseProtectedExcludedApplicationSupportRoots() async throws {
        // Inspect the actual default paths without deleting, replacing or
        // inserting records into the owner's default database/model directory.
        let services = try LocalMinutesServices()
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("LocalMinutes", isDirectory: true)
        XCTAssertEqual(services.meetingsDirectory.standardizedFileURL,
            root.appendingPathComponent("Meetings", isDirectory: true).standardizedFileURL)
        XCTAssertFalse(root.path.contains("/Caches/"))
        XCTAssertFalse(root.path.contains("/tmp/"))
        for url in [root, root.appendingPathComponent("Models"), root.appendingPathComponent("Meetings"),
                    root.appendingPathComponent("meetings.sqlite")] {
            try assertPrivacy(url, within: root)
        }
        try await services.store.close()
    }

    func testExistingModelAndMetadataTreeIsProtectedWithoutChangingBytes() throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let installed = h.root.appendingPathComponent("Models/fixture/revision/installation", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let model = installed.appendingPathComponent("original-fixture.onnx")
        let manifest = installed.appendingPathComponent("manifest.json")
        let bytes = Data("Original non-model bytes".utf8)
        let metadata = Data("{\"originalFixture\":true}".utf8)
        try bytes.write(to: model); try metadata.write(to: manifest)
        try ModelStoragePolicy.protectPersistentDirectory(h.root)
        for url in [h.root, h.root.appendingPathComponent("Models"),
                    h.root.appendingPathComponent("Models/fixture"),
                    h.root.appendingPathComponent("Models/fixture/revision"), installed, model, manifest] {
            try assertPrivacy(url, within: h.root)
        }
        XCTAssertEqual(try Data(contentsOf: model), bytes)
        XCTAssertEqual(try Data(contentsOf: manifest), metadata)
    }

    func testNewVerifiedModelImportReceivesPersistentPrivacyInsteadOfSourceProtection() async throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let modelRoot = h.root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: false)
        try ModelStoragePolicy.protectPersistentDirectory(modelRoot)
        let (source, manifest) = try modelSource(in: h.root)
        let manager = ModelInstallationManager(rootURL: modelRoot,
            availableBytes: { try ModelStoragePolicy.availableBytes(at: $0) })
        let installed = try await manager.importDirectory(source, manifest: manifest)
        for file in installed.files.values { try assertPrivacy(file, within: modelRoot) }
        try assertPrivacy(installed.directoryURL, within: modelRoot)
        try assertPrivacy(installed.directoryURL.appendingPathComponent("manifest.json"), within: modelRoot)
        try assertPrivacy(modelRoot.appendingPathComponent(manifest.modelID).appendingPathComponent("current.json"), within: modelRoot)
        for artifact in manifest.artifacts {
            XCTAssertEqual(try protection(source.appendingPathComponent(artifact.fileName)),
                           FileProtectionType.complete.rawValue, "Source import privacy must remain unchanged")
        }
    }

    func testActualSQLiteDatabaseWALAndSHMAreProtectedAndRowsSurviveReopen() async throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let database = h.root.appendingPathComponent("meetings.sqlite")
        let wal = try PrivacyWALConnection(database: database)
        defer { wal.close() }
        let store = try SQLiteMeetingStore(databaseURL: database)
        let record = meeting()
        try await store.createMeeting(record)
        let sidecars = [URL(fileURLWithPath: database.path + "-wal"), URL(fileURLWithPath: database.path + "-shm")]
        XCTAssertTrue(sidecars.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
                      "The test must create real SQLite sidecars before checking their privacy")
        try ModelStoragePolicy.protectPersistentDirectory(h.root)
        for file in [database] + sidecars { try assertPrivacy(file, within: h.root) }
        try await store.close()
        wal.close()
        let reopened = try SQLiteMeetingStore(databaseURL: database)
        let restored = try await reopened.meeting(id: record.id)
        XCTAssertEqual(restored, record)
        try assertPrivacy(database, within: h.root)
        try await reopened.close()
    }

    func testSQLiteSidecarsRecreatedAfterReopenRetainPersistentPrivacy() async throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let database = h.root.appendingPathComponent("meetings.sqlite")
        let wal = try PrivacyWALConnection(database: database)
        defer { wal.close() }
        let first = try SQLiteMeetingStore(databaseURL: database)
        try await first.createMeeting(meeting())
        try ModelStoragePolicy.protectPersistentDirectory(h.root)
        try await first.close()
        wal.close()
        let sidecars = [URL(fileURLWithPath: database.path + "-wal"), URL(fileURLWithPath: database.path + "-shm")]
        XCTAssertTrue(sidecars.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
                      "Old sidecars must be gone so their re-creation is actually exercised")
        let reopened = try SQLiteMeetingStore(databaseURL: database)
        let later = meeting()
        try await reopened.createMeeting(later)
        for file in [database] + sidecars { try assertPrivacy(file, within: h.root) }
        let persisted = try await reopened.meeting(id: later.id)
        XCTAssertEqual(persisted, later)
        try await reopened.close()
    }

    func testNewCAFSegmentsAndAtomicManifestStayPrivateBeforeAndAfterFinish() throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let meetings = h.root.appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: false)
        try ModelStoragePolicy.protectPersistentDirectory(meetings)
        let directory = meetings.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer = try SegmentCAFWriter(directory: directory, sessionID: UUID(), maximumSegmentFrames: 16)
        try writer.append(signal(frames: 20))
        let checkpoint = directory.appendingPathComponent("capture-manifest.json")
        let first = directory.appendingPathComponent("segment-000000.caf")
        try assertPrivacy(directory, within: meetings)
        try assertPrivacy(first, within: meetings)
        try assertPrivacy(checkpoint, within: meetings)
        XCTAssertEqual(try AVAudioFile(forReading: first).length, 16)
        let final = try writer.finish()
        XCTAssertEqual(final.totalFrames, 20)
        for segment in final.segments { try assertPrivacy(directory.appendingPathComponent(segment.relativePath), within: meetings) }
        try assertPrivacy(checkpoint, within: meetings)
        let stored = try JSONDecoder().decode(AudioCaptureManifest.self, from: Data(contentsOf: checkpoint))
        XCTAssertEqual(stored, final)
    }

    func testRecursivePrivacyPolicyRejectsSymlinksWithoutChangingOutsideFiles() throws {
        let h = try PrivacyOwnedDirectory(); defer { h.cleanup() }
        let inside = h.root.appendingPathComponent("Models", isDirectory: true)
        let outside = h.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("original-fixture.txt")
        let bytes = Data("Outside original fixture remains unchanged".utf8)
        try bytes.write(to: sentinel)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: sentinel.path)
        var external = sentinel
        var values = URLResourceValues(); values.isExcludedFromBackup = false
        try external.setResourceValues(values)
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertThrowsError(try ModelStoragePolicy.protectPersistentDirectory(inside))
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        XCTAssertEqual(try protection(sentinel), FileProtectionType.complete.rawValue)
        XCTAssertNotEqual(try URL(fileURLWithPath: sentinel.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
}
#endif
