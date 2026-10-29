import Foundation

struct GroundedEvidenceKey: Hashable {
    let sourceID: Data
    let startSample: Int64
    let endSample: Int64
    let quote: Data
    init(_ value: GroundedSummaryEvidence) {
        sourceID = Data(value.sourceID.utf8); startSample = value.startSample
        endSample = value.endSample; quote = Data(value.quote.utf8)
    }
}

/// Validates immutable input identity and ordering. The writer separately
/// validates generated JSON and membership of its transcript references.
struct SummarySourceValidation {
    init(selectedMeetingID: UUID, source: GroundedSummarySource, limits: GroundedSummaryLimits) throws {
        guard (1...1_048_576).contains(limits.maximumJSONBytes),
              (1...128).contains(limits.maximumItems),
              (1...4_096).contains(limits.maximumQuoteUTF8Bytes) else {
            throw GroundedSummaryError.invalidLimits
        }
        guard source.meetingID == selectedMeetingID else { throw GroundedSummaryError.meetingMismatch }
        guard source.segments.count <= 65_536 else { throw GroundedSummaryError.invalidSource }
        var seen: Set<Data> = []
        var previousEnd: Int64?
        for segment in source.segments {
            try Task.checkCancellation()
            guard !segment.id.isEmpty, segment.id.utf8.count <= 256,
                  !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.text.utf8.count <= 1_048_576,
                  segment.startSample >= 0, segment.endSample >= segment.startSample,
                  seen.insert(Data(segment.id.utf8)).inserted else {
                throw GroundedSummaryError.invalidSource
            }
            if let previousEnd, segment.startSample < previousEnd { throw GroundedSummaryError.invalidSource }
            previousEnd = segment.endSample
        }
    }

    func provenance(_ value: SummaryGenerationProvenance) throws {
        let revision = value.modelRevision.utf8
        guard revision.count == 40,
              revision.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              !value.promptVersion.isEmpty, value.promptVersion.utf8.count <= 256, value.mapIndex >= 0 else {
            throw GroundedSummaryError.invalidProvenance
        }
    }

    static func evidenceLess(_ first: GroundedSummaryEvidence, _ second: GroundedSummaryEvidence) -> Bool {
        if first.startSample != second.startSample { return first.startSample < second.startSample }
        if first.endSample != second.endSample { return first.endSample < second.endSample }
        let a = Data(first.sourceID.utf8), b = Data(second.sourceID.utf8)
        if a != b { return a.lexicographicallyPrecedes(b) }
        return Data(first.quote.utf8).lexicographicallyPrecedes(Data(second.quote.utf8))
    }
}
