import CryptoKit
import Darwin
import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

// App-owned installation authority. A verified handle establishes integrity;
// only a successful native recognizer load can establish inference readiness.
public enum ModelInstallationError: Error, Equatable, Sendable {
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
public typealias ModelProgressArtifactDownloader = @Sendable (ModelArtifact, URL, ModelTransferProgressHandler?) async throws -> Void

public actor ModelInstallationManager {
    private struct Selection: Codable {
        let schemaVersion: Int
        let revision: String
        let installationID: UUID
    }

    private let rootURL: URL
    private let availableBytes: ModelAvailableBytes
    private let downloader: ModelArtifactDownloader?
    private let progressDownloader: ModelProgressArtifactDownloader?
    private var leases: [UUID: VerifiedModel] = [:]
    private var installationsInProgress: Set<String> = []

    public init(rootURL: URL, availableBytes: @escaping ModelAvailableBytes,
                downloader: ModelArtifactDownloader? = nil,
                progressDownloader: ModelProgressArtifactDownloader? = nil) {
        self.rootURL = rootURL.standardizedFileURL
        self.availableBytes = availableBytes
        self.downloader = downloader
        self.progressDownloader = progressDownloader
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
            if artifact.role == .coreMLAsset {
                try createDirectory(destination.deletingLastPathComponent())
                try copyAsset(source.appendingPathComponent(artifact.fileName), to: destination, artifact: artifact, sourceRoot: source)
            } else {
                try FileManager.default.copyItem(at: source.appendingPathComponent(artifact.fileName), to: destination)
            }
            // Copy can retain the import source's stronger protection class.
            // Change only the app-owned copy, never the external source.
            try PersistentFilePolicy.protectItem(destination, within: rootURL)
        }
        // Verify the copied bytes as well: source mutation must not publish a
        // handle that only describes an earlier validation of external files.
        try validateFiles(in: staging, manifest: manifest, containsMetadata: false)
        return try publish(staging, manifest: manifest)
    }

    public func download(_ manifest: ModelManifest, progress: ModelTransferProgressHandler? = nil) async throws -> VerifiedModel {
        try validate(manifest)
        try Task.checkCancellation()
        guard downloader != nil || progressDownloader != nil else { throw ModelInstallationError.downloadFailed }
        try beginInstallation(manifest)
        defer { installationsInProgress.remove(manifest.modelID) }
        let staging = try makeStagingDirectory()
        defer { removeOwnedStaging(staging) }
        let reporter = progress.map { ModelDownloadProgressReporter(manifest: manifest, handler: $0) }
        do {
        for (index, artifact) in manifest.artifacts.enumerated() {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(artifact.fileName)
            if artifact.role == .coreMLAsset { try createDirectory(destination.deletingLastPathComponent()) }
            do {
                if let progressDownloader {
                    let callback: ModelTransferProgressHandler? = reporter.map { reporter in
                        { @Sendable event in reporter.receive(event, index: index) }
                    }
                    try await progressDownloader(artifact, destination, callback)
                } else if let downloader { try await downloader(artifact, destination) }
            }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                throw ModelInstallationError.downloadFailed
            }
            try Task.checkCancellation()
            try verifyFile(destination, artifact: artifact)
            try PersistentFilePolicy.protectItem(destination, within: rootURL)
        }
        try validateFiles(in: staging, manifest: manifest, containsMetadata: false, progress: reporter)
        reporter?.finish(.installing)
        let installed = try publish(staging, manifest: manifest)
        reporter?.finish(.completed)
        return installed
        } catch {
            reporter?.finish(error is CancellationError ? .paused : .failed)
            throw error
        }
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

