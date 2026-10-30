#if os(iOS)
import SwiftUI

struct MeetingExportView: View {
    let controller: MeetingLibraryController
    let intelligence: MeetingIntelligenceController
    @Environment(\.dismiss) private var dismiss
    @State private var markdown = false
    private var meetingText: String? {
        #if DEBUG
        if AppScreenshotFixture.scene == .meetingExportFailure { return nil }
        #endif
        return try? controller.export(markdown: markdown)
    }
    private var generatedEditsPending: Bool {
        intelligence.hasSummaryEdits || intelligence.isSaving || intelligence.hasAnswerEdits
            || !intelligence.savingAnswerIDs.isEmpty || !intelligence.answerEditConflicts.isEmpty
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(controller.selected?.title ?? "Meeting").font(.title3.weight(.semibold))
                    MinutesChoicePicker(title: "Format", selection: $markdown,
                        options: [false, true], label: { $0 ? "Markdown" : "Text" })
                        .accessibilityIdentifier("meeting.export.format")
                    if let text = meetingText {
                        ShareLink(item: text) { Label("Share meeting", systemImage: "square.and.arrow.up") }
                            .buttonStyle(MinutesButtonStyle())
                            .accessibilityLabel(markdown ? "Share Markdown" : "Share text")
                            .accessibilityIdentifier(markdown ? "meeting.export.markdown" : "meeting.export.text")
                    } else {
                        Label("This meeting could not be prepared for sharing. Close this sheet and try again.",
                              systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(MinutesStyle.recording)
                            .accessibilityIdentifier("meeting.export.unavailable")
                    }
                } footer: { Text("Includes the title, original notes, and transcript.") }
                if let text = intelligence.exportText {
                    Section {
                        ShareLink(item: text) { Label("Share summary & answers", systemImage: "sparkles") }
                            .buttonStyle(MinutesButtonStyle(kind: .secondary))
                            .accessibilityIdentifier("meeting.intelligence.share")
                            .disabled(generatedEditsPending)
                    } footer: {
                        Text(generatedEditsPending ? "Save your generated content edits before sharing." :
                             "Shares your saved generated content separately from the original meeting.")
                            .accessibilityIdentifier("meeting.export.pendingEdits")
                    }
                }
            }
            .minutesList().navigationTitle("Export meeting").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .screenshotReady(controller.selected != nil)
        }
        .minutesSheet(compact: true)
    }
}
#endif
