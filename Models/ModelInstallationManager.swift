import CryptoKit
import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

// App-owned installation authority. A verified handle establishes integrity;
// only a successful native recognizer load can establish inference readiness.
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
    private struct Selection: Codable {
        let schemaVersion: Int
        let revision: String
        let installationID: UUID
    }

    private let rootURL: URL
    private let availableBytes: ModelAvailableBytes
    private let downloader: ModelArtifactDownloader?
    private var leases: [UUID: VerifiedModel] = [:]
    private var installationsInProgress: Set<String> = []

    public init(rootURL: URL, availableBytes: @escaping ModelAvailableBytes,
                downloader: ModelArtifactDownloader? = nil) {
        self.rootURL = rootURL.standardizedFileURL
        self.availableBytes = availableBytes
        self.downloader = downloader
    }

    public func importDirectory(_ sourceURL: URL, manifest: ModelManifest) async throws -> VerifiedModel {
        try validate(manifest)
        try Task.checkCancellation()
        try beginInstallation(manifest)
        defer { installationsInProgress.remove(manifest.modelID) }
        let source = sourceURL.standardizedFileURL
        try requireDirectory(source)
        try validateFiles(in: source, manifest: manifest, containsMetadata: false)
        let staging = try makeStagingDirectory()
        defer { removeOwnedStaging(staging) }
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(artifact.fileName)
            try FileManager.default.copyItem(at: source.appendingPathComponent(artifact.fileName), to: destination)
            // Copy can retain the import source's stronger protection class.
            // Change only the app-owned copy, never the external source.
            try PersistentFilePolicy.protectItem(destination, within: rootURL)
        }
        // Verify the copied bytes as well: source mutation must not publish a
        // handle that only describes an earlier validation of external files.
        try validateFiles(in: staging, manifest: manifest, containsMetadata: false)
        return try publish(staging, manifest: manifest)
    }

    public func download(_ manifest: ModelManifest) async throws -> VerifiedModel {
        try validate(manifest)
        try Task.checkCancellation()
        guard let downloader else { throw ModelInstallationError.downloadFailed }
        try beginInstallation(manifest)
        defer { installationsInProgress.remove(manifest.modelID) }
        let staging = try makeStagingDirectory()
        defer { removeOwnedStaging(staging) }
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(artifact.fileName)
            do { try await downloader(artifact, destination) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                throw ModelInstallationError.downloadFailed
            }
            try Task.checkCancellation()
            try verifyFile(destination, artifact: artifact)
            try PersistentFilePolicy.protectItem(destination, within: rootURL)
        }
        try validateFiles(in: staging, manifest: manifest, containsMetadata: false)
        return try publish(staging, manifest: manifest)
    }

    public func current(modelID: String) throws -> VerifiedModel? {
        guard validComponent(modelID) else { throw ModelInstallationError.invalidManifest }
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return nil }
        try requireDirectory(rootURL)
        let modelDirectory = rootURL.appendingPathComponent(modelID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return nil }
        try requireDirectory(modelDirectory)
        let pointer = modelDirectory.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        let selection: Selection
        do {
            selection = try JSONDecoder().decode(Selection.self, from: readMetadata(pointer))
        } catch { throw ModelInstallationError.invalidInstallation }
        guard selection.schemaVersion == 1, validRevision(selection.revision) else {
            throw ModelInstallationError.invalidInstallation
        }
        let revisionDirectory = modelDirectory.appendingPathComponent(selection.revision, isDirectory: true)
        try requireDirectory(revisionDirectory)
        let directory = revisionDirectory.appendingPathComponent(selection.installationID.uuidString, isDirectory: true)
        try requireDirectory(directory)
        let manifest: ModelManifest
        do {
            manifest = try JSONDecoder().decode(ModelManifest.self,
                from: readMetadata(directory.appendingPathComponent("manifest.json")))
            try validate(manifest)
        } catch { throw ModelInstallationError.invalidInstallation }
        guard manifest.modelID == modelID, manifest.revision == selection.revision else {
            throw ModelInstallationError.invalidInstallation
        }
        try validateFiles(in: directory, manifest: manifest, containsMetadata: true)
        return handle(manifest: manifest, id: selection.installationID, directory: directory)
    }

    /// TEST-FIRST inventory seam. Metadata listing remains unimplemented until
    /// its own compatible assertion RED; it is not an inference readiness check.
    public func installedManifests() throws -> [ModelManifest] { [] }

    public func acquire(modelID: String) throws -> ModelLease {
        guard let model = try current(modelID: modelID) else { throw ModelInstallationError.modelMissing }
        let token = UUID()
        leases[token] = model
        return ModelLease(model: model, token: token)
    }

    public func release(_ lease: ModelLease) throws {
        guard leases[lease.token] == lease.model else { throw ModelInstallationError.invalidLease }
        leases.removeValue(forKey: lease.token)
    }

    public func remove(modelID: String) throws {
        guard validComponent(modelID) else { throw ModelInstallationError.invalidManifest }
        guard !installationsInProgress.contains(modelID),
              !leases.values.contains(where: { $0.manifest.modelID == modelID }) else {
            throw ModelInstallationError.modelInUse
        }
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        try requireDirectory(rootURL)
        let modelDirectory = rootURL.appendingPathComponent(modelID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else { return }
        try requireDirectory(modelDirectory)
        try FileManager.default.removeItem(at: modelDirectory)
    }

    private func beginInstallation(_ manifest: ModelManifest) throws {
        guard !installationsInProgress.contains(manifest.modelID) else { throw ModelInstallationError.modelInUse }
        try createDirectory(rootURL)
        var required: Int64 = 0
        for artifact in manifest.artifacts {
            let sum = required.addingReportingOverflow(artifact.byteCount)
            guard !sum.overflow else { throw ModelInstallationError.invalidManifest }
            required = sum.partialValue
        }
        let metadata = try JSONEncoder().encode(manifest)
        let sum = required.addingReportingOverflow(Int64(metadata.count))
        guard !sum.overflow else { throw ModelInstallationError.invalidManifest }
        guard try availableBytes(rootURL) >= sum.partialValue else { throw ModelInstallationError.insufficientSpace }
        installationsInProgress.insert(manifest.modelID)
    }

    private func makeStagingDirectory() throws -> URL {
        let parent = rootURL.appendingPathComponent(".staging", isDirectory: true)
        try createDirectory(parent)
        let staging = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do { try PersistentFilePolicy.protectItem(staging, within: rootURL) }
        catch {
            removeOwnedStaging(staging)
            throw error
        }
        return staging
    }

    private func removeOwnedStaging(_ staging: URL) {
        let parent = rootURL.appendingPathComponent(".staging", isDirectory: true)
        guard staging.deletingLastPathComponent().standardizedFileURL.path == parent.standardizedFileURL.path,
              UUID(uuidString: staging.lastPathComponent) != nil else { return }
        if FileManager.default.fileExists(atPath: staging.path) {
            try? FileManager.default.removeItem(at: staging)
        }
    }

    private func publish(_ staging: URL, manifest: ModelManifest) throws -> VerifiedModel {
        try Task.checkCancellation()
        let manifestBytes = try JSONEncoder().encode(manifest)
        try PersistentFilePolicy.writeAtomically(manifestBytes,
            to: staging.appendingPathComponent("manifest.json"), within: rootURL)
        // All installed bytes and metadata receive the policy before moving
        // the immutable set and before the current pointer can reference it.
        try PersistentFilePolicy.protectDirectory(staging)
        let modelDirectory = rootURL.appendingPathComponent(manifest.modelID, isDirectory: true)
        try createDirectory(modelDirectory)
        let revisionDirectory = modelDirectory.appendingPathComponent(manifest.revision, isDirectory: true)
        try createDirectory(revisionDirectory)
        let id = UUID()
        let directory = revisionDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: staging, to: directory)
        do {
            try Task.checkCancellation()
            let pointer = modelDirectory.appendingPathComponent("current.json")
            if FileManager.default.fileExists(atPath: pointer.path) {
                try requireRegularFile(pointer, name: "current.json")
            }
            let selection = Selection(schemaVersion: 1, revision: manifest.revision, installationID: id)
            try PersistentFilePolicy.writeAtomically(try JSONEncoder().encode(selection),
                to: pointer, within: rootURL)
        } catch {
            // This directory has never been published or leased. Preserve the
            // previous pointer and remove only the operation's immutable set.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return handle(manifest: manifest, id: id, directory: directory)
    }

    private func handle(manifest: ModelManifest, id: UUID, directory: URL) -> VerifiedModel {
        let files = Dictionary(uniqueKeysWithValues: manifest.artifacts.map {
            ($0.role, directory.appendingPathComponent($0.fileName))
        })
        return VerifiedModel(manifest: manifest, installationID: id, directoryURL: directory, files: files)
    }

    private func validate(_ manifest: ModelManifest) throws {
        guard manifest.schemaVersion == 1, validComponent(manifest.modelID),
              validRevision(manifest.revision), !manifest.licenseIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.licenseNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.runtimeVersion.isEmpty, manifest.upstreamRepository.scheme == "https",
              manifest.upstreamRepository.host != nil, !manifest.artifacts.isEmpty else {
            throw ModelInstallationError.invalidManifest
        }
        var roles: Set<ModelFileRole> = []
        var names: Set<String> = []
        for artifact in manifest.artifacts {
            guard validComponent(artifact.fileName), artifact.fileName != "manifest.json",
                  artifact.fileName != "current.json", artifact.byteCount > 0,
                  artifact.sha256.count == 64, artifact.sha256.utf8.allSatisfy(isLowerHex),
                  artifact.downloadURL.scheme == "https",
                  artifact.downloadURL.host == manifest.upstreamRepository.host,
                  artifact.downloadURL.path.contains("/resolve/\(manifest.revision)/"),
                  roles.insert(artifact.role).inserted, names.insert(artifact.fileName).inserted else {
                throw ModelInstallationError.invalidManifest
            }
        }
        switch manifest.purpose {
        case .speechRecognition:
            if roles == [.whisper] {
                guard manifest.artifacts.count == 1, manifest.sampleRate == 16_000,
                      manifest.featureDimension == nil, manifest.runtimeVersion == "whisper.cpp-1.7.5" else {
                    throw ModelInstallationError.invalidManifest
                }
            } else {
                guard roles == [.encoder, .decoder, .joiner, .tokens], manifest.sampleRate == 16_000,
                      manifest.featureDimension == 80 else { throw ModelInstallationError.invalidManifest }
            }
        case .summary:
            guard roles == [.summary] else { throw ModelInstallationError.invalidManifest }
        }
    }

    private func validComponent(_ component: String) -> Bool {
        guard !component.isEmpty, component.utf8.count <= 255, component.first != "." else { return false }
        return component.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    private func isLowerHex(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }

    private func validRevision(_ revision: String) -> Bool {
        revision.utf8.count == 40 && revision.utf8.allSatisfy(isLowerHex)
    }

    private func createDirectory(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        guard url.isFileURL,
              path == rootURL.path || path.hasPrefix(rootURL.path + "/") else {
            throw ModelInstallationError.invalidInstallation
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if path != rootURL.path {
                try createDirectory(parent)
                try PersistentFilePolicy.protectItem(parent, within: rootURL)
            } else {
                // The configured root's immediate parent is chosen by the app;
                // never create intermediate paths through an unchecked link.
                try requireDirectory(parent)
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        try requireDirectory(url)
        if path == rootURL.path {
            try PersistentFilePolicy.protectDirectory(url)
        } else {
            try PersistentFilePolicy.protectItem(url, within: rootURL)
        }
    }

    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ModelInstallationError.invalidInstallation
        }
    }

    private func requireRegularFile(_ url: URL, name: String) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ModelInstallationError.unsafeFile(name)
        }
    }

    private func readMetadata(_ url: URL) throws -> Data {
        try requireRegularFile(url, name: url.lastPathComponent)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard size >= 0, size <= 1_048_576 else { throw ModelInstallationError.invalidInstallation }
        return try Data(contentsOf: url)
    }

    private func validateFiles(in directory: URL, manifest: ModelManifest, containsMetadata: Bool) throws {
        try requireDirectory(directory)
        let present = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let required = Set(manifest.artifacts.map(\.fileName))
        for artifact in manifest.artifacts where !present.contains(artifact.fileName) {
            throw ModelInstallationError.missingFile(artifact.fileName)
        }
        let allowed = containsMetadata ? required.union(["manifest.json"]) : required
        if let unexpected = present.subtracting(allowed).sorted().first {
            throw ModelInstallationError.unexpectedFile(unexpected)
        }
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            try verifyFile(directory.appendingPathComponent(artifact.fileName), artifact: artifact)
        }
    }

    private func verifyFile(_ url: URL, artifact: ModelArtifact) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModelInstallationError.missingFile(artifact.fileName)
        }
        try requireRegularFile(url, name: artifact.fileName)
        let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard Int64(count) == artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hasher = SHA256()
        var consumed: Int64 = 0
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 65_536), !data.isEmpty else { break }
            consumed += Int64(data.count)
            guard consumed <= artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
            hasher.update(data: data)
        }
        guard consumed == artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw ModelInstallationError.checksumMismatch(artifact.fileName) }
    }
}