    /// List published installed choices without hashing every weight for UI.
    /// Paths, pointers, manifest coherence and file sizes are checked here;
    /// acquire/current still perform full byte verification before native use.
    public func installedManifests() throws -> [ModelManifest] {
        let manager = FileManager.default
        do {
            let attributes = try manager.attributesOfItem(atPath: rootURL.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ModelInstallationError.invalidInstallation
            }
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return []
        }
        try PersistentFilePolicy.validateItem(rootURL, within: rootURL)
        var inventory: [ModelManifest] = []
        for name in try manager.contentsOfDirectory(atPath: rootURL.path).sorted() {
            try Task.checkCancellation()
            let container = rootURL.appendingPathComponent(name, isDirectory: true)
            try PersistentFilePolicy.validateItem(container, within: rootURL)
            try requireDirectory(container)
            if name == ".staging" { continue }
            guard validComponent(name) else { throw ModelInstallationError.invalidInstallation }
            let pointer = container.appendingPathComponent("current.json")
            do { _ = try manager.attributesOfItem(atPath: pointer.path) }
            catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                // An import can create its container before atomic publication.
                continue
            }
            try PersistentFilePolicy.validateItem(pointer, within: rootURL)
            let selected: Selection
            do { selected = try JSONDecoder().decode(Selection.self, from: readMetadata(pointer)) }
            catch { throw ModelInstallationError.invalidInstallation }
            guard selected.schemaVersion == 1, validRevision(selected.revision) else {
                throw ModelInstallationError.invalidInstallation
            }
            let directory = container.appendingPathComponent(selected.revision, isDirectory: true)
                .appendingPathComponent(selected.installationID.uuidString, isDirectory: true)
            try PersistentFilePolicy.validateItem(directory, within: rootURL)
            try requireDirectory(directory)
            let metadata = directory.appendingPathComponent("manifest.json")
            try PersistentFilePolicy.validateItem(metadata, within: rootURL)
            let manifest: ModelManifest
            do {
                manifest = try JSONDecoder().decode(ModelManifest.self, from: readMetadata(metadata))
                try validate(manifest)
            } catch { throw ModelInstallationError.invalidInstallation }
            guard manifest.modelID == name, manifest.revision == selected.revision else {
                throw ModelInstallationError.invalidInstallation
            }
            if manifest.artifacts.allSatisfy({ $0.role == .coreMLAsset }) {
                try validateAssetTree(in: directory, manifest: manifest, containsMetadata: true)
            } else {
                let present = Set(try manager.contentsOfDirectory(atPath: directory.path))
                guard present == Set(manifest.artifacts.map(\.fileName)).union(["manifest.json"]) else {
                    throw ModelInstallationError.invalidInstallation
                }
            }
            for artifact in manifest.artifacts {
                let file = directory.appendingPathComponent(artifact.fileName)
                try PersistentFilePolicy.validateItem(file, within: rootURL)
                try requireRegularFile(file, name: artifact.fileName)
                let size = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard size.map({ Int64($0) }) == artifact.byteCount else {
                    throw ModelInstallationError.sizeMismatch(artifact.fileName)
                }
            }
            inventory.append(manifest)
        }
        return inventory
    }

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
        let files = Dictionary(uniqueKeysWithValues: manifest.artifacts.filter { $0.role != .coreMLAsset }.map {
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
        let assets = manifest.artifacts.allSatisfy { $0.role == .coreMLAsset }
        if assets {
            guard manifest.purpose == .speechRecognition, (1...256).contains(manifest.artifacts.count),
                  manifest.sampleRate == 16_000, manifest.featureDimension == 128,
                  [ParakeetCoreMLModel.runtimeVersion, ParakeetModelPack.runtimeVersion].contains(manifest.runtimeVersion) else {
                throw ModelInstallationError.invalidManifest
            }
            if manifest.runtimeVersion == ParakeetModelPack.runtimeVersion {
                do { _ = try ParakeetModelPack.configuration(for: manifest) }
                catch { throw ModelInstallationError.invalidManifest }
            }
        }
        var assetBytes: Int64 = 0
        for artifact in manifest.artifacts {
            let safeName = assets ? ModelArtifactPath.components(artifact.fileName) != nil : validComponent(artifact.fileName)
            guard safeName, artifact.fileName != "manifest.json",
                  artifact.fileName != "current.json", artifact.byteCount > 0,
                  artifact.sha256.count == 64, artifact.sha256.utf8.allSatisfy(isLowerHex),
                  artifact.downloadURL.scheme == "https",
                  artifact.downloadURL.host == manifest.upstreamRepository.host,
                  artifact.downloadURL.path.contains("/resolve/\(manifest.revision)/"),
                  (assets || !roles.contains(artifact.role)), names.insert(artifact.fileName).inserted else {
                throw ModelInstallationError.invalidManifest
            }
            roles.insert(artifact.role)
            if assets {
                let sum = assetBytes.addingReportingOverflow(artifact.byteCount)
                guard !sum.overflow, sum.partialValue <= 8_589_934_592 else { throw ModelInstallationError.invalidManifest }
                assetBytes = sum.partialValue
            }
        }
        if assets {
            guard Set(names.map { $0.lowercased() }).count == names.count,
                  ModelArtifactPath.directories(for: Array(names)).isDisjoint(with: names) else {
                throw ModelInstallationError.invalidManifest
            }
        }
        switch manifest.purpose {
        case .speechRecognition:
            if assets { break }
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
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeDirectory else {
            throw ModelInstallationError.invalidInstallation
        }
    }

    private func requireRegularFile(_ url: URL, name: String) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular,
              (values[.referenceCount] as? NSNumber)?.intValue == 1 else {
            throw ModelInstallationError.unsafeFile(name)
        }
    }

    private func readMetadata(_ url: URL) throws -> Data {
        try requireRegularFile(url, name: url.lastPathComponent)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard size >= 0, size <= 1_048_576 else { throw ModelInstallationError.invalidInstallation }
        return try Data(contentsOf: url)
    }

    private func validateFiles(in directory: URL, manifest: ModelManifest, containsMetadata: Bool,
                               progress: ModelDownloadProgressReporter? = nil) throws {
        try requireDirectory(directory)
        if manifest.artifacts.allSatisfy({ $0.role == .coreMLAsset }) {
            try validateAssetTree(in: directory, manifest: manifest, containsMetadata: containsMetadata)
            for (index, artifact) in manifest.artifacts.enumerated() {
                try Task.checkCancellation()
                try verifyFile(directory.appendingPathComponent(artifact.fileName), artifact: artifact,
                    progress: progress.map { reporter in { reporter.verifying(index: index, bytes: $0) } })
            }
            return
        }
        let present = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        let required = Set(manifest.artifacts.map(\.fileName))
        for artifact in manifest.artifacts where !present.contains(artifact.fileName) {
            throw ModelInstallationError.missingFile(artifact.fileName)
        }
        let allowed = containsMetadata ? required.union(["manifest.json"]) : required
        if let unexpected = present.subtracting(allowed).sorted().first {
            throw ModelInstallationError.unexpectedFile(unexpected)
        }
        for (index, artifact) in manifest.artifacts.enumerated() {
            try Task.checkCancellation()
            try verifyFile(directory.appendingPathComponent(artifact.fileName), artifact: artifact,
                progress: progress.map { reporter in { reporter.verifying(index: index, bytes: $0) } })
        }
    }

    private func verifyFile(_ url: URL, artifact: ModelArtifact, progress: ((Int64) -> Void)? = nil) throws {
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
        var lastProgress: TimeInterval = 0
        progress?(0)
        try ModelFileIO.forEachChunk(in: input) { data in
            try Task.checkCancellation()
            consumed += Int64(data.count)
            guard consumed <= artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
            hasher.update(data: data)
            if let progress {
                let now = ProcessInfo.processInfo.systemUptime
                if consumed == artifact.byteCount || now - lastProgress >= 0.2 {
                    progress(consumed); lastProgress = now
                }
            }
        }
        guard consumed == artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw ModelInstallationError.checksumMismatch(artifact.fileName) }
    }

    private func validateAssetTree(in directory: URL, manifest: ModelManifest, containsMetadata: Bool) throws {
        try requireDirectory(directory)
        let required = Set(manifest.artifacts.map(\.fileName))
        let parents = ModelArtifactPath.directories(for: Array(required))
        let allowed = containsMetadata ? required.union(["manifest.json"]) : required
        var pending = [(directory, "")]
        var present: Set<String> = []
        var visited = 0
        while let (folder, prefix) = pending.popLast() {
            do { try PersistentFilePolicy.validateItem(folder, within: directory) }
            catch { throw ModelInstallationError.unsafeFile(prefix) }
            let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            guard children.count <= allowed.count + parents.count + 1 - visited else { throw ModelInstallationError.invalidManifest }
            for child in children {
                try Task.checkCancellation(); visited += 1
                let path = prefix.isEmpty ? child.lastPathComponent : prefix + "/" + child.lastPathComponent
                let info = try FileManager.default.attributesOfItem(atPath: child.path)
                if info[.type] as? FileAttributeType == .typeDirectory {
                    guard parents.contains(path) else { throw ModelInstallationError.unexpectedFile(path) }
                    pending.append((child, path))
                } else {
                    guard info[.type] as? FileAttributeType == .typeRegular,
                          (info[.referenceCount] as? NSNumber)?.intValue == 1 else { throw ModelInstallationError.unsafeFile(path) }
                    guard allowed.contains(path) else { throw ModelInstallationError.unexpectedFile(path) }
                    do { try PersistentFilePolicy.validateItem(child, within: directory) }
                    catch { throw ModelInstallationError.unsafeFile(path) }
                    present.insert(path)
                }
            }
        }
        for artifact in manifest.artifacts where !present.contains(artifact.fileName) { throw ModelInstallationError.missingFile(artifact.fileName) }
        for artifact in manifest.artifacts {
            let file = directory.appendingPathComponent(artifact.fileName)
            let info = try FileManager.default.attributesOfItem(atPath: file.path)
            guard (info[.size] as? NSNumber)?.int64Value == artifact.byteCount else {
                throw ModelInstallationError.sizeMismatch(artifact.fileName)
            }
        }
    }

    private func copyAsset(_ source: URL, to destination: URL, artifact: ModelArtifact, sourceRoot: URL) throws {
        do { try PersistentFilePolicy.validateItem(source, within: sourceRoot) }
        catch { throw ModelInstallationError.unsafeFile(artifact.fileName) }
        let descriptor = source.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw ModelInstallationError.unsafeFile(artifact.fileName) }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_nlink == 1, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw ModelInstallationError.unsafeFile(artifact.fileName)
        }
        guard info.st_size == artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
        let outputFD = destination.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) }
        guard outputFD >= 0 else { throw ModelInstallationError.invalidInstallation }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        try PersistentFilePolicy.protectItem(destination, within: rootURL)
        var copied: Int64 = 0
        try ModelFileIO.forEachChunk(in: input) { bytes in
            try Task.checkCancellation()
            guard Int64(bytes.count) <= artifact.byteCount - copied else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
            try output.write(contentsOf: bytes); copied += Int64(bytes.count)
        }
        guard copied == artifact.byteCount else { throw ModelInstallationError.sizeMismatch(artifact.fileName) }
        try output.synchronize()
    }
}
