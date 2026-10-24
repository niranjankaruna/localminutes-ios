import Foundation

/// Boundary for untrusted generation. Only exact extractive support
/// is in this slice; general semantic entailment and the model pipeline are not.
public enum GroundedSummaryDecoder {
    public static func decode(_ data: Data, selectedMeetingID: UUID, source: GroundedSummarySource,
                              provenance: SummaryGenerationProvenance,
                              limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        let validation = try GroundedSummaryValidation(selectedMeetingID: selectedMeetingID, source: source, limits: limits)
        try validation.provenance(provenance)
        guard data.count <= limits.maximumJSONBytes else { throw GroundedSummaryError.limitExceeded }
        let raw: RawSummary
        do { raw = try JSONDecoder().decode(RawSummary.self, from: data) }
        catch { throw GroundedSummaryError.invalidJSON }
        guard raw.meeting_id == selectedMeetingID else { throw GroundedSummaryError.meetingMismatch }
        try validation.itemCount([raw.summary_points.count, raw.decisions.count, raw.actions.count])
        let output = GroundedSummary(meetingID: raw.meeting_id,
            summaryPoints: raw.summary_points.map { $0.point(provenance) },
            decisions: raw.decisions.map { $0.point(provenance) },
            actions: raw.actions.map { $0.action(provenance) })
        return try validation.summary(output)
    }
}

private struct RawSummary: Decodable {
    let meeting_id: UUID
    let summary_points: [RawPoint]
    let decisions: [RawPoint]
    let actions: [RawAction]
}

private struct RawEvidence: Decodable {
    let source_id: String
    let start_sample: Int64
    let end_sample: Int64
    let quote: String
    var evidence: GroundedSummaryEvidence {
        .init(sourceID: source_id, startSample: start_sample, endSample: end_sample, quote: quote)
    }
}

private struct RawPoint: Decodable {
    let text: String
    let evidence: [RawEvidence]
    func point(_ provenance: SummaryGenerationProvenance) -> GroundedSummaryPoint {
        .init(text: text, evidence: evidence.map(\.evidence), provenance: [provenance])
    }
}

private struct RawAction: Decodable {
    let task: String
    let owner: String?
    let due: String?
    let evidence: [RawEvidence]
    func action(_ provenance: SummaryGenerationProvenance) -> GroundedSummaryAction {
        .init(task: task, owner: owner, due: due, evidence: evidence.map(\.evidence), provenance: [provenance])
    }
}
