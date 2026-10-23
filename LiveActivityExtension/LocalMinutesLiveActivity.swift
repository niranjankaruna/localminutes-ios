import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LocalMinutesLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MeetingLiveActivity()
    }
}

// Presentation interface only. T06 adds tested lifecycle and recording controls.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack {
                Text("LocalMinutes")
                Spacer()
                Text(context.state.status)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("LocalMinutes")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status)
                }
            } compactLeading: {
                Image(systemName: "mic")
            } compactTrailing: {
                Text("LM")
            } minimal: {
                Image(systemName: "mic")
            }
        }
    }
}
