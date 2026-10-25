#if os(iOS)
import Foundation
import UIKit

/// Public build provenance and observed metadata only. The report is not a
/// physical-device acceptance verdict and has no path/content/name fields.
struct StoragePrivacyReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceCommit: String
    let appVersion: String
    let buildNumber: String
    let protectedDataAvailable: Bool
    let audit: StorageAuditReport
}

enum StoragePrivacyReportError: Error, Equatable {
    case notReady, recordingActive, busy, invalidBuildIdentity
}

extension LocalMinutesServices {
    /// The caller supplies the actual app-owned coordinator snapshot. Admission
    /// is synchronous after that observation and retained until the worker joins.
    func storagePrivacyReport(recording: RecordingSnapshot?) async throws -> StoragePrivacyReport {
        try Task.checkCancellation()
        guard startup.state == .ready, let recording else { throw StoragePrivacyReportError.notReady }
        guard !recording.cleanupPending, !recording.readiness.audioSessionActive,
              ![.preparing, .recording, .stopping].contains(recording.phase) else {
            throw StoragePrivacyReportError.recordingActive
        }
        guard canPrepareStoragePrivacyReport, let admission = heavyAdmission,
              admission.snapshot().phase == .idle else { throw StoragePrivacyReportError.busy }
        guard let identity = AppBuildIdentity.current(),
              let source = Bundle.main.object(forInfoDictionaryKey: "LocalMinutesSourceCommit") as? String,
              source.utf8.count == 40,
              source.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              identity.version.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
              }), identity.build.utf8.allSatisfy({ (48...57).contains($0) }),
              let buildNumber = Int(identity.build), buildNumber > 0 else {
            throw StoragePrivacyReportError.invalidBuildIdentity
        }
        let root = try storagePrivacyInspectionRoot()
        let resource = StoragePrivacyAuditWork()
        let lease: HeavyModelUseLease
        do { lease = try admission.acquire(purpose: .libraryMaintenance, requestID: UUID(), resource: resource) }
        catch { throw StoragePrivacyReportError.busy }
        do { try beginLibraryMaintenance() }
        catch {
            try? await admission.cancelAndDrain(lease)
            throw StoragePrivacyReportError.busy
        }
        defer { endLibraryMaintenance() }
        let protectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
        let worker = Task.detached(priority: .utility) {
            StorageAuditInspector.inspect(rootURL: root)
        }
        resource.worker = worker
        let audit = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        // Cleanup has its own retained task in the shared gate. Even a cancelled
        // caller cannot release admission while metadata enumeration is running.
        do { try await admission.cancelAndDrain(lease) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw StoragePrivacyReportError.busy
        }
        try Task.checkCancellation()
        return StoragePrivacyReport(schemaVersion: 1, sourceCommit: source,
            appVersion: identity.version, buildNumber: identity.build,
            protectedDataAvailable: protectedDataAvailable, audit: audit)
    }

    /// Return bytes for explicit user sharing; never publish or write an audit
    /// file beside meeting content as a side effect of preparing this report.
    func exportStoragePrivacyReport(recording: RecordingSnapshot?) async throws -> Data {
        let report = try await storagePrivacyReport(recording: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report)
    }

    private func storagePrivacyInspectionRoot() throws -> URL {
        // Foundation's trusted system path may contain /var -> /private/var on
        // iOS. Resolve only that ancestor for the exact default app location.
        // The owned LocalMinutes root and all descendants remain un-resolved so
        // the inspector can reject symlinks rather than concealing them.
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false).standardizedFileURL
        let defaultRoot = support.appendingPathComponent("LocalMinutes", isDirectory: true).standardizedFileURL
        guard applicationRoot.standardizedFileURL == defaultRoot else { return applicationRoot }
        return support.resolvingSymlinksInPath().appendingPathComponent("LocalMinutes", isDirectory: true)
    }
}

@MainActor
private final class StoragePrivacyAuditWork: HeavyModelResourceLifecycle {
    var worker: Task<StorageAuditReport, Never>?
    private var settled = false

    func requestCancellation() { worker?.cancel() }
    func drain() async throws {
        if let worker { _ = await worker.value }
        settled = true
    }
    func unloadAndReleaseModel() async throws {
        guard settled else { throw HeavyModelAdmissionError.cleanupFailed }
    }
}
#endif
