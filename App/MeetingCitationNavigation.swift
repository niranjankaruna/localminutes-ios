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
    func citationNavigationTarget(documentID: UUID, citationID: String) -> MeetingCitationNavigationTarget? {
        guard let citation = citations[documentID]?.first(where: { $0.id == citationID }) else { return nil }
        // The controller builds this collection only from stored documents and
        // exact quotes/ranges in this meeting's original transcript.
        return MeetingCitationNavigationTarget(meetingID: meetingID, segmentID: citation.sourceID,
            startSample: citation.startSample, endSample: citation.endSample)
    }
}
#endif
