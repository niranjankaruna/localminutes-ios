import Foundation

/// Deterministic merge of separately validated map outputs. No model inference,
/// missing attribute filling, editing or persistence is performed here.
public enum GroundedSummaryMerger {
    public static func merge(_ maps: [GroundedSummary], selectedMeetingID: UUID,
                             source: GroundedSummarySource,
                             limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        let validation = try GroundedSummaryValidation(selectedMeetingID: selectedMeetingID, source: source, limits: limits)
        guard maps.count <= limits.maximumItems else { throw GroundedSummaryError.limitExceeded }
        var total = 0
        for map in maps {
            let checked = try validation.summary(map)
            for count in [checked.summaryPoints.count, checked.decisions.count, checked.actions.count] {
                guard total <= limits.maximumItems - count else { throw GroundedSummaryError.limitExceeded }
                total += count
            }
        }
        let points = try mergePoints(maps.flatMap(\.summaryPoints), limits: limits)
        let decisions = try mergePoints(maps.flatMap(\.decisions), limits: limits)
        var actions: [GroundedActionKey: GroundedSummaryAction] = [:]
        for action in maps.flatMap(\.actions) {
            let key = GroundedActionKey(action)
            if let existing = actions[key] {
                guard same(existing.owner, action.owner), same(existing.due, action.due) else {
                    throw GroundedSummaryError.conflictingClaim
                }
                actions[key] = GroundedSummaryAction(task: existing.task, owner: existing.owner, due: existing.due,
                    evidence: try unionEvidence(existing.evidence + action.evidence, limits: limits),
                    provenance: try unionProvenance(existing.provenance + action.provenance, limits: limits))
            } else {
                actions[key] = GroundedSummaryAction(task: action.task, owner: action.owner, due: action.due,
                    evidence: action.evidence.sorted(by: GroundedSummaryValidation.evidenceLess),
                    provenance: action.provenance.sorted(by: GroundedSummaryValidation.provenanceLess))
            }
        }
        let orderedActions = actions.values.sorted {
            if let a = $0.evidence.first, let b = $1.evidence.first, GroundedEvidenceKey(a) != GroundedEvidenceKey(b) {
                return GroundedSummaryValidation.evidenceLess(a, b)
            }
            let a = Data($0.task.utf8), b = Data($1.task.utf8)
            if a != b { return a.lexicographicallyPrecedes(b) }
            return GroundedSummaryValidation.evidenceSequenceLess($0.evidence, $1.evidence)
        }
        let output = GroundedSummary(meetingID: selectedMeetingID, summaryPoints: points,
                                     decisions: decisions, actions: orderedActions)
        // The generated result remains separate from all immutable map/source
        // values. No partially merged output is returned on any failure.
        try validation.itemCount([points.count, decisions.count, orderedActions.count])
        return output
    }

    private static func mergePoints(_ points: [GroundedSummaryPoint], limits: GroundedSummaryLimits) throws -> [GroundedSummaryPoint] {
        var merged: [Data: GroundedSummaryPoint] = [:]
        for point in points {
            let key = Data(point.text.utf8)
            if let existing = merged[key] {
                merged[key] = GroundedSummaryPoint(text: existing.text,
                    evidence: try unionEvidence(existing.evidence + point.evidence, limits: limits),
                    provenance: try unionProvenance(existing.provenance + point.provenance, limits: limits))
            } else {
                merged[key] = GroundedSummaryPoint(text: point.text,
                    evidence: point.evidence.sorted(by: GroundedSummaryValidation.evidenceLess),
                    provenance: point.provenance.sorted(by: GroundedSummaryValidation.provenanceLess))
            }
        }
        return merged.values.sorted {
            if let a = $0.evidence.first, let b = $1.evidence.first, GroundedEvidenceKey(a) != GroundedEvidenceKey(b) {
                return GroundedSummaryValidation.evidenceLess(a, b)
            }
            return Data($0.text.utf8).lexicographicallyPrecedes(Data($1.text.utf8))
        }
    }

    private static func unionEvidence(_ input: [GroundedSummaryEvidence], limits: GroundedSummaryLimits) throws -> [GroundedSummaryEvidence] {
        var unique: [GroundedEvidenceKey: GroundedSummaryEvidence] = [:]
        for value in input {
            unique[GroundedEvidenceKey(value)] = value
            guard unique.count <= limits.maximumItems else { throw GroundedSummaryError.limitExceeded }
        }
        return unique.values.sorted(by: GroundedSummaryValidation.evidenceLess)
    }

    private static func unionProvenance(_ input: [SummaryGenerationProvenance], limits: GroundedSummaryLimits) throws -> [SummaryGenerationProvenance] {
        var unique: [GroundedProvenanceKey: SummaryGenerationProvenance] = [:]
        for value in input {
            unique[GroundedProvenanceKey(value)] = value
            guard unique.count <= limits.maximumItems else { throw GroundedSummaryError.limitExceeded }
        }
        return unique.values.sorted(by: GroundedSummaryValidation.provenanceLess)
    }

    private static func same(_ first: String?, _ second: String?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case let (a?, b?): return Data(a.utf8) == Data(b.utf8)
        default: return false
        }
    }
}
