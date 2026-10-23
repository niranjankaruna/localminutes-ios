import Foundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
import LocalMinutesRecording
#endif

public struct MeetingExportDocument: Sendable {
    public let meeting: MeetingRecord
    public let manualNote: StoredManualNote?
    public let transcript: [StoredTranscriptSegment]

    public init(meeting: MeetingRecord, manualNote: StoredManualNote?,
                transcript: [StoredTranscriptSegment]) {
        self.meeting = meeting
        self.manualNote = manualNote
        self.transcript = transcript
    }
}

public enum MeetingExportError: Error, Equatable, Sendable {
    case crossMeetingContent
    case invalidTranscript
}

/// No-op test-first rendering interfaces. No file export or network activity.
public enum MeetingTextExporter {
    public static func markdown(_ document: MeetingExportDocument) throws -> String { "" }
    public static func plainText(_ document: MeetingExportDocument) throws -> String { "" }
}

public struct MeetingPlaybackLocation: Equatable, Sendable {
    public let fileURL: URL
    public let frameOffset: Int64
    public let remainingFrames: Int64

    public init(fileURL: URL, frameOffset: Int64, remainingFrames: Int64) {
        self.fileURL = fileURL
        self.frameOffset = frameOffset
        self.remainingFrames = remainingFrames
    }
}

public enum MeetingPlaybackError: Error, Equatable, Sendable {
    case wrongMeeting
    case invalidPosition
    case invalidManifest
    case unsafePath
    case missingAudio
    case unreadableAudio
}

/// No-op test-first seek mapping. A player must later consume this value and
/// preserve gaps explicitly; mapping/readback is not an audible playback claim.
public enum MeetingPlaybackMapper {
    public static func locate(globalSample: Int64, meetingID: UUID,
                              manifest: AudioCaptureManifest,
                              meetingDirectory: URL) throws -> MeetingPlaybackLocation? { nil }
}
