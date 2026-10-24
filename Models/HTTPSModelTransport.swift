import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

// The transfer owns only operation staging. Installation and inference readiness
// remain the verified model manager's and native recognizer's responsibilities.
public enum ModelTransportError: Error, Equatable, Sendable {
    case notImplemented, insecureURL, unapprovedHost, invalidDestination
    case httpStatus(Int)
    case sizeMismatch, networkFailure
}

public final class HTTPSModelTransport: @unchecked Sendable {
    private let stagingRootURL: URL
    private let allowedHosts: Set<String>
    private let session: URLSession

    public init(stagingRootURL: URL, allowedHosts: Set<String>,
                configuration: URLSessionConfiguration = .ephemeral) {
        self.stagingRootURL = stagingRootURL.standardizedFileURL
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        let policy = ModelDownloadRedirectPolicy(allowedHosts: allowedHosts)
        let options = configuration.copy() as! URLSessionConfiguration
        options.httpShouldSetCookies = false
        options.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: options, delegate: policy, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

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
        guard destination.isFileURL, destination.lastPathComponent == artifact.fileName,
              directory.deletingLastPathComponent().standardizedFileURL.path == stagingRootURL.path,
              UUID(uuidString: directory.lastPathComponent) != nil else {
            throw ModelTransportError.invalidDestination
        }
        for url in [stagingRootURL, directory] {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else {
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
