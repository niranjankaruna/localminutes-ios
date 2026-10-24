import Foundation

/// Manifest names are relative archive-style paths, never URLs. The same
/// bounded parser is used by installation, Files import and HTTP staging.
enum ModelArtifactPath {
    static func components(_ value: String) -> [String]? {
        guard !value.isEmpty, value.utf8.count <= 1_024, !value.contains("\\") else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (1...8).contains(parts.count), parts.allSatisfy(component) else { return nil }
        return parts
    }
    static func component(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.first != "." && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }
    static func directories(for paths: [String]) -> Set<String> {
        var result: Set<String> = []
        for path in paths {
            let parts = path.split(separator: "/")
            for count in 1..<parts.count { result.insert(parts.prefix(count).joined(separator: "/")) }
        }
        return result
    }
    static func operationRoot(destination: URL, fileName: String, stagingRoot: URL) -> URL? {
        guard destination.isFileURL, stagingRoot.isFileURL, let parts = components(fileName),
              destination.standardizedFileURL.path == destination.path else { return nil }
        var operation = destination
        for _ in parts { operation.deleteLastPathComponent() }
        guard operation.deletingLastPathComponent().standardizedFileURL.path == stagingRoot.standardizedFileURL.path,
              let id = UUID(uuidString: operation.lastPathComponent), id.uuidString == operation.lastPathComponent,
              operation.appendingPathComponent(fileName).standardizedFileURL.path == destination.path else { return nil }
        return operation
    }
}
