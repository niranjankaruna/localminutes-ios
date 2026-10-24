import Foundation

public struct LibraryMaintenanceLease: Equatable, Sendable {
    let token: UUID
    init(token: UUID) { self.token = token }
}
