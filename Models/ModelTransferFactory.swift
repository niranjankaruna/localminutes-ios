import CryptoKit
import Darwin
import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

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
              ModelArtifactPath.components(artifact.fileName) != nil,
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

    public func discardProgress(for manifest: ModelManifest) throws {
        let root = appRootURL.appendingPathComponent("DownloadResume", isDirectory: true)
        let targets = try Set(manifest.artifacts.map { try checkpointDirectory(for: $0) })
        guard try Self.exists(root) else { return }
        try PersistentFilePolicy.validateItem(root, within: appRootURL)
        var locks: [Int32] = []
        defer { for descriptor in locks { Darwin.close(descriptor) } }
        var existing: [URL] = []
        // Validate and reserve every target before erasing any retained bytes.
        for target in targets {
            guard target.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path,
                  UUID(uuidString: target.lastPathComponent) != nil else { throw ModelInstallationError.invalidInstallation }
            guard try Self.exists(target) else { continue }
            try PersistentFilePolicy.validateItem(target, within: root)
            guard try FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw ModelInstallationError.invalidInstallation
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: target.path)
            guard Set(names).isSubset(of: ["partial.bin", "checkpoint.json", ".transfer.lock"]) else {
                throw ModelInstallationError.invalidInstallation
            }
            for name in names {
                let file = target.appendingPathComponent(name)
                try PersistentFilePolicy.validateItem(file, within: root)
                guard try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType == .typeRegular else {
                    throw ModelInstallationError.invalidInstallation
                }
            }
            let lock = target.appendingPathComponent(".transfer.lock")
            let descriptor = lock.path.withCString { Darwin.open($0, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600)) }
            guard descriptor >= 0 else { throw ModelInstallationError.invalidInstallation }
            locks.append(descriptor)
            guard ResumableModelDownload.lockExclusively(descriptor) else { throw ModelInstallationError.modelInUse }
            try PersistentFilePolicy.protectItem(lock, within: root)
            existing.append(target)
        }
        for target in existing {
            try PersistentFilePolicy.validateItem(target, within: root)
            try FileManager.default.removeItem(at: target)
        }
    }

    private static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return false }
    }
}
