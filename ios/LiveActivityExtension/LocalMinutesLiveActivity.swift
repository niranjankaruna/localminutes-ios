import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LocalMinutesLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MeetingLiveActivity()
    }
}

// Actual shared controls; physical Lock Screen rendering/delivery are separate
// device gates from the app-hosted shared-view Simulator assertions.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingActivityControls(meetingID: context.attributes.meetingID, state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    RecordingActivityControls(meetingID: context.attributes.meetingID,
                                              state: context.state)
                }
            } compactLeading: {
                Image(systemName: "mic")
            } compactTrailing: {
                RecordingActivityElapsed(state: context.state)
            } minimal: {
                Image(systemName: "mic")
            }
        }
    }
}
