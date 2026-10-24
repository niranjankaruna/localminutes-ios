import CryptoKit
import Darwin
import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

/// One operation owns one serial delegate/file queue. Task cancellation touches
/// only the locked flag; every handle, digest, checkpoint and continuation is
/// used on that queue. No complete model is retained in memory. The lock file
/// also excludes another process/transport writing the same progress directory.
final class ResumableModelDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let artifact: ModelArtifact
    private let destination: URL
    private let stagingRoot: URL
    private let resumeRoot: URL
    private let directory: URL
    private let allowedHosts: Set<String>
    private let configuration: URLSessionConfiguration
    private let queue: OperationQueue
    private let cancellationLock = NSLock()
    private var cancellationRequested = false

    // Queue-owned state only.
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var pending: CheckedContinuation<Void, Error>?
    private var outcome: Result<Void, Error>?
    private var file: FileHandle?
    private var transferLock: Int32 = -1
    private var checkpoint: ModelDownloadCheckpoint?
    private var revision = ""
    private var received: Int64 = 0
    private var responseBytes: Int64 = 0
    private var expectedResponseBytes: Int64 = 0
    private var digest = SHA256()
    private var validator: String?
    private var accepted = false
    private var redirects = 0
    private var durableBytes: Int64 = 0
    private var outputTemporary: URL?
    private var publishedOutput = false
    private var partial: URL { directory.appendingPathComponent("partial.bin") }
    private var checkpointURL: URL { directory.appendingPathComponent("checkpoint.json") }

    init(artifact: ModelArtifact, destination: URL, stagingRoot: URL, resumeRoot: URL,
         directory: URL, allowedHosts: Set<String>, configuration: URLSessionConfiguration) {
        self.artifact = artifact; self.destination = destination.standardizedFileURL
        self.stagingRoot = stagingRoot.standardizedFileURL
        self.resumeRoot = resumeRoot.standardizedFileURL; self.directory = directory.standardizedFileURL
        self.allowedHosts = allowedHosts
        let options = configuration.copy() as! URLSessionConfiguration
        options.httpShouldSetCookies = false; options.httpCookieStorage = nil
        options.urlCredentialStorage = nil; options.urlCache = nil; options.httpAdditionalHeaders = [:]
        options.requestCachePolicy = .reloadIgnoringLocalCacheData
        options.timeoutIntervalForRequest = 60; options.timeoutIntervalForResource = 3_600
        self.configuration = options
        let queue = OperationQueue()
        queue.name = "LocalMinutes.ModelResume"; queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        self.queue = queue
        super.init()
    }

    deinit {
        try? file?.close()
        if transferLock >= 0 { Darwin.close(transferLock) }
    }

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.addOperation { [self] in
                    if let outcome { continuation.resume(with: outcome); return }
                    pending = continuation
                    do {
                        try prepare()
                        try checkCancellation()
                        if received == artifact.byteCount {
                            try publishStaging()
                            finish(.success(()))
                        } else { startRequest() }
                    } catch { fail(error, preservingProgress: false) }
                }
            }
        } onCancel: {
            self.cancellationLock.withLock { self.cancellationRequested = true }
            self.queue.addOperation { self.fail(CancellationError(), preservingProgress: true) }
        }
    }

    private func prepare() throws {
        try checkCancellation()
        try validateRoute(artifact.downloadURL)
        let parts = artifact.downloadURL.path.split(separator: "/", omittingEmptySubsequences: true)
        guard artifact.downloadURL.query == nil, artifact.downloadURL.fragment == nil,
              parts.count >= 5, parts[2] == "resolve", Self.hex(String(parts[3]), length: 40),
              artifact.downloadURL.lastPathComponent == artifact.fileName,
              Self.component(artifact.fileName), artifact.byteCount > 0,
              Self.hex(artifact.sha256, length: 64) else { throw ModelTransportError.invalidResumeState }
        revision = String(parts[3])
        try validateDestination()
        guard resumeRoot.isFileURL, directory.isFileURL, resumeRoot.path != "/",
              directory.deletingLastPathComponent().path == resumeRoot.path,
              UUID(uuidString: directory.lastPathComponent) != nil,
              !Self.contains(stagingRoot, directory), !Self.contains(directory, destination),
              !Self.contains(directory, stagingRoot) else { throw ModelTransportError.invalidDestination }
        do {
            if try !Self.exists(resumeRoot) {
                let parent = resumeRoot.deletingLastPathComponent()
                try PersistentFilePolicy.validateItem(parent, within: parent)
                try FileManager.default.createDirectory(at: resumeRoot, withIntermediateDirectories: false)
            }
            try PersistentFilePolicy.protectItem(resumeRoot, within: resumeRoot)
            if try !Self.exists(directory) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            }
            try PersistentFilePolicy.protectItem(directory, within: resumeRoot)
            let children = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard Set(children).isSubset(of: ["partial.bin", "checkpoint.json", ".transfer.lock"]) else {
                throw ModelTransportError.invalidResumeState
            }
            for name in children {
                try PersistentFilePolicy.validateItem(directory.appendingPathComponent(name), within: resumeRoot)
                guard try directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ModelTransportError.invalidDestination
                }
            }
            let lockURL = directory.appendingPathComponent(".transfer.lock")
            transferLock = try Self.openRegular(lockURL, flags: O_RDWR | O_CREAT)
            guard Self.lockExclusively(transferLock) else { throw ModelTransportError.invalidResumeState }
            try PersistentFilePolicy.protectItem(lockURL, within: resumeRoot)
        } catch let error as ModelTransportError { throw error }
        catch { throw ModelTransportError.invalidDestination }

        if try Self.exists(checkpointURL) {
            do {
                let data = try Self.smallData(checkpointURL)
                let point = try JSONDecoder().decode(ModelDownloadCheckpoint.self, from: data)
                guard point.schemaVersion == 1, point.downloadURL == artifact.downloadURL,
                      point.revision == revision, point.fileName == artifact.fileName,
                      point.expectedByteCount == artifact.byteCount, point.sha256 == artifact.sha256,
                      Self.strongETag(point.strongETag), point.receivedByteCount > 0,
                      point.receivedByteCount <= artifact.byteCount,
                      Self.hex(point.partialSHA256, length: 64), try Self.exists(partial) else {
                    throw ModelTransportError.invalidResumeState
                }
                let input = try Self.readHandle(partial)
                defer { try? input.close() }
                let length = try input.seekToEnd()
                guard length >= UInt64(point.receivedByteCount), length <= UInt64(artifact.byteCount) else {
                    throw ModelTransportError.invalidResumeState
                }
                try input.seek(toOffset: 0)
                var count: Int64 = 0
                while count < point.receivedByteCount {
                    try checkCancellation()
                    let bytes = try input.read(upToCount: Int(min(65_536, point.receivedByteCount - count))) ?? Data()
                    guard !bytes.isEmpty else { throw ModelTransportError.invalidResumeState }
                    digest.update(data: bytes); count += Int64(bytes.count)
                }
                guard Self.finalDigest(digest) == point.partialSHA256 else { throw ModelTransportError.invalidResumeState }
                checkpoint = point; received = count; durableBytes = count; validator = point.strongETag
            } catch is CancellationError { throw CancellationError() }
            catch let error as ModelTransportError { throw error }
            catch { throw ModelTransportError.invalidResumeState }
        }
        // A partial without a checkpoint is an uncommitted crash tail. It is
        // never resumed; a validated fresh200 can replace only this owned file.
    }

    private func startRequest() {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        task = session.dataTask(with: request(for: artifact.downloadURL))
        task?.resume()
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let checkpoint {
            request.setValue("bytes=\(checkpoint.receivedByteCount)-", forHTTPHeaderField: "Range")
            request.setValue(checkpoint.strongETag, forHTTPHeaderField: "If-Range")
        }
        return request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard outcome == nil else { completionHandler(.cancel); return }
        do {
            try checkCancellation()
            guard let response = response as? HTTPURLResponse, let finalURL = response.url else {
                throw ModelTransportError.networkFailure
            }
            try validateRoute(finalURL)
            guard response.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true else {
                throw ModelTransportError.invalidRangeResponse
            }
            let tag = response.value(forHTTPHeaderField: "ETag")
            switch response.statusCode {
            case 206:
                guard let checkpoint, tag == checkpoint.strongETag,
                      let range = response.value(forHTTPHeaderField: "Content-Range"),
                      Self.range(range, start: checkpoint.receivedByteCount, total: artifact.byteCount) else {
                    throw ModelTransportError.invalidRangeResponse
                }
                expectedResponseBytes = artifact.byteCount - received
                validator = checkpoint.strongETag
            case 200:
                expectedResponseBytes = artifact.byteCount
                validator = tag.flatMap { Self.strongETag($0) ? $0 : nil }
            default: throw ModelTransportError.httpStatus(response.statusCode)
            }
            guard response.expectedContentLength < 0 || response.expectedContentLength == expectedResponseBytes else {
                throw ModelTransportError.sizeMismatch
            }
            try validateProgressFiles()
            if response.statusCode == 200 {
                // Invalidate the previous cursor before truncating its bytes.
                // A crash between these steps restarts, never appends old data.
                if try Self.exists(checkpointURL) { try FileManager.default.removeItem(at: checkpointURL) }
                checkpoint = nil; received = 0; durableBytes = 0; digest = SHA256()
            }
            let descriptor = try Self.openRegular(partial, flags: O_RDWR | O_CREAT)
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try file?.truncate(atOffset: UInt64(received))
            try file?.seek(toOffset: UInt64(received))
            try PersistentFilePolicy.protectItem(partial, within: resumeRoot)
            accepted = true
            completionHandler(.allow)
        } catch {
            fail(error, preservingProgress: false)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard outcome == nil, accepted else { return }
        do {
            try checkCancellation()
            guard Int64(data.count) <= artifact.byteCount - received,
                  Int64(data.count) <= expectedResponseBytes - responseBytes, let file else {
                throw ModelTransportError.sizeMismatch
            }
            var offset = 0
            while offset < data.count {
                try checkCancellation()
                let count = min(65_536, data.count - offset)
                let bytes = data.subdata(in: offset..<(offset + count))
                try file.write(contentsOf: bytes)
                digest.update(data: bytes)
                received += Int64(count); responseBytes += Int64(count); offset += count
            }
            // First progress is immediately durable, then checkpoint at most
            // oneMiB apart. Error/cancel/completion always flush the remainder.
            if durableBytes == 0 || received - durableBytes >= 1_048_576 { try persistProgress() }
        } catch { fail(error, preservingProgress: true) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard outcome == nil else { return }
        if let error { fail(error, preservingProgress: true); return }
        do {
            try checkCancellation()
            guard accepted, responseBytes == expectedResponseBytes, received == artifact.byteCount else {
                throw ModelTransportError.sizeMismatch
            }
            try persistProgress()
            try publishStaging()
            finish(.success(()))
        } catch { fail(error, preservingProgress: true) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest proposed: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard outcome == nil else { completionHandler(nil); return }
        do {
            try checkCancellation()
            guard let target = proposed.url, proposed.httpMethod == "GET", redirects < 8 else {
                throw ModelTransportError.unapprovedHost
            }
            try validateRoute(target)
            redirects += 1
            // Rebuild explicitly: no credentials/cookies are forwarded, while
            // Range/If-Range survive a reviewed HF distribution-host redirect.
            completionHandler(request(for: target))
        } catch { fail(error, preservingProgress: false); completionHandler(nil) }
    }

    private func persistProgress() throws {
        guard accepted, received > 0, let validator else { return }
        try file?.synchronize()
        try validateProgressFiles()
        let point = ModelDownloadCheckpoint(downloadURL: artifact.downloadURL, revision: revision,
            fileName: artifact.fileName, expectedByteCount: artifact.byteCount, sha256: artifact.sha256,
            strongETag: validator, receivedByteCount: received, partialSHA256: Self.finalDigest(digest))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try PersistentFilePolicy.writeAtomically(encoder.encode(point), to: checkpointURL, within: resumeRoot)
        checkpoint = point; durableBytes = received
    }

    private func publishStaging() throws {
        try checkCancellation()
        try file?.synchronize(); try file?.close(); file = nil
        try validateProgressFiles()
        try validateDestination()
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".resume-output-\(UUID().uuidString).tmp")
        outputTemporary = temporary
        let output = FileHandle(fileDescriptor: try Self.openRegular(temporary, flags: O_WRONLY | O_CREAT | O_EXCL), closeOnDealloc: true)
        let input = try Self.readHandle(partial)
        defer { try? output.close(); try? input.close() }
        try PersistentFilePolicy.protectItem(temporary, within: stagingRoot)
        var copied: Int64 = 0
        var copiedHash = SHA256()
        while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty {
            try checkCancellation()
            guard Int64(bytes.count) <= artifact.byteCount - copied else { throw ModelTransportError.sizeMismatch }
            try output.write(contentsOf: bytes); copiedHash.update(data: bytes); copied += Int64(bytes.count)
        }
        guard copied == artifact.byteCount, Self.finalDigest(copiedHash) == Self.finalDigest(digest) else {
            throw ModelTransportError.invalidResumeState
        }
        try output.synchronize(); try output.close(); try input.close()
        try checkCancellation()
        try validateDestination()
        try FileManager.default.moveItem(at: temporary, to: destination)
        publishedOutput = true; outputTemporary = nil
        try checkCancellation()
        // The manager still performs its independent expected SHA-256 check and
        // atomic current.json publication. This operation publishes no model.
        // Cleanup is best-effort after a complete staging file exists; retained
        // completed bytes can be safely reused if cleanup itself is interrupted.
        try? FileManager.default.removeItem(at: checkpointURL)
        try? FileManager.default.removeItem(at: partial)
    }

    private func validateDestination() throws {
        let parent = destination.deletingLastPathComponent()
        guard destination.isFileURL, stagingRoot.isFileURL,
              destination.lastPathComponent == artifact.fileName,
              parent.deletingLastPathComponent().path == stagingRoot.path,
              UUID(uuidString: parent.lastPathComponent) != nil else { throw ModelTransportError.invalidDestination }
        do {
            try PersistentFilePolicy.validateItem(parent, within: stagingRoot)
            guard try parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                  try !Self.exists(destination) else { throw ModelTransportError.invalidDestination }
        } catch { throw ModelTransportError.invalidDestination }
    }

    private func validateProgressFiles() throws {
        do {
            try PersistentFilePolicy.validateItem(directory, within: resumeRoot)
            for path in [partial, checkpointURL] where try Self.exists(path) {
                try PersistentFilePolicy.validateItem(path, within: resumeRoot)
                guard try URL(fileURLWithPath: path.path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ModelTransportError.invalidDestination
                }
            }
        } catch { throw ModelTransportError.invalidDestination }
    }

    private func validateRoute(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else { throw ModelTransportError.insecureURL }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host), url.user == nil,
              url.password == nil, url.port == nil || url.port == 443, url.fragment == nil else {
            throw ModelTransportError.unapprovedHost
        }
    }
    private func checkCancellation() throws {
        if cancellationLock.withLock({ cancellationRequested }) { throw CancellationError() }
    }
    private func fail(_ error: Error, preservingProgress: Bool) {
        guard outcome == nil else { return }
        if preservingProgress { try? persistProgress() }
        if publishedOutput {
            try? FileManager.default.removeItem(at: destination); publishedOutput = false
        }
        let normalized: Error
        if error is CancellationError || (error as? URLError)?.code == .cancelled
            || cancellationLock.withLock({ cancellationRequested }) { normalized = CancellationError() }
        else if let error = error as? ModelTransportError { normalized = error }
        else { normalized = ModelTransportError.networkFailure }
        finish(.failure(normalized))
    }
    private func finish(_ result: Result<Void, Error>) {
        guard outcome == nil else { return }
        outcome = result
        try? file?.close(); file = nil
        if let outputTemporary { try? FileManager.default.removeItem(at: outputTemporary); self.outputTemporary = nil }
        if transferLock >= 0 { Darwin.close(transferLock); transferLock = -1 }
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        let continuation = pending; pending = nil
        continuation?.resume(with: result)
    }

    private static func readHandle(_ url: URL) throws -> FileHandle {
        FileHandle(fileDescriptor: try openRegular(url, flags: O_RDONLY), closeOnDealloc: true)
    }
    private static func lockExclusively(_ descriptor: Int32) -> Bool {
        // Darwin's imported struct flock shadows the C function in this SDK.
        // Resolve only this constant public libSystem symbol with its C ABI;
        // never load a path/model library or send the pointer across executors.
        guard let process = Darwin.dlopen(nil, RTLD_NOW) else { return false }
        defer { Darwin.dlclose(process) }
        guard let symbol = Darwin.dlsym(process, "flock") else { return false }
        typealias LockFunction = @convention(c) (Int32, Int32) -> Int32
        let lock = unsafeBitCast(symbol, to: LockFunction.self)
        return lock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
    private static func openRegular(_ url: URL, flags: Int32) throws -> Int32 {
        let descriptor = url.path.withCString { Darwin.open($0, flags | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600)) }
        guard descriptor >= 0 else { throw ModelTransportError.invalidDestination }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_nlink == 1 else {
            Darwin.close(descriptor); throw ModelTransportError.invalidDestination
        }
        return descriptor
    }
    private static func smallData(_ url: URL) throws -> Data {
        let file = try readHandle(url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: 65_537) ?? Data()
        guard !bytes.isEmpty, bytes.count <= 65_536 else { throw ModelTransportError.invalidResumeState }
        return bytes
    }
    private static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return false }
    }
    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }
    private static func component(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.first != "."
            && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0)
                || (97...122).contains($0) || [45, 46, 95].contains($0) }
    }
    private static func hex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func strongETag(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (2...256).contains(bytes.count), bytes.first == 34, bytes.last == 34 else { return false }
        return bytes.dropFirst().dropLast().allSatisfy { $0 == 33 || (35...126).contains($0) }
    }
    private static func range(_ value: String, start: Int64, total: Int64) -> Bool {
        guard value.hasPrefix("bytes ") else { return false }
        let parts = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, decimal(parts[1]), let count = Int64(parts[1]), count == total else { return false }
        let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, decimal(bounds[0]), decimal(bounds[1]),
              let first = Int64(bounds[0]), let last = Int64(bounds[1]) else { return false }
        return first == start && start >= 0 && start < total && last == total - 1
    }
    private static func finalDigest(_ digest: SHA256) -> String {
        var copy = digest
        return copy.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func decimal(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}
