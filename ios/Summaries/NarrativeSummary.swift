import Foundation

/// Readable meeting minutes and immutable evidence are deliberately separate.
/// A reference proves source membership, not the factual accuracy of model prose.
public struct NarrativeSummaryParagraph: Equatable, Sendable {
    public let text: String
    public let evidence: [GroundedSummaryEvidence]
    public let isSourceExcerpt: Bool
    public init(text: String, evidence: [GroundedSummaryEvidence], isSourceExcerpt: Bool = false) {
        self.text = text; self.evidence = evidence; self.isSourceExcerpt = isSourceExcerpt
    }
}

public struct NarrativeSummary: Equatable, Sendable {
    public let meetingID: UUID
    public let overview: NarrativeSummaryParagraph?
    public let bullets: [NarrativeSummaryParagraph]
    public let provenance: SummaryGenerationProvenance
    public init(meetingID: UUID, overview: NarrativeSummaryParagraph?, bullets: [NarrativeSummaryParagraph],
                provenance: SummaryGenerationProvenance) {
        self.meetingID = meetingID; self.overview = overview; self.bullets = bullets; self.provenance = provenance
    }
}

/// A contiguous reading unit may cross ASR boundaries. Every piece keeps its
/// original source identity and range; no generated text becomes source evidence.
struct NarrativeSourceUnit: Codable, Equatable, Sendable {
    let id: Int
    let segments: [SummaryEvidenceSegment]
    var text: String { segments.map(\.text).joined(separator: " ") }
    var evidence: [GroundedSummaryEvidence] {
        segments.map { .init(sourceID: $0.id, startSample: $0.startSample, endSample: $0.endSample, quote: $0.text) }
    }
}

struct NarrativeDraftParagraph: Codable, Equatable, Sendable {
    let text: String
    let sourceIDs: [Int]
    enum CodingKeys: String, CodingKey { case text; case sourceIDs = "source_ids" }

    var uniqueReferences: Self {
        var seen: Set<Int> = []
        return .init(text: text, sourceIDs: sourceIDs.filter { seen.insert($0).inserted })
    }
}

struct NarrativeSummaryDraft: Codable, Equatable, Sendable {
    let bullets: [NarrativeDraftParagraph]
    let overview: NarrativeDraftParagraph
}

public enum NarrativeSummaryError: Error, Equatable, Sendable {
    case invalidConfiguration, invalidTokenCount, invalidResponse, unsupportedEvidence, reviewRejected, contextExceeded, limitExceeded, alreadyRunning
}
