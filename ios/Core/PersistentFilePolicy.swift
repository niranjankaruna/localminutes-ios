import Foundation
import Darwin

public enum PersistentFilePolicyError: Error, Equatable, Sendable {
    case invalidRoot, unsafePath, unsupportedItem
    case posixFailure(Int32)
}

/// Applies to explicitly owned persistent paths. Protection permits access after
/// the first unlock following reboot; physical locked access still needs proof.
public enum PersistentFilePolicy {
    private struct Boundary {
        let root: URL
        let canonicalRoot: URL

        init(_ directory: URL) throws {
            guard directory.isFileURL else { throw PersistentFilePolicyError.invalidRoot }
            let root = directory.standardizedFileURL
            guard root.path != "/", root.path.hasPrefix("/") else {
                throw PersistentFilePolicyError.invalidRoot
            }
            let values = try PersistentFilePolicy.fresh(root).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw PersistentFilePolicyError.invalidRoot
            }
            self.root = root
            canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        }

        func validate(_ item: URL) throws -> Bool {
            guard item.isFileURL else { throw PersistentFilePolicyError.unsafePath }
            let path = item.standardizedFileURL
            guard path.path == root.path || path.path.hasPrefix(root.path + "/") else {
                throw PersistentFilePolicyError.unsafePath
            }
            // Check each owned component, including ancestors of a newly copied
            // file. Resolving a link first and then inspecting it would hide it.
            let suffix = Array(path.pathComponents.dropFirst(root.pathComponents.count))
            var current = path
            var ownedAncestors = [current]
            while current.path != root.path {
                current.deleteLastPathComponent()
                ownedAncestors.append(current)
            }
            var isDirectory = false
            for current in ownedAncestors.reversed() {
                let values = try PersistentFilePolicy.fresh(current).resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey
                ])
                guard values.isSymbolicLink != true else { throw PersistentFilePolicyError.unsafePath }
                guard values.isDirectory == true || values.isRegularFile == true else {
                    throw PersistentFilePolicyError.unsupportedItem
                }
                if values.isRegularFile == true {
                    let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
                    guard let links = attributes[.referenceCount] as? NSNumber else {
                        throw PersistentFilePolicyError.unsupportedItem
                    }
                    // Permission/protection/backup changes affect the inode,
                    // including links outside this trusted pathname tree.
                    guard links.uint64Value == 1 else { throw PersistentFilePolicyError.unsafePath }
                }
                if current.path != path.path, values.isDirectory != true {
                    throw PersistentFilePolicyError.unsafePath
                }
                isDirectory = values.isDirectory == true
            }
            let expected = suffix.reduce(canonicalRoot) { $0.appendingPathComponent($1) }.standardizedFileURL
            guard path.resolvingSymlinksInPath().standardizedFileURL.path == expected.path else {
                throw PersistentFilePolicyError.unsafePath
            }
            return isDirectory
        }
    }

    /// Preflights the entire tree before changing any attribute. Symlinks are
    /// rejected even when their destination happens to remain inside the root.
    public static func protectDirectory(_ directory: URL) throws {
        let boundary = try Boundary(directory)
        var pending = [boundary.root]
        var items: [(URL, Bool)] = []
        while let item = pending.popLast() {
            let isDirectory = try boundary.validate(item)
            items.append((item, isDirectory))
            if isDirectory {
                pending += try FileManager.default.contentsOfDirectory(at: item,
                    includingPropertiesForKeys: nil, options: [])
            }
        }
        for (item, isDirectory) in items {
            _ = try boundary.validate(item)
            try applyAttributes(to: item, isDirectory: isDirectory)
        }
    }

    /// Covers a newly created item without scanning unrelated large recordings.
    public static func protectItem(_ item: URL, within trustedRoot: URL) throws {
        let boundary = try Boundary(trustedRoot)
        let isDirectory = try boundary.validate(item)
        try applyAttributes(to: item.standardizedFileURL, isDirectory: isDirectory)
    }

    /// Checks an existing owned path without changing its metadata. A generic
    /// database opener must not exclude a mixed-use parent and all its siblings.
    public static func validateItem(_ item: URL, within trustedRoot: URL) throws {
        let boundary = try Boundary(trustedRoot)
        _ = try boundary.validate(item)
    }

    /// The replacement is fully protected before rename. No throwing operation
    /// follows publication, so callers can preserve an existing current pointer
    /// whenever this method throws.
    public static func writeAtomically(_ data: Data, to destination: URL,
                                       within trustedRoot: URL) throws {
        let boundary = try Boundary(trustedRoot)
        guard destination.isFileURL else { throw PersistentFilePolicyError.unsafePath }
        let destination = destination.standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        guard destination.path != boundary.root.path, try boundary.validate(parent) else {
            throw PersistentFilePolicyError.unsafePath
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try boundary.validate(destination) == false else { throw PersistentFilePolicyError.unsafePath }
        } else {
            // A dangling link does not satisfy fileExists, but must still fail.
            let values = try? fresh(destination).resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { throw PersistentFilePolicyError.unsafePath }
        }
        try applyAttributes(to: parent, isDirectory: true)
        let temporary = parent.appendingPathComponent(".localminutes-write-\(UUID().uuidString).tmp")
        let descriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw PersistentFilePolicyError.posixFailure(errno) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? file.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        try protectItem(temporary, within: boundary.root)
        try file.write(contentsOf: data)
        try file.synchronize()
        try file.close()
        _ = try boundary.validate(temporary)
        _ = try boundary.validate(parent)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try boundary.validate(destination) == false else { throw PersistentFilePolicyError.unsafePath }
        } else {
            let values = try? fresh(destination).resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { throw PersistentFilePolicyError.unsafePath }
        }
        let status = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.rename(source, target) }
        }
        guard status == 0 else { throw PersistentFilePolicyError.posixFailure(errno) }
    }

    private static func applyAttributes(to item: URL, isDirectory: Bool) throws {
        var attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: isDirectory ? 0o700 : 0o600)
        ]
#if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
#endif
        // Propagate actual SDK errors. A Simulator may accept protection yet
        // report no class; do not invent metadata or equate that with a device.
        try FileManager.default.setAttributes(attributes, ofItemAtPath: item.path)
        var url = fresh(item)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private static func fresh(_ url: URL) -> URL { URL(fileURLWithPath: url.path) }
}
