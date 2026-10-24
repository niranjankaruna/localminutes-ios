#if DEBUG && os(iOS)
import Foundation
import SwiftUI

/// Test-first hook only. Entire declaration and all launch modes must disappear
/// from compiled Release products. No default application/data access on this path.
@MainActor
enum LibraryUITestFixture {
    static let releaseCanary = "LOCALMINUTES_DEBUG_LIBRARY_FIXTURE_CANARY_v1"
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-library-fixture")
    }
    static var token: UUID? {
        guard let value = ProcessInfo.processInfo.environment["LOCALMINUTES_UI_LIBRARY_TOKEN"] else { return nil }
        return UUID(uuidString: value)
    }

    static func makeApplication(token: UUID) async throws -> RecordingApplication? {
        // Deliberate no-op to obtain real hosted fixture/UI assertion RED.
        // Actual SQLite/CAF seeding is authorized only after that observation.
        nil
    }
}

@MainActor
struct LibraryUITestFixtureRoot: View {
    @State private var application: RecordingApplication?
    @State private var finished = false
    var body: some View {
        Group {
            if let application { LocalMinutesHomeView(application: application) }
            else if finished {
                Text("Library fixture unavailable.").accessibilityIdentifier("ui.fixture.library.failure")
            } else { ProgressView("Preparing library fixture…") }
        }
        .accessibilityIdentifier(LibraryUITestFixture.releaseCanary)
        .task {
            guard !finished else { return }
            defer { finished = true }
            guard let token = LibraryUITestFixture.token else { return }
            application = try? await LibraryUITestFixture.makeApplication(token: token)
        }
    }
}
#endif
