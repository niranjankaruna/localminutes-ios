import Darwin
import Foundation
#if canImport(LocalMinutesCore)
import LocalMinutesCore
#endif

/// OS permission boundary only. A granted scope remains owned until every
/// actual copy/hash/installer operation settles, including cancellation/error.
public protocol ModelFileSecurityScope: Sendable {
    func begin(_ url: URL) -> Bool
    func end(_ url: URL)
}

public struct FoundationModelFileSecurityScope: ModelFileSecurityScope {
    public init() {}
    public func begin(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func end(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

public enum ModelFileImportError: Error, Equatable, Sendable {
    case invalidSelection, accessDenied, unsafeSource, unsafeStaging
}

/// Import exactly the selected expected basenames. Sources may be in different
/// Files directories. The actual manager owns hash/size/license validation and
/// atomic installation; original Files resources must never be modified.
public actor ModelFilesImporter {
    private let manager: ModelInstallationManager
    private let stagingRoot: URL
    public init(manager: ModelInstallationManager, stagingRootURL: URL) {
        self.manager = manager
        stagingRoot = stagingRootURL.isFileURL
            ? URL(fileURLWithPath: stagingRootURL.standardizedFileURL.path, isDirectory: true) : stagingRootURL
    }

    public func importFiles(_ files: [URL], manifest: ModelManifest,
                            access: any ModelFileSecurityScope = FoundationModelFileSecurityScope()) async throws -> VerifiedModel {
        try Task.checkCancellation()
        if !manifest.artifacts.isEmpty, manifest.artifacts.allSatisfy({ $0.role == .coreMLAsset }) {
            guard files.count == 1, let folder = files.first, folder.isFileURL else { throw ModelFileImportError.invalidSelection }
            guard access.begin(folder) else { throw ModelFileImportError.accessDenied }
            defer { access.end(folder) }
            try Task.checkCancellation()
            do {
                let info = try FileManager.default.attributesOfItem(atPath: folder.path)
                guard info[.type] as? FileAttributeType == .typeDirectory else { throw ModelFileImportError.unsafeSource }
                try PersistentFilePolicy.validateItem(folder, within: folder.deletingLastPathComponent())
            } catch { throw ModelFileImportError.unsafeSource }
            // The real installer already copies/hashes into private staging.
            // Keep this single granted folder scope alive through publication;
            // do not retain an additional complete tree in ModelImports.
            return try await manager.importDirectory(folder, manifest: manifest)
        }
        let expected = Set(manifest.artifacts.map(\.fileName))
        let names = files.map(\.lastPathComponent)
        guard !files.isEmpty, files.count == manifest.artifacts.count,
              Set(names).count == names.count, Set(names) == expected,
              expected.count == manifest.artifacts.count,
              files.allSatisfy({ $0.isFileURL }),
              manifest.artifacts.allSatisfy({ !$0.fileName.isEmpty && !$0.fileName.contains("/")
                  && !$0.fileName.contains("\\") && $0.byteCount > 0 }) else {
            throw ModelFileImportError.invalidSelection
        }
        var granted: [URL] = []
        defer { for url in granted.reversed() { access.end(url) } }
        for url in files {
            try Task.checkCancellation()
            guard access.begin(url) else { throw ModelFileImportError.accessDenied }
            granted.append(url)
            try Task.checkCancellation()
        }
        let parent = stagingRoot.deletingLastPathComponent()
        guard stagingRoot.isFileURL, stagingRoot.lastPathComponent == "ModelImports",
              parent.path != "/" else { throw ModelFileImportError.unsafeStaging }
        try PersistentFilePolicy.validateItem(parent, within: parent)
        if !FileManager.default.fileExists(atPath: stagingRoot.path) {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        }
        try PersistentFilePolicy.protectDirectory(stagingRoot)
        let operation = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: false)
        defer {
            // Only this call's freshly created UUID directory can be removed.
            if operation.deletingLastPathComponent().standardizedFileURL.path == stagingRoot.standardizedFileURL.path,
               (try? PersistentFilePolicy.validateItem(operation, within: stagingRoot)) != nil {
                try? FileManager.default.removeItem(at: operation)
            }
        }
        try PersistentFilePolicy.protectItem(operation, within: stagingRoot)
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            guard let source = files.first(where: { $0.lastPathComponent == artifact.fileName }) else {
                throw ModelFileImportError.invalidSelection
            }
            try Self.copy(source, to: operation.appendingPathComponent(artifact.fileName),
                          byteCount: artifact.byteCount, within: operation)
        }
        try Task.checkCancellation()
        return try await manager.importDirectory(operation, manifest: manifest)
    }

    private static func copy(_ source: URL, to destination: URL, byteCount: Int64, within root: URL) throws {
        try PersistentFilePolicy.validateItem(source, within: source.deletingLastPathComponent())
        let descriptor = source.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw ModelFileImportError.unsafeSource }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_nlink == 1,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw ModelFileImportError.unsafeSource }
        guard metadata.st_size == byteCount else { throw ModelInstallationError.sizeMismatch(source.lastPathComponent) }
        let outputDescriptor = destination.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard outputDescriptor >= 0 else { throw ModelFileImportError.unsafeStaging }
        let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        defer { try? output.close() }
        var count: Int64 = 0
        while let bytes = try input.read(upToCount: 65_536), !bytes.isEmpty {
            try Task.checkCancellation()
            let next = count.addingReportingOverflow(Int64(bytes.count))
            guard !next.overflow, next.partialValue <= byteCount else { throw ModelInstallationError.sizeMismatch(source.lastPathComponent) }
            try output.write(contentsOf: bytes); count = next.partialValue
        }
        guard count == byteCount else { throw ModelInstallationError.sizeMismatch(source.lastPathComponent) }
        try output.synchronize()
        try PersistentFilePolicy.protectItem(destination, within: root)
    }
}
