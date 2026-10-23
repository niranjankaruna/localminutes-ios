import SwiftUI

// Minimal composition interface for the native build gate. No capture adapter yet.
@main
struct LocalMinutesApp: App {
    private let coordinator = RecordingCoordinator()

    var body: some Scene {
        WindowGroup {
            Text("LocalMinutes")
        }
    }
}
