#if os(iOS)
import Foundation
import SwiftUI
import XCTest
@testable import LocalMinutes

// Active test-first cases. Native assertion RED is still pending after harness
// failures; no app instrumentation, locked-device or two-hour pass is claimed.
// The fixture opens real app services and SQLite in its generated owned root.
@MainActor
private final class NativeAppMetricsFixture {
    let parent: URL
    let root: URL
    let services: LocalMinutesServices
    let application: RecordingApplication

    init() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .resolvingSymlinksInPath().standardizedFileURL
        parent = support.appendingPathComponent("LocalMinutesAppMetricsTests", isDirectory: true)
        root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        services = try LocalMinutesServices(rootURL: root)
        application = RecordingApplication(services: services)
    }

    func cleanup(file: StaticString = #filePath, line: UInt = #line) async {
        // No start/model/inference operation is admitted by these tests.
        if let snapshot = await application.owner?.snapshot(),
           snapshot.cleanupPending || snapshot.readiness.audioSessionActive {
            XCTFail("Unexpected live resources: retain the owned metrics fixture", file: file, line: line)
            return
        }
        do { try await services.store.close() }
        catch { XCTFail("Metrics fixture database did not close", file: file, line: line); return }
        guard parent.lastPathComponent == "LocalMinutesAppMetricsTests",
              root.deletingLastPathComponent().standardizedFileURL == parent,
              root.resolvingSymlinksInPath().standardizedFileURL == root,
              UUID(uuidString: root.lastPathComponent) != nil else {
            XCTFail("Refuse cleanup outside generated metrics root", file: file, line: line); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned app metrics fixture cleanup failed", file: file, line: line) }
    }
}

@MainActor
final class NativeAppMetricsTests: XCTestCase {
    private func withFixture(_ body: @MainActor (NativeAppMetricsFixture) async throws -> Void) async throws {
        let h = try NativeAppMetricsFixture()
        do { try await body(h) }
        catch { await h.cleanup(); throw error }
        await h.cleanup()
    }

