import Foundation

struct AppBuildIdentity: Equatable, Sendable {
    let version: String
    let build: String

    static func current(in bundle: Bundle = .main) -> AppBuildIdentity? {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AppBuildIdentity(version: version, build: build)
    }
}
