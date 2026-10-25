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
    /// The caller supplies the actual app-owned coordinator snapshot. This
    /// metadata-only seam awaits hosted behavioral RED before implementation.
    func storagePrivacyReport(recording: RecordingSnapshot?) async throws -> StoragePrivacyReport {
        throw StoragePrivacyReportError.notReady
    }

    /// Return bytes for explicit user sharing; never publish or write an audit
    /// file beside meeting content as a side effect of preparing this report.
    func exportStoragePrivacyReport(recording: RecordingSnapshot?) async throws -> Data {
        throw StoragePrivacyReportError.notReady
    }
}
#endif