    private func assertOwnedPolicy(_ url: URL, root: URL,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(root.path + "/"), file: file, line: line)
        try PersistentFilePolicy.validateItem(url, within: root)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue,
                       isDirectory ? 0o700 : 0o600, file: file, line: line)
        var cursor = url
        var excluded = false
        while cursor.path == root.path || cursor.path.hasPrefix(root.path + "/") {
            if try URL(fileURLWithPath: cursor.path).resourceValues(
                forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true { excluded = true; break }
            if cursor.path == root.path { break }
            cursor.deleteLastPathComponent()
        }
        XCTAssertTrue(excluded, "An actual owned ancestor must exclude this file from backup", file: file, line: line)
        // Simulator SDK metadata cannot establish encrypted locked-device access.
        let reported = (attributes[.protectionKey] as? FileProtectionType)?.rawValue ??
            (attributes[.protectionKey] as? String)
        if let reported {
            XCTAssertEqual(reported, FileProtectionType.completeUntilFirstUserAuthentication.rawValue,
                           file: file, line: line)
            print("APP_METRICS_PROTECTION SDK_METADATA_ONLY; physical locked access=UNVERIFIED")
        } else {
            print("APP_METRICS_PROTECTION UNVERIFIED: SDK getter nil; physical gate NOT_RUN")
        }
    }

    func testDefaultServicesRetainOneLiveRecorderWithActualBuildAndModelPins() async throws {
        try await withFixture { h in
            let appBundle = Bundle(for: LocalMinutesServices.self)
            let source = try XCTUnwrap(appBundle.object(forInfoDictionaryKey: "LocalMinutesSourceCommit") as? String,
                "Missing source stamping is a setup failure, not behavioral RED")
            XCTAssertEqual(source.utf8.count, 40)
            XCTAssertTrue(source.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
            let build = try XCTUnwrap(appBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            let buildNumber = try XCTUnwrap(Int(build))
            guard let recorder = h.services.metrics else {
                XCTFail("Actual default Services must retain nonnil metrics before any recording"); return
            }
            XCTAssertTrue(h.services.live.metricsRecorder === recorder,
                "A separate unused recorder does not instrument the app-owned CPU consumer")
            XCTAssertTrue(h.application.services === h.services)
            let snapshot = recorder.snapshot()
            XCTAssertEqual(snapshot.identity.sourceCommit, source)
            XCTAssertEqual(snapshot.identity.buildNumber, buildNumber)
            XCTAssertEqual(snapshot.identity.modelRevision, StreamingEnglishModel.manifest.revision)
            XCTAssertEqual(snapshot.identity.runtimeVersion, StreamingEnglishModel.manifest.runtimeVersion)
            XCTAssertEqual(snapshot.capturedSampleCount, 0)
            XCTAssertEqual(snapshot.processedSampleCount, 0)
            XCTAssertTrue(snapshot.errors.isEmpty)
            let installed = try await h.services.models.current(modelID: StreamingEnglishModel.manifest.modelID)
            XCTAssertNil(installed,
                "Diagnostics initialization must not download, install or pretend to load a model")
        }
    }

    func testAppScenePhaseControlRecordsTruthfulBoundedVisibilityCheckpoints() async throws {
        try await withFixture { h in
            // Direct control-boundary calls test forwarding and mapping. A
            // separate entry/UI test must cover SwiftUI scenePhase delivery.
            try h.application.recordScenePhase(.active)
            try h.application.recordScenePhase(.background)
            try h.application.recordScenePhase(.inactive)
            let initial = h.services.metrics?.snapshot()
            XCTAssertEqual(initial?.checkpoints.map(\.visibility), [.foreground, .background, .unknown])
            XCTAssertTrue(initial?.checkpoints.allSatisfy {
                $0.capturedSampleCount == 0 && $0.processedSampleCount == 0
            } ?? false, "A scene phase must never fabricate ASR progress or a locked-device claim")
            for index in 0..<200 {
                try h.application.recordScenePhase(index.isMultiple(of: 2) ? .active : .background)
            }
            let final = h.services.metrics?.snapshot()
            XCTAssertEqual(final?.checkpoints.count, 128)
            XCTAssertEqual(final?.checkpoints.last?.visibility, .background)
            let times = final?.checkpoints.map(\.monotonicNanoseconds) ?? []
            XCTAssertFalse(times.isEmpty)
            XCTAssertEqual(times, times.sorted())
            XCTAssertEqual(final?.capturedSampleCount, 0)
            XCTAssertEqual(final?.processedSampleCount, 0)
            XCTAssertEqual(final?.errors, [])
        }
    }

    func testAppPersistsProtectedAtomicMetricsJSONAndExportsOnlyValidatedFacts() async throws {
        try await withFixture { h in
            // Original non-sensitive sentinel text is intentionally stored in
            // real SQLite so the export must not copy meeting content or paths.
            let id = UUID()
            let sentinel = "Original diagnostics exclusion fixture words"
            try await h.services.store.createMeeting(.init(id: id, title: sentinel,
                createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
            try await h.services.store.appendFinalizedSegments([
                .init(id: UUID(), meetingID: id, sequence: 0, startSample: 0, endSample: 1_600,
                      text: sentinel, modelRevision: StreamingEnglishModel.manifest.revision)
            ], to: id)
            try h.application.recordScenePhase(.active)
            let firstURL: URL
            do { firstURL = try h.services.persistMetricsCheckpoint() }
            catch {
                XCTFail("App Services must publish a real protected JSON checkpoint: \(type(of: error))"); return
            }
            let firstBytes = try Data(contentsOf: firstURL)
            _ = try MetricsExportCodec.decodeValidated(firstBytes)
            try self.assertOwnedPolicy(firstURL, root: h.root)
            try self.assertOwnedPolicy(firstURL.deletingLastPathComponent(), root: h.root)
            let originalReader = try FileHandle(forReadingFrom: firstURL)
            defer { try? originalReader.close() }
            try h.application.recordScenePhase(.background)
            h.services.metrics?.recordError(.queueOverflow)
            let secondURL = try h.services.persistMetricsCheckpoint()
            XCTAssertEqual(secondURL, firstURL)
            let replacement = try Data(contentsOf: secondURL)
            XCTAssertNotEqual(replacement, firstBytes)
            XCTAssertEqual(try originalReader.readToEnd(), firstBytes,
                "An old inode reader must preserve the first bytes after real atomic replacement")
            let exported = try h.services.exportMetrics()
            XCTAssertEqual(exported, replacement, "Export returns the exact latest validated checkpoint")
            XCTAssertLessThanOrEqual(exported.count, 65_536)
            let decoded = try MetricsExportCodec.decodeValidated(exported)
            XCTAssertEqual(decoded, h.services.metrics?.snapshot())
            XCTAssertEqual(decoded.errors.map(\.category), [.queueOverflow])
            XCTAssertEqual(decoded.processedSampleCount, 0, "This is storage/visibility evidence, never inference")
            let text = try XCTUnwrap(String(data: exported, encoding: .utf8))
            XCTAssertFalse(text.contains(sentinel))
            XCTAssertFalse(text.contains(h.root.path))
            XCTAssertFalse(text.contains("transcript"))
            XCTAssertFalse(text.contains("credentials"))
            let leftovers = try FileManager.default.subpathsOfDirectory(atPath: h.root.path)
            XCTAssertFalse(leftovers.contains { $0.contains(".localminutes-write-") || $0.hasSuffix(".tmp") })
            try self.assertOwnedPolicy(secondURL, root: h.root)
        }
    }
}
#endif
