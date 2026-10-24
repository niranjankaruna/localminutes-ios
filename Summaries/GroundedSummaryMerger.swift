import Foundation

/// Test-first deterministic merge of separately validated map outputs. No model
/// inference, missing attribute filling, editing or persistence is implemented.
public enum GroundedSummaryMerger {
    public static func merge(_ maps: [GroundedSummary], selectedMeetingID: UUID,
                             source: GroundedSummarySource,
                             limits: GroundedSummaryLimits = .init()) throws -> GroundedSummary {
        GroundedSummary(meetingID: selectedMeetingID, summaryPoints: [], decisions: [], actions: [])
    }
}
