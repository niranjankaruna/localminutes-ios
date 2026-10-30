import Foundation

public enum MeetingContentAvailability: Equatable, Sendable {
    case available, absent, unknown
}

public struct MeetingContentStatus: Equatable, Sendable {
    public let transcript: MeetingContentAvailability
    public let summary: MeetingContentAvailability
    public init(transcript: MeetingContentAvailability, summary: MeetingContentAvailability) {
        self.transcript = transcript; self.summary = summary
    }
    public static let unknown = Self(transcript: .unknown, summary: .unknown)
}
