import Foundation

/// Last-resort presentation of original speech, never a model-written claim.
/// Labels remain in the saved/display text as well as machine-readable metadata.
enum NarrativeSourceExcerpt {
    static func paragraph(_ units: [NarrativeSourceUnit]) throws -> NarrativeDraftParagraph {
        guard !units.isEmpty, units.count <= 8, Set(units.map(\.id)).count == units.count,
              units.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw NarrativeSummaryError.unsupportedEvidence
        }
        let ordered = units.sorted { $0.id < $1.id }
        let text = ordered.map { "Transcript excerpt: “\($0.text)”" }.joined(separator: "\n")
        guard text.utf8.count <= 8_192 else { throw NarrativeSummaryError.contextExceeded }
        return .init(text: text, sourceIDs: ordered.map(\.id), isSourceExcerpt: true)
    }

    static func paragraphs(_ units: [NarrativeSourceUnit]) throws -> [NarrativeDraftParagraph] {
        // Source units are already small and retain complete original ranges.
        // Keep each independently readable; never select only the first N units.
        try units.map { try paragraph([$0]) }
    }

    static func overview(_ units: [NarrativeSourceUnit]) throws -> NarrativeDraftParagraph {
        guard let first = units.first, let last = units.last else { throw NarrativeSummaryError.unsupportedEvidence }
        // These are explicitly opening/closing excerpts, not a synthesized
        // conclusion. Full discussion coverage remains in the minutes below.
        return try paragraph(first.id == last.id ? [first] : [first, last])
    }

    static func validate(_ paragraph: NarrativeDraftParagraph, units: [NarrativeSourceUnit]) throws {
        let ids = Set(paragraph.sourceIDs)
        let selected = units.filter { ids.contains($0.id) }
        guard selected.count == ids.count, paragraph == (try self.paragraph(selected)) else {
            throw NarrativeSummaryError.unsupportedEvidence
        }
    }
}
