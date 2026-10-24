import Foundation

/// Test-first boundary for untrusted generation. Only exact extractive support
/// is in this slice; general semantic entailment and the model pipeline are not.
public enum GroundedSummaryDecoder {
    public static func decode(_ data: Data, selectedMeetingID: UUID, source: GroundedSummarySource,
                              provenance: SummaryGenerationProvenance,
                              limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        GroundedSummary(meetingID: selectedMeetingID, summaryPoints: [], decisions: [], actions: [])
    }
}
