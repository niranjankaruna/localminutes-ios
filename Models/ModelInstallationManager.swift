import Foundation

// Minimal compileable no-op interface for hosted behavioral RED. Do not replace
// these errors/empty reads with behavior until root records actual assertions.
public enum ModelInstallationError: Error, Equatable, Sendable {
    case notImplemented
    case invalidManifest
    case missingFile(String)
    case unexpectedFile(String)
    case sizeMismatch(String)
    case checksumMismatch(String)
    case unsafeFile(String)
    case insufficientSpace
    case downloadFailed
    case modelMissing
    case modelInUse
    case invalidLease
    case invalidInstallation
}

public struct VerifiedModel: Equatable, Sendable {
    public let manifest: ModelManifest
    public let installationID: UUID
    public let directoryURL: URL
    public let files: [ModelFileRole: URL]
}

public struct ModelLease: Equatable, Sendable {
    public let model: VerifiedModel
    public let token: UUID
}

public typealias ModelAvailableBytes = @Sendable (URL) throws -> Int64
public typealias ModelArtifactDownloader = @Sendable (ModelArtifact, URL) async throws -> Void

public actor ModelInstallationManager {
    public init(rootURL: URL, availableBytes: @escaping ModelAvailableBytes,
                downloader: ModelArtifactDownloader? = nil) {}

    public func importDirectory(_ sourceURL: URL, manifest: ModelManifest) async throws -> VerifiedModel {
        throw ModelInstallationError.notImplemented
    }

    public func download(_ manifest: ModelManifest) async throws -> VerifiedModel {
        throw ModelInstallationError.notImplemented
    }

    public func current(modelID: String) throws -> VerifiedModel? { nil }

    public func acquire(modelID: String) throws -> ModelLease {
        throw ModelInstallationError.notImplemented
    }

    public func release(_ lease: ModelLease) throws { throw ModelInstallationError.notImplemented }
    public func remove(modelID: String) throws { throw ModelInstallationError.notImplemented }
}
