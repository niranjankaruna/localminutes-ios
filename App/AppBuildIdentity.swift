import Foundation

struct AppBuildIdentity: Equatable, Sendable {
    let version: String
    let build: String

    // Test-first seam: read actual app metadata only after hosted assertion RED.
    static func current(in bundle: Bundle = .main) -> AppBuildIdentity? { nil }
}
