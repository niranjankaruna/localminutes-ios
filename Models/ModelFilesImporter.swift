import Foundation

/// OS permission boundary only. A granted scope remains owned until every
/// actual copy/hash/installer operation settles, including cancellation/error.
public protocol ModelFileSecurityScope: Sendable {
    func begin(_ url: URL) -> Bool
    func end(_ url: URL)
}

public struct FoundationModelFileSecurityScope: ModelFileSecurityScope {
    public init() {}
    // TEST-FIRST native adapter seams. No OS access behavior before RED.
    public func begin(_ url: URL) -> Bool { false }
    public func end(_ url: URL) {}
}

public enum ModelFileImportError: Error, Equatable, Sendable {
    case notImplemented, invalidSelection, accessDenied, unsafeSource, unsafeStaging
}

/// Import exactly the selected expected basenames. Sources may be in different
/// Files directories. The actual manager owns hash/size/license validation and
/// atomic installation; original Files resources must never be modified.
public actor ModelFilesImporter {
    public init(manager: ModelInstallationManager, stagingRootURL: URL) {}

    // TEST-FIRST no-op: no copying, access acquisition or installation yet.
    public func importFiles(_ files: [URL], manifest: ModelManifest,
                            access: any ModelFileSecurityScope = FoundationModelFileSecurityScope()) async throws -> VerifiedModel {
        throw ModelFileImportError.notImplemented
    }
}
