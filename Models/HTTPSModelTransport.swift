import Foundation

// Draft test-first interfaces only. No transport or disk-policy behavior exists.
public enum ModelTransportError: Error, Equatable, Sendable {
    case notImplemented, insecureURL, unapprovedHost, invalidDestination
    case httpStatus(Int)
    case sizeMismatch, networkFailure
}

public final class HTTPSModelTransport: @unchecked Sendable {
    public init(stagingRootURL: URL, allowedHosts: Set<String>,
                configuration: URLSessionConfiguration = .ephemeral) {}

    public func download(_ artifact: ModelArtifact, to destination: URL) async throws {
        throw ModelTransportError.notImplemented
    }
}

public final class ModelDownloadRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public init(allowedHosts: Set<String>) { super.init() }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ModelStoragePolicy {
    public static func availableBytes(at directory: URL) throws -> Int64 {
        throw ModelTransportError.notImplemented
    }

    public static func protectPersistentDirectory(_ directory: URL) throws {
        throw ModelTransportError.notImplemented
    }
}
