import Foundation
import AVFoundation
import AudioToolbox
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

/// User-requested text values only; rendering does not write files or use a network.
public enum MeetingTextExporter {
    public static func markdown(_ document: MeetingExportDocument) throws -> String {
        let segments = try validatedSegments(document)
        var lines = ["# \(escaped(document.meeting.title))",
            "", "Created: \(dateString(document.meeting.createdAt))",
            "State: \(document.meeting.recordingState.rawValue)",
            "Captured duration: \(timestamp(document.meeting.capturedSampleCount))", "",
            "## Manual notes", "", escaped(document.manualNote?.text ?? "No manual notes."),
            "", "## Transcript", "", "Timing: utterance ranges on the 16 kHz meeting timeline.", ""]
        if segments.isEmpty {
            lines.append("No finalized transcript is available.")
        } else {
            for segment in segments {
                lines.append("- [\(timestamp(segment.startSample))–\(timestamp(segment.endSample))] \(escaped(segment.text))")
                lines.append("  Model: \(escaped(segment.modelRevision)); segment: \(segment.id.uuidString)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func plainText(_ document: MeetingExportDocument) throws -> String {
        let segments = try validatedSegments(document)
        var lines = [document.meeting.title, "", "Created: \(dateString(document.meeting.createdAt))",
            "State: \(document.meeting.recordingState.rawValue)",
            "Captured duration: \(timestamp(document.meeting.capturedSampleCount))", "",
            "Manual notes", "", document.manualNote?.text ?? "No manual notes.", "",
            "Transcript (utterance ranges on the 16 kHz meeting timeline)", ""]
        if segments.isEmpty {
            lines.append("No finalized transcript is available.")
        } else {
            for segment in segments {
                lines.append("[\(timestamp(segment.startSample))–\(timestamp(segment.endSample))] \(segment.text)")
                lines.append("Model: \(segment.modelRevision); segment: \(segment.id.uuidString)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func validatedSegments(_ document: MeetingExportDocument) throws -> [StoredTranscriptSegment] {
        guard document.manualNote == nil || document.manualNote?.meetingID == document.meeting.id,
              document.transcript.allSatisfy({ $0.meetingID == document.meeting.id }) else {
            throw MeetingExportError.crossMeetingContent
        }
        guard document.meeting.createdAt.timeIntervalSince1970.isFinite,
              document.meeting.capturedSampleCount >= 0,
              document.transcript.allSatisfy({
                  $0.sequence >= 0 && $0.startSample >= 0 && $0.endSample >= $0.startSample
              }), Set(document.transcript.map(\.id)).count == document.transcript.count,
              Set(document.transcript.map(\.sequence)).count == document.transcript.count else {
            throw MeetingExportError.invalidTranscript
        }
        return document.transcript.sorted { $0.sequence < $1.sequence }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func timestamp(_ sample: Int64) -> String {
        // Integer division avoids floating drift and multiplication overflow.
        let milliseconds = sample / 16
        return String(format: "%02lld:%02lld:%02lld.%03lld", milliseconds / 3_600_000,
            milliseconds / 60_000 % 60, milliseconds / 1_000 % 60, milliseconds % 1_000)
    }

    private static func escaped(_ source: String) -> String {
        let entities = source.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let active: Set<Character> = ["\\", "`", "*", "_", "[", "]", "(", ")", "!", "#", "|", "{", "}", "~"]
        return entities.reduce(into: "") { result, character in
            if active.contains(character) { result.append("\\") }
            result.append(character)
        }
    }
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

/// Resolves only owned durable CAF samples. No seek is clamped across a gap.
/// Native playback and physical speaker behavior are separate integration gates.
public enum MeetingPlaybackMapper {
    public static func locate(globalSample: Int64, meetingID: UUID,
                              manifest: AudioCaptureManifest,
                              meetingDirectory: URL) throws -> MeetingPlaybackLocation? {
        guard meetingID == manifest.sessionID else { throw MeetingPlaybackError.wrongMeeting }
        guard globalSample >= 0 else { throw MeetingPlaybackError.invalidPosition }
        guard manifest.schemaVersion == 1, manifest.totalFrames >= 0 else {
            throw MeetingPlaybackError.invalidManifest
        }
        guard meetingDirectory.isFileURL else { throw MeetingPlaybackError.unsafePath }
        var previousEnd: Int64 = 0
        var total: Int64 = 0
        var selected: StoredAudioSegment?
        for segment in manifest.segments {
            guard segment.startFrame >= previousEnd, segment.frameCount > 0 else {
                throw MeetingPlaybackError.invalidManifest
            }
            let (end, endOverflow) = segment.startFrame.addingReportingOverflow(segment.frameCount)
            let (sum, sumOverflow) = total.addingReportingOverflow(segment.frameCount)
            guard !endOverflow, !sumOverflow else { throw MeetingPlaybackError.invalidManifest }
            guard safeRelativePath(segment.relativePath) else { throw MeetingPlaybackError.unsafePath }
            if globalSample >= segment.startFrame && globalSample < end { selected = segment }
            previousEnd = end
            total = sum
        }
        guard total == manifest.totalFrames else { throw MeetingPlaybackError.invalidManifest }
        guard let segment = selected else { return nil }
        let root = meetingDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(segment.relativePath).standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { throw MeetingPlaybackError.unsafePath }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { throw MeetingPlaybackError.missingAudio }
        let audio: AVAudioFile
        do { audio = try AVAudioFile(forReading: candidate) }
        catch { throw MeetingPlaybackError.unreadableAudio }
        let settings = audio.fileFormat.settings
        guard audio.fileFormat.sampleRate == 16_000, audio.fileFormat.channelCount == 1,
              audio.length == segment.frameCount,
              (settings[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatLinearPCM,
              (settings[AVLinearPCMBitDepthKey] as? NSNumber)?.intValue == 16 else {
            throw MeetingPlaybackError.unreadableAudio
        }
        let offset = globalSample - segment.startFrame
        return MeetingPlaybackLocation(fileURL: candidate, frameOffset: offset,
                                       remainingFrames: segment.frameCount - offset)
    }

    private static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !(path as NSString).isAbsolutePath,
              !path.contains("\\"), !path.contains("\0") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
