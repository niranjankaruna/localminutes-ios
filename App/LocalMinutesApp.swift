import Foundation
import SwiftUI

// Resources belong to the application, independently of scene/view lifetime.
@main
@MainActor
struct LocalMinutesApp: App {
    let application = RecordingApplication.shared

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-activity-controls") {
                RecordingActivityTestScreen(application: application, finished: false)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-test-activity-finished") {
                RecordingActivityTestScreen(application: application, finished: true)
            } else {
                LocalMinutesHomeView(application: application)
            }
            #else
            LocalMinutesHomeView(application: application)
            #endif
        }
    }
}
