import Foundation

public enum AppleSummaryModel {
    public static let identifier = "apple-intelligence-on-device"
    public static let displayName = "Apple Intelligence"
}

extension ModelSelectionStore {
    // Test-first interfaces: no system-selection behavior before hosted RED.
    public func selectAppleIntelligence(available: Bool) async throws {
        throw ModelSelectionError.unavailableRuntime
    }
    public func isAppleIntelligenceSelected() throws -> Bool { false }
}
