#if os(iOS)
import Foundation

/// The detail view needs both transcript identity and its validated media range;
/// an audio offset alone cannot identify the row that should become visible.
struct MeetingCitationNavigationTarget: Equatable, Sendable {
    let meetingID: UUID
    let segmentID: UUID
    let startSample: Int64
    let endSample: Int64
}

extension MeetingIntelligenceController {
    // Test-first seam. After hosted behavioral RED, citation buttons will pass
    // this complete target to the actual detail transcript selection/scroll and
    // existing request-owned audio playback, replacing the offset-only callback.
    func citationNavigationTarget(documentID: UUID, citationID: String) -> MeetingCitationNavigationTarget? {
        nil
    }
}
#endif
