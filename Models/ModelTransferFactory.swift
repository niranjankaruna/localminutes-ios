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

    /// TEST-FIRST extraction retains fresh-download behavior until integration
    /// RED. This is a real manager/transport, not an installation/inference fake.
    public func makeManager() -> ModelInstallationManager {
        let models = appRootURL.appendingPathComponent("Models", isDirectory: true)
        let transport = HTTPSModelTransport(stagingRootURL: models.appendingPathComponent(".staging"),
            allowedHosts: ["huggingface.co", "us.aws.cdn.hf.co", "cdn-lfs.huggingface.co",
                           "cdn-lfs-us-1.hf.co", "cas-bridge.xethub.hf.co"], configuration: configuration)
        return ModelInstallationManager(rootURL: models, availableBytes: availableBytes,
            downloader: { artifact, destination in try await transport.download(artifact, to: destination) })
    }

    /// TEST-FIRST no-op identity seam. A fixed UUID deliberately cannot
    /// distinguish different immutable files until the new contracts run RED.
    public func checkpointDirectory(for artifact: ModelArtifact) throws -> URL {
        appRootURL.appendingPathComponent("DownloadResume", isDirectory: true)
            .appendingPathComponent("00000000-0000-0000-0000-000000000000", isDirectory: true)
    }
}
