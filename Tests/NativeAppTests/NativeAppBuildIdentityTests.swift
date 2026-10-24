#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

@MainActor
final class NativeAppBuildIdentityTests: XCTestCase {
    func testDisplayedBuildIdentityReadsTheActualHostedAppBundleVersionAndBuild() throws {
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertFalse(version.isEmpty); XCTAssertFalse(build.isEmpty)
        let identity = try XCTUnwrap(AppBuildIdentity.current(),
            "Settings must expose actual installed app metadata rather than a hardcoded release value")
        XCTAssertEqual(identity.version, version)
        XCTAssertEqual(identity.build, build)
    }
}
#endif
