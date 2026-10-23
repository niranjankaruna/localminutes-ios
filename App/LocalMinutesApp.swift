import SwiftUI

// Application resource lifetime is independent of the view. The separate UI
// case still needs missing-control RED before replacing Text below.
@main
@MainActor
struct LocalMinutesApp: App {
    let application = RecordingApplication.shared

    var body: some Scene {
        WindowGroup {
            Text("LocalMinutes")
        }
    }
}
