import CryptoKit
import Foundation

/// App-retained construction boundary. Caches live beside Models, never inside
/// installer staging or installed-model inventory. Input artifacts are pinned.
public final class ModelTransferFactory: @unchecked Sendable {
    private let appRootURL: URL
    private let configuration: URLSessionConfiguration
    private let availableBytes: ModelAvailableBytes

    public init(appRootURL: URL, configuration: URLSessionConfiguration = .ephemeral,
                availableBytes: @escaping ModelAvailableBytes = { try ModelStoragePolicy.availableBytes(at: $0) }) {
        self.appRootURL = appRootURL.standardizedFileURL
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.availableBytes = availableBytes
    }

    public func makeManager() -> ModelInstallationManager {
        let models = appRootURL.appendingPathComponent("Models", isDirectory: true)
        let transport = HTTPSModelTransport(stagingRootURL: models.appendingPathComponent(".staging"),
            allowedHosts: ["huggingface.co", "us.aws.cdn.hf.co", "cdn-lfs.huggingface.co",
                           "cdn-lfs-us-1.hf.co", "cas-bridge.xethub.hf.co"], configuration: configuration,
            resumeRootURL: appRootURL.appendingPathComponent("DownloadResume", isDirectory: true))
        return ModelInstallationManager(rootURL: models, availableBytes: availableBytes,
            downloader: { [self] artifact, destination in
                try await transport.downloadResumable(artifact, to: destination,
                    checkpointDirectory: checkpointDirectory(for: artifact))
            })
    }

    /// Hash the complete immutable artifact pin, including repository URL and
    /// revision. Calculating a location never creates files or installs a model.
    public func checkpointDirectory(for artifact: ModelArtifact) throws -> URL {
        guard appRootURL.isFileURL, appRootURL.path != "/", artifact.byteCount > 0,
              !artifact.fileName.isEmpty, !artifact.fileName.contains("/"), !artifact.fileName.contains("\\"),
              artifact.sha256.utf8.count == 64 else { throw ModelInstallationError.invalidManifest }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hash = SHA256.hash(data: try encoder.encode(artifact)).map { String(format: "%02x", $0) }.joined()
        let hex = Array(hash.prefix(32))
        let id = [String(hex[0..<8]), String(hex[8..<12]), String(hex[12..<16]),
                  String(hex[16..<20]), String(hex[20..<32])].joined(separator: "-")
        guard let uuid = UUID(uuidString: id) else { throw ModelInstallationError.invalidManifest }
        return appRootURL.appendingPathComponent("DownloadResume", isDirectory: true)
            .appendingPathComponent(uuid.uuidString, isDirectory: true)
    }

    /// TEST-FIRST: removal must also free retained download bytes. This hook
    /// deliberately does nothing until the new real-cache assertion runs RED.
    public func discardProgress(for manifest: ModelManifest) throws {}
}
