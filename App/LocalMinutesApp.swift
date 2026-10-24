import Foundation
import SwiftUI

// Resources belong to the application, independently of scene/view lifetime.
@main
@MainActor
struct LocalMinutesApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if LibraryUITestFixture.requested {
                LibraryUITestFixtureRoot()
            } else if ProcessInfo.processInfo.arguments.contains("--ui-test-activity-controls") {
                RecordingActivityTestScreen(application: RecordingApplication.shared, finished: false)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-test-activity-finished") {
                RecordingActivityTestScreen(application: RecordingApplication.shared, finished: true)
            } else {
                LocalMinutesHomeView(application: RecordingApplication.shared)
            }
            #else
            LocalMinutesHomeView(application: RecordingApplication.shared)
            #endif
        }
    }
}
