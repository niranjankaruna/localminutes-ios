import CryptoKit
import Foundation

/// Receives validated metadata. This extraction deliberately retains the
/// current basename collision until the regression tests have hosted RED.
public enum ModelInstallationIdentity {
    public static func make(repositoryID: String, revision: String, purpose: ModelPurpose,
                            repositoryRelativeFiles: [String]) -> String {
        let names = repositoryRelativeFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
        let key = repositoryID + "@" + revision + ":" + purpose.rawValue
            + ":" + names.sorted().joined(separator: ",")
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "hf-" + String(digest.prefix(32))
    }
}
