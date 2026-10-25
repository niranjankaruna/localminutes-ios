import Foundation
import AVFoundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesCore
#endif

public enum MeetingRecoveryError: Error, Equatable, Sendable {
    case unsafePath, invalidManifest, metadataFailure, meetingInUse, filesystemFailure
}

public enum AudioRecoveryGapReason: String, Codable, Sendable {
    case missingAudio, corruptAudio, manifestGap
}

public struct AudioRecoveryGap: Equatable, Codable, Sendable {
    public let startSample: Int64
    public let endSample: Int64
    public let reason: AudioRecoveryGapReason
}

public struct MeetingRecoveryReport: Equatable, Codable, Sendable {
    public let meetingID: UUID
    public let durableFrameCount: Int64
    public let timelineEndSample: Int64
    public let resumeFromSample: Int64
    public let gaps: [AudioRecoveryGap]
    public let quarantinedFiles: [String]
}

/// Reconciles only closed, committed native audio. An atomic report precedes
/// quarantine so reopening after metadata failure resumes the same durable plan.
public actor MeetingRecoveryCoordinator {
    private let store: SQLiteMeetingStore
    private let recordingsRoot: URL
    private let beforeMetadataUpdate: (@Sendable () async -> Void)?
    private var inFlight: Set<UUID> = []

    public init(store: SQLiteMeetingStore, recordingsRoot: URL) {
        self.store = store
        self.recordingsRoot = recordingsRoot.standardizedFileURL
        beforeMetadataUpdate = nil
    }

    // Test scheduling only: failure closes the actual SQLite connection after
    // real quarantine work. Production supplies no hook.
    init(store: SQLiteMeetingStore, recordingsRoot: URL,
         beforeMetadataUpdate: @escaping @Sendable () async -> Void) {
        self.store = store
        self.recordingsRoot = recordingsRoot.standardizedFileURL
        self.beforeMetadataUpdate = beforeMetadataUpdate
    }

    public func recover(meetingID: UUID, activeMeetingIDs: Set<UUID> = []) async throws -> MeetingRecoveryReport {
        guard !activeMeetingIDs.contains(meetingID), inFlight.insert(meetingID).inserted else {
            throw MeetingRecoveryError.meetingInUse
        }
        defer { inFlight.remove(meetingID) }
        let meeting: MeetingRecord
        let rows: [StoredTranscriptSegment]
        do {
            guard let found = try await store.meeting(id: meetingID) else {
                throw MeetingRecoveryError.metadataFailure
            }
            meeting = found
            rows = try await store.transcript(meetingID: meetingID)
        } catch { throw MeetingRecoveryError.metadataFailure }

        let directory = recordingsRoot.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try validateOwnedTree(directory)
        let manifestURL = directory.appendingPathComponent("capture-manifest.json")
        let manifest: AudioCaptureManifest
        do { manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: boundedData(manifestURL)) }
        catch let error as MeetingRecoveryError { throw error }
        catch { throw MeetingRecoveryError.invalidManifest }
        try validate(manifest, for: meetingID, directory: directory)
        let reportURL = directory.appendingPathComponent("recovery-report.json")
        // Rebuild the plan from the source manifest and actual decoded files on
        // every attempt. A journal is retry evidence, never file-move authority.
        // This also recognizes a previously quarantined corrupt/tail file, so a
        // real metadata failure can be retried without classifying it as lost.
        let observed = try inspect(manifest, directory: directory, rows: rows)
        let report: MeetingRecoveryReport
        if FileManager.default.fileExists(atPath: reportURL.path), meeting.recordingState != .completed {
            do { report = try JSONDecoder().decode(MeetingRecoveryReport.self, from: boundedData(reportURL)) }
            catch { throw MeetingRecoveryError.invalidManifest }
            try validate(report, against: manifest)
            guard report == observed else { throw MeetingRecoveryError.invalidManifest }
        } else {
            report = observed
        }
        // Finished meetings may be inspected, but recovery never rewrites them.
        guard meeting.recordingState != .completed else { return report }
        do {
            try PersistentFilePolicy.protectDirectory(directory)
            if !FileManager.default.fileExists(atPath: reportURL.path) {
                try PersistentFilePolicy.writeAtomically(try JSONEncoder().encode(report),
                    to: reportURL, within: directory)
            }
            if !report.quarantinedFiles.isEmpty {
                let quarantine = directory.appendingPathComponent("RecoveryQuarantine", isDirectory: true)
                if !FileManager.default.fileExists(atPath: quarantine.path) {
                    try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
                }
                try PersistentFilePolicy.protectDirectory(quarantine)
                for name in report.quarantinedFiles {
                    let source = directory.appendingPathComponent(name)
                    let destination = quarantine.appendingPathComponent(name)
                    let sourceExists = FileManager.default.fileExists(atPath: source.path)
                    let destinationExists = FileManager.default.fileExists(atPath: destination.path)
                    guard !(sourceExists && destinationExists), sourceExists || destinationExists else {
                        throw MeetingRecoveryError.filesystemFailure
                    }
                    if sourceExists { try FileManager.default.moveItem(at: source, to: destination) }
                }
            }
        } catch let error as MeetingRecoveryError { throw error }
        catch { throw MeetingRecoveryError.filesystemFailure }
        await beforeMetadataUpdate?()
        do {
            try await store.updateRecordingState(id: meetingID, state: .recovered,
                                                  capturedSampleCount: report.durableFrameCount)
        } catch { throw MeetingRecoveryError.metadataFailure }
        return report
    }

    private func validateOwnedTree(_ directory: URL) throws {
        guard recordingsRoot.isFileURL, directory.deletingLastPathComponent() == recordingsRoot,
              try kind(recordingsRoot) == .typeDirectory, try kind(directory) == .typeDirectory,
              directory.resolvingSymlinksInPath().deletingLastPathComponent()
                == recordingsRoot.resolvingSymlinksInPath() else {
            throw MeetingRecoveryError.unsafePath
        }
        var pending = [directory]
        var entries = 0
        while let next = pending.popLast() {
            for child in try FileManager.default.contentsOfDirectory(at: next, includingPropertiesForKeys: nil) {
                entries += 1
                guard entries <= 8_192 else { throw MeetingRecoveryError.invalidManifest }
                let type = try kind(child)
                guard type == .typeRegular || type == .typeDirectory else {
                    throw MeetingRecoveryError.unsafePath
                }
                if type == .typeDirectory { pending.append(child) }
            }
        }
    }

    private func kind(_ url: URL) throws -> FileAttributeType? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch { throw MeetingRecoveryError.unsafePath }
    }

    private func boundedData(_ url: URL) throws -> Data {
        guard try kind(url) == .typeRegular,
              let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.int64Value >= 0, size.int64Value <= 1_048_576 else {
            throw MeetingRecoveryError.invalidManifest
        }
        return try Data(contentsOf: url)
    }

    private func safeAudioName(_ name: String) -> Bool {
        name.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil
    }

    private func validate(_ manifest: AudioCaptureManifest, for id: UUID, directory: URL) throws {
        guard manifest.schemaVersion == 1, manifest.sessionID == id,
              manifest.totalFrames >= 0, manifest.segments.count <= 4_096 else {
            throw MeetingRecoveryError.invalidManifest
        }
        var previousEnd: Int64 = 0
        var capturedFrames: Int64 = 0
        var names: Set<String> = []
        for segment in manifest.segments {
            guard safeAudioName(segment.relativePath), names.insert(segment.relativePath).inserted else {
                throw MeetingRecoveryError.unsafePath
            }
            let end = segment.startFrame.addingReportingOverflow(segment.frameCount)
            let captured = capturedFrames.addingReportingOverflow(segment.frameCount)
            guard segment.startFrame >= previousEnd, segment.frameCount > 0,
                  segment.frameCount <= 960_000, !end.overflow, !captured.overflow else {
                throw MeetingRecoveryError.invalidManifest
            }
            let file = directory.appendingPathComponent(segment.relativePath)
            if FileManager.default.fileExists(atPath: file.path), try kind(file) != .typeRegular {
                throw MeetingRecoveryError.unsafePath
            }
            previousEnd = end.partialValue
            capturedFrames = captured.partialValue
        }
        // totalFrames is captured audio, matching the existing playback mapper.
        // Global timeline extent can be larger when the manifest contains gaps.
        guard capturedFrames == manifest.totalFrames else { throw MeetingRecoveryError.invalidManifest }
    }

    private func inspect(_ manifest: AudioCaptureManifest, directory: URL,
                         rows: [StoredTranscriptSegment]) throws -> MeetingRecoveryReport {
        var durable: Int64 = 0
        var previousEnd: Int64 = 0
        var gaps: [AudioRecoveryGap] = []
        var quarantine: Set<String> = []
        let committed = Set(manifest.segments.map(\.relativePath))
        let quarantineDirectory = directory.appendingPathComponent("RecoveryQuarantine", isDirectory: true)
        let hasQuarantine = FileManager.default.fileExists(atPath: quarantineDirectory.path)
        if hasQuarantine, try kind(quarantineDirectory) != .typeDirectory {
            throw MeetingRecoveryError.unsafePath
        }
        for segment in manifest.segments {
            if segment.startFrame > previousEnd {
                gaps.append(.init(startSample: previousEnd, endSample: segment.startFrame, reason: .manifestGap))
            }
            let end = segment.startFrame + segment.frameCount // Checked above.
            let file = directory.appendingPathComponent(segment.relativePath)
            let saved = quarantineDirectory.appendingPathComponent(segment.relativePath)
            let originalExists = FileManager.default.fileExists(atPath: file.path)
            let savedExists = hasQuarantine && FileManager.default.fileExists(atPath: saved.path)
            guard !(originalExists && savedExists) else { throw MeetingRecoveryError.invalidManifest }
            if !originalExists && !savedExists {
                gaps.append(.init(startSample: segment.startFrame, endSample: end, reason: .missingAudio))
            } else {
                let valid = fullyReadable(savedExists ? saved : file, expectedFrames: segment.frameCount)
                // A healthy committed file in quarantine cannot be justified by
                // a report claiming corruption. Preserve it and fail closed.
                guard !(savedExists && valid) else { throw MeetingRecoveryError.invalidManifest }
                if valid { durable += segment.frameCount }
                else {
                    gaps.append(.init(startSample: segment.startFrame, endSample: end, reason: .corruptAudio))
                    quarantine.insert(segment.relativePath)
                }
            }
            previousEnd = end
        }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if safeAudioName(file.lastPathComponent), !committed.contains(file.lastPathComponent) {
                guard try kind(file) == .typeRegular else { throw MeetingRecoveryError.unsafePath }
                if hasQuarantine, FileManager.default.fileExists(atPath:
                    quarantineDirectory.appendingPathComponent(file.lastPathComponent).path) {
                    throw MeetingRecoveryError.invalidManifest
                }
                quarantine.insert(file.lastPathComponent)
            }
        }
        if hasQuarantine {
            for file in try FileManager.default.contentsOfDirectory(at: quarantineDirectory,
                includingPropertiesForKeys: nil) {
                if safeAudioName(file.lastPathComponent), !committed.contains(file.lastPathComponent) {
                    guard try kind(file) == .typeRegular else { throw MeetingRecoveryError.unsafePath }
                    quarantine.insert(file.lastPathComponent)
                }
            }
        }
        return MeetingRecoveryReport(meetingID: manifest.sessionID, durableFrameCount: durable,
            timelineEndSample: previousEnd,
            resumeFromSample: min(rows.map(\.endSample).max() ?? 0, previousEnd),
            gaps: gaps, quarantinedFiles: quarantine.sorted())
    }

    /// Container length can describe frames whose PCM bytes were never written.
    /// Decode every claimed frame using one bounded buffer before counting the
    /// segment as durable; short reads/native errors quarantine the whole segment.
    private func fullyReadable(_ file: URL, expectedFrames: Int64) -> Bool {
        do {
            let audio = try AVAudioFile(forReading: file)
            defer { audio.close() }
            guard audio.length == expectedFrames, audio.fileFormat.sampleRate == 16_000,
                  audio.fileFormat.channelCount == 1, audio.fileFormat.commonFormat == .pcmFormatInt16,
                  let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4_096) else {
                return false
            }
            var decoded: Int64 = 0
            while decoded < expectedFrames {
                let requested = AVAudioFrameCount(min(Int64(buffer.frameCapacity), expectedFrames - decoded))
                try audio.read(into: buffer, frameCount: requested)
                guard buffer.frameLength > 0, buffer.frameLength <= requested else { return false }
                decoded += Int64(buffer.frameLength)
            }
            return decoded == expectedFrames
        } catch { return false }
    }

    private func validate(_ report: MeetingRecoveryReport, against manifest: AudioCaptureManifest) throws {
        let timelineEnd = manifest.segments.last.map { $0.startFrame + $0.frameCount } ?? 0
        guard report.meetingID == manifest.sessionID,
              report.timelineEndSample == timelineEnd,
              report.durableFrameCount >= 0, report.durableFrameCount <= manifest.totalFrames,
              report.resumeFromSample >= 0, report.resumeFromSample <= report.timelineEndSample,
              Set(report.quarantinedFiles).count == report.quarantinedFiles.count,
              report.quarantinedFiles.allSatisfy(safeAudioName) else {
            throw MeetingRecoveryError.invalidManifest
        }
        var previousEnd: Int64 = 0
        for gap in report.gaps {
            guard gap.startSample >= previousEnd, gap.endSample > gap.startSample,
                  gap.endSample <= report.timelineEndSample else { throw MeetingRecoveryError.invalidManifest }
            previousEnd = gap.endSample
        }
    }
}
