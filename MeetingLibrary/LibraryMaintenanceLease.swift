import Foundation

public struct LibraryMaintenanceLease: Equatable, Sendable {
    let token: UUID
    init(token: UUID) { self.token = token }
}

extension MeetingUsageRegistry {
    /// TEST-FIRST seam. Actual shared registry guards must be implemented in
    /// their owning file after RED; no independent shadow admission state exists.
    public func beginMaintenance() throws -> LibraryMaintenanceLease { .init(token: UUID()) }
    public func endMaintenance(_ lease: LibraryMaintenanceLease) {}
}
