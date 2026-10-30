#if os(iOS)
import Foundation
import UIKit
import XCTest
@testable import LocalMinutes

/// Actual owned app root and UIKit availability observation, plus explicit
/// domain-state guards. No microphone, lock-state, encryption or phone pass.
@MainActor
final class NativeStoragePrivacyReportTests: XCTestCase {
    func testReadyServicesReportActualOwnedRootCountBuildAndUIKitProtectedDataObservationWithoutChangingCanary() async throws {
        try await fixture { f in
            let beforeBytes = try Data(contentsOf: f.canary)
            let beforeAttributes = try FileManager.default.attributesOfItem(atPath: f.canary.path)
            let expectedCount = try f.itemCount()
            let report = try await f.services.storagePrivacyReport(recording: self.idle)
            XCTAssertEqual(report.schemaVersion, 1)
            XCTAssertEqual(report.audit.status, .complete)
            XCTAssertEqual(report.audit.inspectedItemCount, expectedCount,
                "Inspect the actual complete application root, not a separate empty diagnostic directory")
            XCTAssertEqual(report.audit.groups.reduce(0) { $0 + $1.itemCount }, expectedCount)
            XCTAssertEqual(report.sourceCommit, Bundle.main.object(forInfoDictionaryKey: "LocalMinutesSourceCommit") as? String)
            XCTAssertEqual(report.appVersion, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            XCTAssertEqual(report.buildNumber, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            XCTAssertEqual(report.protectedDataAvailable, UIApplication.shared.isProtectedDataAvailable,
                "Report actual UIKit availability; it does not establish a locked-screen protection result")
#if targetEnvironment(simulator)
            XCTAssertEqual(report.audit.environment, .iOSSimulator)
#else
            XCTAssertEqual(report.audit.environment, .iOSDevice)
#endif
            XCTAssertEqual(try Data(contentsOf: f.canary), beforeBytes)
            let afterAttributes = try FileManager.default.attributesOfItem(atPath: f.canary.path)
            XCTAssertEqual(afterAttributes[.modificationDate] as? Date, beforeAttributes[.modificationDate] as? Date)
            XCTAssertEqual(String(describing: afterAttributes[.protectionKey]), String(describing: beforeAttributes[.protectionKey]))
        }
    }

    func testExportHasOnlyFixedMetadataAndCountsNeverSandboxPathsNamesMeetingTextOrDeviceVerdicts() async throws {
        try await fixture { f in
            let count = try f.itemCount()
            let bytes = try await f.services.exportStoragePrivacyReport(recording: self.idle)
            let report = try JSONDecoder().decode(StoragePrivacyReport.self, from: bytes)
            XCTAssertEqual(report.audit.status, .complete)
            XCTAssertEqual(report.audit.inspectedItemCount, count)
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["schemaVersion", "sourceCommit", "appVersion", "buildNumber", "protectedDataAvailable", "audit"])
            let audit = try XCTUnwrap(object["audit"] as? [String: Any])
            XCTAssertEqual(Set(audit.keys), ["schemaVersion", "environment", "status", "inspectedItemCount", "groups"])
            let text = String(decoding: bytes, as: UTF8.self)
            for privateValue in [f.root.path, f.root.lastPathComponent, f.canary.lastPathComponent,
                                 StoragePrivacyFixture.privateText, "VERIFIED_COMPLETE", "deviceLocked"] {
                XCTAssertFalse(text.contains(privateValue), "Metadata export must not leak private values or fabricate physical verdicts")
            }
            XCTAssertEqual(try Data(contentsOf: f.canary), Data(StoragePrivacyFixture.privateText.utf8))
            XCTAssertEqual(try f.itemCount(), count, "Preparing share bytes must not create files under the audited root")
        }
    }

    func testMissingCoordinatorSnapshotFailsClosedInsteadOfAssumingRecordingIsIdle() async throws {
        try await fixture { f in
            do { _ = try await f.services.storagePrivacyReport(recording: nil); XCTFail("Missing recording authority must fail closed") }
            catch { XCTAssertEqual(error as? StoragePrivacyReportError, .notReady) }
        }
    }

    func testUninitializedLibraryIsNotAssumedSafeToInspect() async throws {
        try await fixture(initialized: false) { f in
            do { _ = try await f.services.storagePrivacyReport(recording: self.idle); XCTFail("Startup must complete before inspection") }
            catch { XCTAssertEqual(error as? StoragePrivacyReportError, .notReady) }
        }
    }

    func testActivePreparationRecordingStoppingAndUnreleasedAudioDenyReportAndExport() async throws {
        try await fixture { f in
            var states = [RecordingPhase.preparing, .recording, .stopping].map {
                RecordingSnapshot(phase: $0, sessionID: UUID(), readiness: .init(), failure: nil, cleanupPending: false)
            }
            states.append(.init(phase: .completed, sessionID: UUID(), readiness: .init(), failure: nil, cleanupPending: true))
            states.append(.init(phase: .idle, sessionID: nil, readiness: .init(audioSessionActive: true), failure: nil, cleanupPending: false))
            for state in states {
                do { _ = try await f.services.storagePrivacyReport(recording: state); XCTFail("Capture work must exclude auditing") }
                catch { XCTAssertEqual(error as? StoragePrivacyReportError, .recordingActive) }
                do { _ = try await f.services.exportStoragePrivacyReport(recording: state); XCTFail("Export must preserve capture admission guards") }
                catch { XCTAssertEqual(error as? StoragePrivacyReportError, .recordingActive) }
            }
        }
    }

    func testActualHeavyAdmissionLeaseDeniesReportWithoutCancellingItsOwner() async throws {
        try await fixture { f in
            let admission = try XCTUnwrap(f.services.heavyAdmission)
            for purpose in HeavyModelPurpose.allCases {
                let resource = StoragePrivacyHeldResource()
                let lease = try admission.acquire(purpose: purpose, requestID: UUID(), resource: resource)
                do { _ = try await f.services.storagePrivacyReport(recording: self.idle); XCTFail("Busy heavy-model work must exclude auditing") }
                catch { XCTAssertEqual(error as? StoragePrivacyReportError, .busy) }
                XCTAssertEqual(admission.snapshot().lease, lease)
                XCTAssertFalse(resource.cancelled, "Read-only diagnostics cannot cancel another operation")
                try await admission.cancelAndDrain(lease)
            }
        }
    }

    func testActualLibraryMaintenanceDeniesReportUntilMaintenanceEnds() async throws {
        try await fixture { f in
            try f.services.beginLibraryMaintenance()
            do { _ = try await f.services.storagePrivacyReport(recording: self.idle); XCTFail("Library replacement must exclude auditing") }
            catch { XCTAssertEqual(error as? StoragePrivacyReportError, .busy) }
            f.services.endLibraryMaintenance()
            let resumed = try await f.services.storagePrivacyReport(recording: self.idle)
            XCTAssertEqual(resumed.audit.status, .complete)
        }
    }

    private var idle: RecordingSnapshot {
        .init(phase: .idle, sessionID: nil, readiness: .init(), failure: nil, cleanupPending: false)
    }

    private func fixture(initialized: Bool = true, _ body: @MainActor (StoragePrivacyFixture) async throws -> Void) async throws {
        let f = try StoragePrivacyFixture()
        if initialized { await f.services.initialize() }
        do { try await body(f) }
        catch { try? await f.services.store.close(); try? f.remove(); throw error }
        try await f.services.store.close()
        try f.remove()
    }
}

@MainActor
private final class StoragePrivacyHeldResource: HeavyModelResourceLifecycle {
    private(set) var cancelled = false
    func requestCancellation() { cancelled = true }
    func drain() async throws {}
    func unloadAndReleaseModel() async throws {}
}

@MainActor
private struct StoragePrivacyFixture {
    static let privateText = "Original synthetic private meeting transcript and model-output canary."
    let parent: URL
    let root: URL
    let canary: URL
    let services: LocalMinutesServices

    init() throws {
        parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        root = parent.appendingPathComponent("localminutes-storage-privacy-\(UUID().uuidString)", isDirectory: true)
        services = try LocalMinutesServices(rootURL: root)
        canary = root.appendingPathComponent("private-person-and-meeting-name.txt")
        try PersistentFilePolicy.writeAtomically(Data(Self.privateText.utf8), to: canary, within: root)
    }

    func itemCount() throws -> Int {
        func count(_ directory: URL) throws -> Int {
            var result = 1
            for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let type = try FileManager.default.attributesOfItem(atPath: item.path)[.type] as? FileAttributeType
                if type == .typeDirectory { result += try count(item) }
                else { result += 1 }
            }
            return result
        }
        return try count(root)
    }

    func remove() throws {
        let prefix = "localminutes-storage-privacy-"
        guard root.deletingLastPathComponent() == parent, root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside owned native privacy-report fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
