import CryptoKit
import Foundation

/// Receives validated metadata. Remote paths remain byte-exact even when an
/// installation stores a single selected file under its local basename.
public enum ModelInstallationIdentity {
    public static func make(repositoryID: String, revision: String, purpose: ModelPurpose,
                            repositoryRelativeFiles: [String]) -> String {
        let paths = repositoryRelativeFiles.map { Data($0.utf8) }
            .sorted { $0.lexicographicallyPrecedes($1) }
        var key = Data()
        for value in [Data(repositoryID.utf8), Data(revision.utf8), Data(purpose.rawValue.utf8)] + paths {
            key.append(contentsOf: "\(value.count):".utf8)
            key.append(value)
        }
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        return "hf-" + String(digest.prefix(32))
    }
}
