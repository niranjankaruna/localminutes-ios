#if os(iOS)
import Foundation
import SwiftUI
import UIKit

/// Structured reading is safe only for the untouched original. Any user edit,
/// unsupported payload, or mismatched meeting falls back to the actual display
/// copy rather than silently substituting the immutable generated result.
struct SummaryPresentation {
    struct Section: Identifiable {
        let title: String
        let items: [String]
        var isBulleted = true
        var id: String { title }
    }
    let sections: [Section]

    init?(document: StoredGeneratedDocument, text: String, meetingStartedAt: Date? = nil) {
        guard document.kind == .summary, document.editRevision == 0, text == document.editedText,
              document.originalJSON.count <= 1_048_576,
              let payload = try? JSONSerialization.jsonObject(with: document.originalJSON) as? [String: Any],
              let meeting = payload["meeting_id"] as? String, UUID(uuidString: meeting) == document.meetingID else { return nil }
        let savedStart = (payload["meeting_started_at"] as? Double).flatMap {
            $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
        }
        let metadata = (savedStart ?? meetingStartedAt).map {
            SummaryOverviewFormatting.meetingDetails(startedAt: $0)
        } ?? []
        if payload["schema_version"] as? Int == 2 {
            guard let rawBullets = payload["bullets"] as? [[String: Any]] else { return nil }
            let bullets = rawBullets.compactMap { $0["text"] as? String }
            guard bullets.count == rawBullets.count,
                  bullets.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            var overviewPoints: [String] = []
            if let overview = payload["overview"] as? [String: Any] {
                guard let paragraph = overview["text"] as? String,
                      !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                overviewPoints = SummaryOverviewFormatting.points(paragraph)
            } else if !(payload["overview"] is NSNull) { return nil }
            if let savedItems = payload["overview_items"] {
                guard let items = savedItems as? [String], !items.isEmpty,
                      items.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
                overviewPoints = items
            } else { overviewPoints = metadata + overviewPoints }
            guard !overviewPoints.isEmpty || !bullets.isEmpty else { return nil }
            sections = [Section(title: "Overview", items: overviewPoints),
                        Section(title: "Minutes of Meetings", items: bullets)]
            return
        }
        guard payload["schema_version"] as? Int == 1,
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
            Section(title: "Overview", items: metadata + overview),
            Section(title: "Minutes of Meetings", items: decided + tasks)
        ]
        if sections.allSatisfy({ $0.items.isEmpty }) { return nil }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

struct SummaryReadingView: View {
    let document: StoredGeneratedDocument
    let text: String
    var meetingStartedAt: Date? = nil
    var body: some View {
        if let presentation = SummaryPresentation(document: document, text: text, meetingStartedAt: meetingStartedAt) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(presentation.sections.filter { !$0.items.isEmpty }) { section in
                    VStack(alignment: .leading, spacing: 16) {
                        if !section.title.isEmpty {
                            Text(section.title).font(.title3.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            JustifiedSummaryText(text: item, isBulleted: section.isBulleted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("meeting.generatedSummary.sections")
        } else {
            JustifiedSummaryText(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("meeting.generatedSummary.content")
        }
    }
}

/// SwiftUI Text has no justified alignment. A non-scrolling native text view
/// provides real paragraph justification, selectable text and hanging bullets.
struct JustifiedSummaryText: UIViewRepresentable {
    let text: String
    var isBulleted = false
    var isHeading = false
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .title3) private var headingSize: CGFloat = 20

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let font = UIFont.systemFont(ofSize: isHeading ? headingSize : bodySize,
            weight: isHeading ? .semibold : .regular)
        let value = Self.attributedText(text, font: font, bulleted: isBulleted)
        if !view.attributedText.isEqual(to: value) { view.attributedText = value }
        view.accessibilityLabel = text
        view.accessibilityTraits = isHeading ? [.header, .staticText] : .staticText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    static func attributedText(_ text: String, font: UIFont, bulleted: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 6
        if bulleted {
            let indent = font.pointSize * 1.25
            paragraph.headIndent = indent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])]
            paragraph.defaultTabInterval = indent
        }
        return NSAttributedString(string: bulleted ? "•\t" + text : text,
            attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph])
    }
}
#endif
