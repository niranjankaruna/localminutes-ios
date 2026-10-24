import Foundation
import AVFoundation
#if SWIFT_PACKAGE
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesCore
#endif

public enum MeetingRecoveryError: Error, Equatable, Sendable {
    case notImplemented, unsafePath, invalidManifest, metadataFailure, meetingInUse, filesystemFailure
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
        let report: MeetingRecoveryReport
        if FileManager.default.fileExists(atPath: reportURL.path), meeting.recordingState != .completed {
            do { report = try JSONDecoder().decode(MeetingRecoveryReport.self, from: boundedData(reportURL)) }
            catch { throw MeetingRecoveryError.invalidManifest }
            try validate(report, against: manifest)
        } else {
            report = try inspect(manifest, directory: directory, rows: rows)
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
        var names: Set<String> = []
        for segment in manifest.segments {
            guard safeAudioName(segment.relativePath), names.insert(segment.relativePath).inserted else {
                throw MeetingRecoveryError.unsafePath
            }
            let end = segment.startFrame.addingReportingOverflow(segment.frameCount)
            guard segment.startFrame >= previousEnd, segment.frameCount > 0,
                  segment.frameCount <= 960_000, !end.overflow else {
                throw MeetingRecoveryError.invalidManifest
            }
            let file = directory.appendingPathComponent(segment.relativePath)
            if FileManager.default.fileExists(atPath: file.path), try kind(file) != .typeRegular {
                throw MeetingRecoveryError.unsafePath
            }
            previousEnd = end.partialValue
        }
        guard previousEnd == manifest.totalFrames else { throw MeetingRecoveryError.invalidManifest }
    }

    private func inspect(_ manifest: AudioCaptureManifest, directory: URL,
                         rows: [StoredTranscriptSegment]) throws -> MeetingRecoveryReport {
        var durable: Int64 = 0
        var previousEnd: Int64 = 0
        var gaps: [AudioRecoveryGap] = []
        var quarantine: Set<String> = []
        let committed = Set(manifest.segments.map(\.relativePath))
        for segment in manifest.segments {
            if segment.startFrame > previousEnd {
                gaps.append(.init(startSample: previousEnd, endSample: segment.startFrame, reason: .manifestGap))
            }
            let end = segment.startFrame + segment.frameCount // Checked above.
            let file = directory.appendingPathComponent(segment.relativePath)
            if !FileManager.default.fileExists(atPath: file.path) {
                gaps.append(.init(startSample: segment.startFrame, endSample: end, reason: .missingAudio))
            } else {
                var valid = false
                if let audio = try? AVAudioFile(forReading: file) {
                    valid = audio.length == segment.frameCount && audio.fileFormat.sampleRate == 16_000
                        && audio.fileFormat.channelCount == 1 && audio.fileFormat.commonFormat == .pcmFormatInt16
                    audio.close()
                }
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
                quarantine.insert(file.lastPathComponent)
            }
        }
        return MeetingRecoveryReport(meetingID: manifest.sessionID, durableFrameCount: durable,
            timelineEndSample: manifest.totalFrames,
            resumeFromSample: min(rows.map(\.endSample).max() ?? 0, manifest.totalFrames),
            gaps: gaps, quarantinedFiles: quarantine.sorted())
    }

    private func validate(_ report: MeetingRecoveryReport, against manifest: AudioCaptureManifest) throws {
        guard report.meetingID == manifest.sessionID,
              report.timelineEndSample == manifest.totalFrames,
              report.durableFrameCount >= 0, report.durableFrameCount <= manifest.totalFrames,
              report.resumeFromSample >= 0, report.resumeFromSample <= manifest.totalFrames,
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
