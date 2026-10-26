#if os(iOS)
import Foundation
import SwiftUI

/// Structured reading is safe only for the untouched original. Any user edit,
/// unsupported payload, or mismatched meeting falls back to the actual display
/// copy rather than silently substituting the immutable generated result.
struct SummaryPresentation {
    struct Section: Identifiable {
        let title: String
        let items: [String]
        var id: String { title }
    }
    let sections: [Section]

    init?(document: StoredGeneratedDocument, text: String) {
        guard document.kind == .summary, document.editRevision == 0, text == document.editedText,
              document.originalJSON.count <= 65_536,
              let payload = try? JSONSerialization.jsonObject(with: document.originalJSON) as? [String: Any],
              payload["schema_version"] as? Int == 1,
              let meeting = payload["meeting_id"] as? String, UUID(uuidString: meeting) == document.meetingID,
              let points = payload["summary_points"] as? [[String: Any]],
              let decisions = payload["decisions"] as? [[String: Any]],
              let actions = payload["actions"] as? [[String: Any]] else { return nil }
        let overview = points.compactMap { $0["text"] as? String }
        let decided = decisions.compactMap { $0["text"] as? String }
        guard overview.count == points.count, decided.count == decisions.count else { return nil }
        var tasks: [String] = []
        for action in actions {
            guard let task = action["task"] as? String else { return nil }
            tasks.append(task + (action["owner"] as? String).map { " — " + $0 }.orEmpty
                         + (action["due"] as? String).map { " (" + $0 + ")" }.orEmpty)
        }
        sections = [
            Section(title: "Overview", items: overview),
            Section(title: "Decisions", items: decided),
            Section(title: "Next steps", items: tasks)
        ].filter { !$0.items.isEmpty }
        if sections.isEmpty { return nil }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

struct SummaryReadingView: View {
    let document: StoredGeneratedDocument
    let text: String
    var body: some View {
        if let presentation = SummaryPresentation(document: document, text: text) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(presentation.sections) { section in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(section.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            Text(item).font(.body).lineSpacing(6).textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("meeting.generatedSummary.sections")
        } else {
            Text(text).font(.body).lineSpacing(6).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("meeting.generatedSummary.content")
        }
    }
}
#endif
