#if os(iOS)
import SwiftUI

struct MeetingExportView: View {
    let controller: MeetingLibraryController
    let intelligence: MeetingIntelligenceController
    @Environment(\.dismiss) private var dismiss
    @State private var markdown = false
    private var generatedEditsPending: Bool {
        intelligence.hasSummaryEdits || intelligence.isSaving || intelligence.hasAnswerEdits
            || !intelligence.savingAnswerIDs.isEmpty || !intelligence.answerEditConflicts.isEmpty
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(controller.selected?.title ?? "Meeting").font(.title3.weight(.semibold))
                    Picker("Format", selection: $markdown) {
                        Text("Text").tag(false)
                        Text("Markdown").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("meeting.export.format")
                    if let text = try? controller.export(markdown: markdown) {
                        ShareLink(item: text) { Label("Share meeting", systemImage: "square.and.arrow.up") }
                            .frame(minHeight: 44)
                            .accessibilityLabel(markdown ? "Share Markdown" : "Share text")
                            .accessibilityIdentifier(markdown ? "meeting.export.markdown" : "meeting.export.text")
                    }
                } footer: { Text("Includes the title, original notes, and transcript.") }
                if let text = intelligence.exportText {
                    Section {
                        ShareLink(item: text) { Label("Share summary & answers", systemImage: "sparkles") }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("meeting.intelligence.share")
                            .disabled(generatedEditsPending)
                    } footer: {
                        Text(generatedEditsPending ? "Save your generated content edits before sharing." :
                             "Shares your saved generated content separately from the original meeting.")
                    }
                }
            }
            .minutesList().navigationTitle("Export meeting").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .screenshotReady(controller.selected != nil)
        }
        .presentationDetents([.medium, .large])
        .tint(MinutesStyle.accent)
    }
}
#endif
