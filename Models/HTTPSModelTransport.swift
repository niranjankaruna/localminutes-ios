import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

// The transfer owns only operation staging. Installation and inference readiness
// remain the verified model manager's and native recognizer's responsibilities.
public enum ModelTransportError: Error, Equatable, Sendable {
    case notImplemented, insecureURL, unapprovedHost, invalidDestination
    case httpStatus(Int)
    case sizeMismatch, networkFailure, invalidResumeState, invalidRangeResponse
}

public struct ModelDownloadCheckpoint: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let downloadURL: URL
    public let revision: String
    public let fileName: String
    public let expectedByteCount: Int64
    public let sha256: String
    public let strongETag: String
    public let receivedByteCount: Int64
    public let partialSHA256: String
    public init(schemaVersion: Int = 1, downloadURL: URL, revision: String, fileName: String,
                expectedByteCount: Int64, sha256: String, strongETag: String,
                receivedByteCount: Int64, partialSHA256: String) {
        self.schemaVersion = schemaVersion; self.downloadURL = downloadURL
        self.revision = revision; self.fileName = fileName; self.expectedByteCount = expectedByteCount
        self.sha256 = sha256; self.strongETag = strongETag
        self.receivedByteCount = receivedByteCount; self.partialSHA256 = partialSHA256
    }
}

public final class HTTPSModelTransport: @unchecked Sendable {
    private let stagingRootURL: URL
    private let allowedHosts: Set<String>
    private let session: URLSession
    private let resumeRootURL: URL?

    public init(stagingRootURL: URL, allowedHosts: Set<String>,
                configuration: URLSessionConfiguration = .ephemeral, resumeRootURL: URL? = nil) {
        self.stagingRootURL = stagingRootURL.standardizedFileURL
        self.resumeRootURL = resumeRootURL?.standardizedFileURL
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        let policy = ModelDownloadRedirectPolicy(allowedHosts: allowedHosts)
        let options = configuration.copy() as! URLSessionConfiguration
        options.httpShouldSetCookies = false
        options.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: options, delegate: policy, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// checkpointDirectory is one owned UUID child of resumeRootURL,
    /// separate from the installer's disposable .staging directory. Layout is
    /// partial.bin + checkpoint.json. Checkpoints bind all immutable metadata
    /// and the retained prefix digest; only a strong ETag authorizes If-Range.
    /// This method can publish only the operation staging file, never current.json.
    public func downloadResumable(_ artifact: ModelArtifact, to destination: URL,
                                  checkpointDirectory: URL) async throws {
        try Task.checkCancellation()
        guard let resumeRootURL else { throw ModelTransportError.invalidDestination }
        let operation = ResumableModelDownload(artifact: artifact, destination: destination,
            stagingRoot: stagingRootURL, resumeRoot: resumeRootURL, directory: checkpointDirectory,
            allowedHosts: allowedHosts, configuration: session.configuration)
        try await operation.run()
    }

    public func download(_ artifact: ModelArtifact, to destination: URL) async throws {
        try Task.checkCancellation()
        try validateRoute(artifact.downloadURL)
        try validateDestination(destination, artifact: artifact)
        var temporary: URL?
        var published = false
        defer {
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
        }
        do {
            let (location, response) = try await session.download(for: URLRequest(url: artifact.downloadURL))
            temporary = location
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, let finalURL = http.url else {
                throw ModelTransportError.networkFailure
            }
            try validateRoute(finalURL)
            guard http.statusCode == 200 else { throw ModelTransportError.httpStatus(http.statusCode) }
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == artifact.byteCount else {
                throw ModelTransportError.sizeMismatch
            }
            try validateDestination(destination, artifact: artifact)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: location, to: destination)
            published = true
            try Task.checkCancellation()
        } catch {
            if published { try? FileManager.default.removeItem(at: destination) }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw CancellationError()
            }
            if let error = error as? ModelTransportError { throw error }
            throw ModelTransportError.networkFailure
        }
    }

    private func validateRoute(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw ModelTransportError.insecureURL }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil else { throw ModelTransportError.unapprovedHost }
    }

    private func validateDestination(_ destination: URL, artifact: ModelArtifact) throws {
        let directory = destination.deletingLastPathComponent().standardizedFileURL
        guard ModelArtifactPath.operationRoot(destination: destination, fileName: artifact.fileName, stagingRoot: stagingRootURL) != nil else {
            throw ModelTransportError.invalidDestination
        }
        for url in [stagingRootURL, directory] {
            guard (try? PersistentFilePolicy.validateItem(url, within: stagingRootURL)) != nil,
                  (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory else {
                throw ModelTransportError.invalidDestination
            }
        }
        let values = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true,
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw ModelTransportError.invalidDestination
        }
    }
}

public final class ModelDownloadRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedHosts: Set<String>
    public init(allowedHosts: Set<String>) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        super.init()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public enum ModelStoragePolicy {
    public static func availableBytes(at directory: URL) throws -> Int64 {
        let values = try directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey
        ])
        return max(0, values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0)
    }

    public static func protectPersistentDirectory(_ directory: URL) throws {
        try PersistentFilePolicy.protectDirectory(directory)
    }
}
