import Foundation

public enum AppleSummaryModel {
    public static let identifier = "apple-intelligence-on-device"
    public static let displayName = "Apple Intelligence"

    public static var currentSystemRevision: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
#if os(iOS)
        let platform = "ios"
#else
        let platform = "macos"
#endif
        return "apple-system-\(platform)-\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// This identifies the OS-managed provider, never an exact weight digest.
    public static func isSystemRevision(_ value: String) -> Bool {
        guard value.utf8.count <= 64 else { return false }
        let prefix = ["apple-system-ios-", "apple-system-macos-"].first { value.hasPrefix($0) }
        guard let prefix else { return false }
        let numbers = value.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == 3 && numbers.allSatisfy {
            !$0.isEmpty && $0.count <= 4 && $0.utf8.allSatisfy { (48...57).contains($0) }
        }
    }
}

public enum AppleSummaryAvailability: Equatable, Sendable {
    case available, unsupportedOS, deviceNotEligible, disabled, modelNotReady, unavailable

    public var explanation: String {
        switch self {
        case .available: "Ready on this iPhone. No model file to import."
        case .unsupportedOS: "Requires iOS 26 or later."
        case .deviceNotEligible: "Apple Intelligence is unavailable on this device."
        case .disabled: "Enable Apple Intelligence in iPhone Settings."
        case .modelNotReady: "Apple’s on-device model is not ready. The system manages its download."
        case .unavailable: "Apple’s on-device model is currently unavailable."
        }
    }
}
