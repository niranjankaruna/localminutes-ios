import Foundation
import AVFoundation
import CryptoKit
#if SWIFT_PACKAGE
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
#endif

public struct TranscriptionReplayCheckpoint: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let meetingID: UUID
    public let manifestSHA256: String
    public let modelRevision: String
    /// Global resume position; explicit gaps are accounted, never decoded frames.
    public let nextGlobalSample: Int64
    public let committedSequence: Int
    public init(schemaVersion: Int = 1, meetingID: UUID, manifestSHA256: String,
                modelRevision: String, nextGlobalSample: Int64, committedSequence: Int) {
        self.schemaVersion = schemaVersion; self.meetingID = meetingID
        self.manifestSHA256 = manifestSHA256; self.modelRevision = modelRevision
        self.nextGlobalSample = nextGlobalSample; self.committedSequence = committedSequence
    }
}

public struct TranscriptionReplayReport: Equatable, Sendable {
    public let meetingID: UUID
    public let durableFrameCount: Int64
    public let replayedFrameCount: Int64
    public let timelineEndSample: Int64
    public let insertedSegmentIDs: [UUID]
    public let gaps: [AudioRecoveryGap]
    public init(meetingID: UUID, durableFrameCount: Int64, replayedFrameCount: Int64,
                timelineEndSample: Int64, insertedSegmentIDs: [UUID], gaps: [AudioRecoveryGap]) {
        self.meetingID = meetingID; self.durableFrameCount = durableFrameCount
        self.replayedFrameCount = replayedFrameCount; self.timelineEndSample = timelineEndSample
        self.insertedSegmentIDs = insertedSegmentIDs; self.gaps = gaps
    }
}

public enum TranscriptionReplayError: Error, Equatable, Sendable {
    case meetingInUse, invalidCheckpoint, invalidAudio, metadataFailure, modelUnavailable
}

/// Replays closed durable audio only. One shared meeting/model claim outlives
/// cancellation, native drain, checkpoint publication and model-file release.
@MainActor
public final class MeetingTranscriptionReplayCoordinator {
    @MainActor
    private final class Use: HeavyModelResourceLifecycle {
        let id: UUID
        let models: ModelInstallationManager
        let meetingLease: MeetingRecordingLease
        var gateLease: HeavyModelUseLease?
        var modelLease: ModelLease?
        var recognizer: CoreMLParakeetRecognizer?
        var work: Task<TranscriptionReplayReport, Error>?
        var completion: Task<TranscriptionReplayReport, Error>?
        var resourcesReleased = false
        init(id: UUID, models: ModelInstallationManager, meetingLease: MeetingRecordingLease) {
            self.id = id; self.models = models; self.meetingLease = meetingLease
        }
        func requestCancellation() { work?.cancel() }
        func drain() async throws { if let work { _ = await work.result } }
        func unloadAndReleaseModel() async throws {
            if let recognizer { await recognizer.unload(); self.recognizer = nil }
            if let modelLease { try await models.release(modelLease); self.modelLease = nil }
            resourcesReleased = true
        }
    }
    private struct Journal: Codable {
        let schemaVersion: Int
        let checkpoint: TranscriptionReplayCheckpoint
        let recoverySHA256: String
        let rowsSHA256: String
        let modelPinSHA256: String?
        let cursorProofSHA256: String
    }
    private struct CursorProof: Codable {
        let checkpoint: TranscriptionReplayCheckpoint
        let recoverySHA256: String
        let rowsSHA256: String
        let modelPinSHA256: String?
    }
    private struct ReplaySource: Sendable {
        let manifest: ModelManifest
        let profile: HuggingFaceRuntimeProfile
        let installationID: UUID
        let pinSHA256: String
    }
    private struct RowProof: Codable {
        let id: UUID, sequence: Int, start: Int64, end: Int64, text: String, revision: String
    }
    private struct Gap: Sendable {
        let start: Int64, end: Int64
        let reason: AudioRecoveryGapReason
    }
    private struct Plan: Sendable {
        let manifest: AudioCaptureManifest
        let manifestBytes: Data
        let report: MeetingRecoveryReport
        let reportBytes: Data
        let healthy: [StoredAudioSegment]
    }
    private let store: SQLiteMeetingStore
    private let models: ModelInstallationManager
    private let recordingsRoot: URL
    private let usage: MeetingUsageRegistry
    private let admission: HeavyModelAdmission
    private let afterClaim: (@Sendable () async -> Void)?
    private let afterCheckpoint: (@Sendable (TranscriptionReplayCheckpoint) async -> Void)?
    private var current: Use?

    public init(store: SQLiteMeetingStore, models: ModelInstallationManager,
                recordingsRoot: URL, usage: MeetingUsageRegistry, admission: HeavyModelAdmission) {
        self.store = store; self.models = models; self.recordingsRoot = recordingsRoot.standardizedFileURL
        self.usage = usage; self.admission = admission; afterClaim = nil; afterCheckpoint = nil
    }

    // Scheduling boundaries only. Production uses the public initializer; these
    // never replace file decoding, persistence, or actual model inference.
    init(store: SQLiteMeetingStore, models: ModelInstallationManager,
         recordingsRoot: URL, usage: MeetingUsageRegistry, admission: HeavyModelAdmission,
         afterClaim: @escaping @Sendable () async -> Void,
         afterCheckpoint: (@Sendable (TranscriptionReplayCheckpoint) async -> Void)? = nil) {
        self.store = store; self.models = models; self.recordingsRoot = recordingsRoot.standardizedFileURL
        self.usage = usage; self.admission = admission; self.afterClaim = afterClaim
        self.afterCheckpoint = afterCheckpoint
    }

    public func replay(meetingID: UUID) async throws -> TranscriptionReplayReport {
        try Task.checkCancellation()
        guard current == nil else { throw TranscriptionReplayError.meetingInUse }
        let meetingLease: MeetingRecordingLease
        do { meetingLease = try usage.beginRecording(meetingID: meetingID) }
        catch { throw TranscriptionReplayError.meetingInUse }
        let use = Use(id: meetingID, models: models, meetingLease: meetingLease)
        do { use.gateLease = try admission.acquire(purpose: .streamingASR, requestID: meetingID, resource: use) }
        catch { usage.endRecording(meetingLease); throw TranscriptionReplayError.meetingInUse }
        current = use
        let work = Task { @MainActor in
            await self.afterClaim?()
            try Task.checkCancellation()
            return try await self.perform(use)
        }
        use.work = work
        let completion = Task { @MainActor in
            let result = await work.result
            guard let lease = use.gateLease else { throw TranscriptionReplayError.meetingInUse }
            do { try await self.admission.cancelAndDrain(lease) }
            catch HeavyModelAdmissionError.staleLease where use.resourcesReleased { }
            // Only this invocation can release its exact meeting claim.
            self.usage.endRecording(use.meetingLease)
            if self.current === use { self.current = nil }
            return try result.get()
        }
        use.completion = completion
        return try await withTaskCancellationHandler { try await completion.value } onCancel: { work.cancel() }
    }

    public func checkpoint(meetingID: UUID) async throws -> TranscriptionReplayCheckpoint? {
        let directory = try checkedDirectory(meetingID)
        return try readJournal(directory)?.checkpoint
    }

    private func perform(_ use: Use) async throws -> TranscriptionReplayReport {
        let directory = try checkedDirectory(use.id)
        let initialRows = try await store.transcript(meetingID: use.id)
        guard let meeting = try await store.meeting(id: use.id) else { throw TranscriptionReplayError.metadataFailure }
        guard let pin = try await store.speechModelPin(meetingID: use.id) else {
            throw MeetingSpeechModelPinError.missingPin
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let source = ReplaySource(manifest: pin.selection.manifest, profile: pin.selection.profile,
            installationID: pin.selection.installationID, pinSHA256: Self.digest(try encoder.encode(pin)))
        let revision = source.manifest.revision
        try Task.checkCancellation()
        let reportURL = directory.appendingPathComponent("recovery-report.json")
        if try !Self.exists(reportURL) {
            _ = try await MeetingRecoveryCoordinator(store: store, recordingsRoot: recordingsRoot).recover(meetingID: use.id)
        }
        let root = recordingsRoot
        let meetingID = use.id
        let inspection = Task.detached(priority: .userInitiated) {
            try Self.inspect(directory: directory, root: root, id: meetingID)
        }
        let plan = try await withTaskCancellationHandler { try await inspection.value } onCancel: { inspection.cancel() }
        try Task.checkCancellation()
        try validateRows(initialRows, plan: plan, id: use.id)
        let journal = try readJournal(directory)
        var resume = initialRows.last?.endSample ?? 0
        if let journal {
            let point = journal.checkpoint
            guard journal.schemaVersion == 2, point.schemaVersion == 1, point.meetingID == use.id,
                  point.manifestSHA256 == Self.digest(plan.manifestBytes),
                  point.modelRevision == revision,
                  point.nextGlobalSample >= 0, point.nextGlobalSample <= plan.report.timelineEndSample,
                  point.committedSequence >= -1, point.committedSequence < initialRows.count,
                  journal.recoverySHA256 == Self.digest(plan.reportBytes),
                  journal.rowsSHA256 == (try rowsDigest(Array(initialRows.prefix(point.committedSequence + 1)))),
                  journal.modelPinSHA256 == source.pinSHA256,
                  journal.cursorProofSHA256 == (try cursorProof(point, recovery: journal.recoverySHA256,
                    rows: journal.rowsSHA256, modelPin: journal.modelPinSHA256)) else {
                throw TranscriptionReplayError.invalidCheckpoint
            }
            let committedEnd = point.committedSequence >= 0 ? initialRows[point.committedSequence].endSample : 0
            guard point.nextGlobalSample >= committedEnd else { throw TranscriptionReplayError.invalidCheckpoint }
            resume = max(resume, point.nextGlobalSample)
        }
        // The filesystem report is immutable evidence. Its original resume hint
        // may precede rows later committed by replay; it is not the replay cursor.
        guard plan.report.resumeFromSample == 0 || initialRows.contains(where: { $0.endSample == plan.report.resumeFromSample }) else {
            throw TranscriptionReplayError.invalidCheckpoint
        }
        try quarantine(plan, directory: directory)
        if meeting.recordingState != .completed {
            try await store.updateRecordingState(id: use.id, state: .recovered, capturedSampleCount: plan.report.durableFrameCount)
        }
        let remaining = plan.healthy.filter { $0.startFrame + $0.frameCount > resume }
        if remaining.isEmpty {
            if journal == nil {
                try writeCheckpoint(id: use.id, next: plan.report.timelineEndSample, rows: initialRows, plan: plan,
                    directory: directory, revision: revision, modelPin: source.pinSHA256)
            }
            return .init(meetingID: use.id, durableFrameCount: plan.report.durableFrameCount,
                replayedFrameCount: 0, timelineEndSample: plan.report.timelineEndSample,
                insertedSegmentIDs: [], gaps: plan.report.gaps)
        }
        let lease: ModelLease
        do { lease = try await models.acquire(modelID: source.manifest.modelID) }
        catch is CancellationError { throw CancellationError() }
        catch { throw TranscriptionReplayError.modelUnavailable }
        use.modelLease = lease
        guard lease.model.manifest == source.manifest,
              source.installationID == lease.model.installationID else {
            throw TranscriptionReplayError.modelUnavailable
        }
        guard source.profile == .parakeetTDTCoreML,
              (try? ParakeetModelPack.configuration(for: source.manifest)) != nil else {
            throw TranscriptionReplayError.modelUnavailable
        }
        let recognizer = CoreMLParakeetRecognizer(files: .init(
            directory: lease.model.directoryURL, manifest: source.manifest))
        use.recognizer = recognizer
        try await recognizer.load()
        return try await replayAudio(use, recognizer: recognizer, source: source, plan: plan,
            directory: directory, rows: initialRows, remaining: remaining, resume: resume)
    }

    private func commit(_ text: String, start: Int64, end: Int64,
        rows: inout [StoredTranscriptSegment], inserted: inout [UUID], plan: Plan,
        directory: URL, id: UUID, revision: String, modelPin: String?) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try Task.checkCancellation()
        guard end > start, start >= (rows.last?.endSample ?? 0), end <= plan.report.timelineEndSample else {
            throw TranscriptionReplayError.invalidAudio
        }
        let seed = "\(id.uuidString)|\(Self.digest(plan.manifestBytes))|\(revision)|\(start)|\(end)"
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        let row = StoredTranscriptSegment(id: uuid, meetingID: id, sequence: rows.count,
            startSample: start, endSample: end, text: text, modelRevision: revision)
        try await store.appendFinalizedSegments([row], to: id)
        rows.append(row); inserted.append(row.id)
        let checkpoint = try writeCheckpoint(id: id, next: end, rows: rows, plan: plan,
            directory: directory, revision: revision, modelPin: modelPin)
        await afterCheckpoint?(checkpoint)
    }

    private func replayAudio(_ use: Use, recognizer: CoreMLParakeetRecognizer, source: ReplaySource,
        plan: Plan, directory: URL, rows originalRows: [StoredTranscriptSegment],
        remaining: [StoredAudioSegment], resume: Int64) async throws -> TranscriptionReplayReport {
        try Task.checkCancellation()
        var rows = originalRows
        var inserted: [UUID] = []
        var cursor = resume
        var base = resume
        var relative: Int64 = 0
        var replayed: Int64 = 0
        var active = false
        let reader = ReplayCAFReader()
        do {
            for segment in remaining {
                try Task.checkCancellation()
                let start = max(resume, segment.startFrame)
                if active && start != cursor {
                    let ending = try await recognizer.finish()
                    try await commitFinals(ending, base: base, through: relative, rows: &rows, inserted: &inserted,
                        plan: plan, directory: directory, id: use.id, source: source)
                    active = false
                }
                if !active {
                    try await recognizer.start(epochID: use.id)
                    base = start; cursor = start; relative = 0; active = true
                }
                try await reader.open(directory.appendingPathComponent(segment.relativePath),
                    expectedFrames: segment.frameCount, offset: start - segment.startFrame)
                while let samples = try await reader.next() {
                    try Task.checkCancellation()
                    let output = try await recognizer.accept(samples, at: relative)
                    relative += Int64(samples.count); cursor += Int64(samples.count); replayed += Int64(samples.count)
                    try await commitFinals(output, base: base, through: relative, rows: &rows, inserted: &inserted,
                        plan: plan, directory: directory, id: use.id, source: source)
                }
                await reader.close()
            }
            if active {
                let ending = try await recognizer.finish()
                try await commitFinals(ending, base: base, through: relative, rows: &rows, inserted: &inserted,
                    plan: plan, directory: directory, id: use.id, source: source)
            }
            try Task.checkCancellation()
            try writeCheckpoint(id: use.id, next: plan.report.timelineEndSample, rows: rows, plan: plan,
                directory: directory, revision: source.manifest.revision, modelPin: source.pinSHA256)
            return .init(meetingID: use.id, durableFrameCount: plan.report.durableFrameCount,
                replayedFrameCount: replayed, timelineEndSample: plan.report.timelineEndSample,
                insertedSegmentIDs: inserted, gaps: plan.report.gaps)
        } catch {
            await reader.close()
            await recognizer.cancel(epochID: use.id)
            throw error
        }
    }

    private func commitFinals(_ update: SpeechUpdate, base: Int64, through: Int64,
        rows: inout [StoredTranscriptSegment], inserted: inout [UUID], plan: Plan,
        directory: URL, id: UUID, source: ReplaySource) async throws {
        guard update.epochID == id else { throw TranscriptionReplayError.invalidAudio }
        for segment in update.finalized {
            let start = base.addingReportingOverflow(segment.startSample)
            let end = base.addingReportingOverflow(segment.endSample)
            guard segment.startSample >= 0, segment.endSample > segment.startSample, segment.endSample <= through,
                  !start.overflow, !end.overflow else { throw TranscriptionReplayError.invalidAudio }
            try await commit(segment.text, start: start.partialValue, end: end.partialValue,
                rows: &rows, inserted: &inserted, plan: plan, directory: directory, id: id,
                revision: source.manifest.revision, modelPin: source.pinSHA256)
        }
    }

    @discardableResult
    private func writeCheckpoint(id: UUID, next: Int64, rows: [StoredTranscriptSegment], plan: Plan,
        directory: URL, revision: String, modelPin: String?) throws -> TranscriptionReplayCheckpoint {
        let point = TranscriptionReplayCheckpoint(meetingID: id, manifestSHA256: Self.digest(plan.manifestBytes),
            modelRevision: revision, nextGlobalSample: next, committedSequence: rows.count - 1)
        let recovery = Self.digest(plan.reportBytes), proof = try rowsDigest(rows)
        let journal = Journal(schemaVersion: 2, checkpoint: point, recoverySHA256: recovery,
            rowsSHA256: proof, modelPinSHA256: modelPin,
            cursorProofSHA256: try cursorProof(point, recovery: recovery, rows: proof, modelPin: modelPin))
        try PersistentFilePolicy.writeAtomically(try JSONEncoder().encode(journal),
            to: directory.appendingPathComponent("transcription-replay.json"), within: directory)
        return point
    }

    /// Integrity checksum of the complete committed position and its evidence.
    /// This detects cursor mutation retaining old proof fields; it is not a
    /// signature or a claim of authentication against arbitrary private writes.
    private func cursorProof(_ point: TranscriptionReplayCheckpoint, recovery: String,
        rows: String, modelPin: String?) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Self.digest(try encoder.encode(CursorProof(checkpoint: point, recoverySHA256: recovery,
            rowsSHA256: rows, modelPinSHA256: modelPin)))
    }

    private func readJournal(_ directory: URL) throws -> Journal? {
        let file = directory.appendingPathComponent("transcription-replay.json")
        guard try Self.exists(file) else { return nil }
        do { return try JSONDecoder().decode(Journal.self, from: Self.bounded(file, root: recordingsRoot)) }
        catch { throw TranscriptionReplayError.invalidCheckpoint }
    }

    private func rowsDigest(_ rows: [StoredTranscriptSegment]) throws -> String {
        let proof = rows.map { RowProof(id: $0.id, sequence: $0.sequence, start: $0.startSample,
            end: $0.endSample, text: $0.text, revision: $0.modelRevision) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return Self.digest(try encoder.encode(proof))
    }

    private func validateRows(_ rows: [StoredTranscriptSegment], plan: Plan, id: UUID) throws {
        var previous: Int64 = 0
        for (index, row) in rows.enumerated() {
            guard row.meetingID == id, row.sequence == index, row.startSample >= previous,
                  row.endSample > row.startSample, row.endSample <= plan.report.timelineEndSample,
                  !plan.report.gaps.contains(where: { row.startSample < $0.endSample && row.endSample > $0.startSample }) else {
                throw TranscriptionReplayError.invalidCheckpoint
            }
            previous = row.endSample
        }
    }

    private func checkedDirectory(_ id: UUID) throws -> URL {
        let directory = recordingsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try PersistentFilePolicy.validateItem(directory, within: recordingsRoot)
            var pending = [directory]; var count = 0
            while let parent = pending.popLast() {
                for child in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
                    count += 1
                    guard count <= 8_192 else { throw TranscriptionReplayError.invalidAudio }
                    try PersistentFilePolicy.validateItem(child, within: recordingsRoot)
                    if try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { pending.append(child) }
                }
            }
        } catch { throw TranscriptionReplayError.invalidAudio }
        return directory
    }

    private func quarantine(_ plan: Plan, directory: URL) throws {
        guard !plan.report.quarantinedFiles.isEmpty else { return }
        let quarantine = directory.appendingPathComponent("RecoveryQuarantine", isDirectory: true)
        if try !Self.exists(quarantine) {
            try FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: false)
        }
        try PersistentFilePolicy.protectItem(quarantine, within: directory)
        for name in plan.report.quarantinedFiles {
            let source = directory.appendingPathComponent(name)
            let destination = quarantine.appendingPathComponent(name)
            if try Self.exists(source) {
                guard try !Self.exists(destination) else { throw TranscriptionReplayError.invalidAudio }
                try PersistentFilePolicy.validateItem(source, within: directory)
                try FileManager.default.moveItem(at: source, to: destination)
            }
        }
    }

    private nonisolated static func inspect(directory: URL, root: URL, id: UUID) throws -> Plan {
        let manifestBytes = try bounded(directory.appendingPathComponent("capture-manifest.json"), root: root)
        let manifest = try JSONDecoder().decode(AudioCaptureManifest.self, from: manifestBytes)
        let reportBytes = try bounded(directory.appendingPathComponent("recovery-report.json"), root: root)
        let report = try JSONDecoder().decode(MeetingRecoveryReport.self, from: reportBytes)
        guard manifest.schemaVersion == 1, manifest.sessionID == id, manifest.totalFrames >= 0,
              manifest.segments.count <= 4_096, report.meetingID == id else { throw TranscriptionReplayError.invalidAudio }
        var names: Set<String> = []; var quarantineNames: Set<String> = []
        var previous: Int64 = 0; var total: Int64 = 0; var durable: Int64 = 0
        var gaps: [Gap] = []; var healthy: [StoredAudioSegment] = []
        let quarantine = directory.appendingPathComponent("RecoveryQuarantine", isDirectory: true)
        for segment in manifest.segments {
            try Task.checkCancellation()
            let end = segment.startFrame.addingReportingOverflow(segment.frameCount)
            let sum = total.addingReportingOverflow(segment.frameCount)
            guard audioName(segment.relativePath), names.insert(segment.relativePath).inserted,
                  segment.startFrame >= previous, segment.frameCount > 0, segment.frameCount <= 960_000,
                  !end.overflow, !sum.overflow else { throw TranscriptionReplayError.invalidAudio }
            if segment.startFrame > previous { gaps.append(.init(start: previous, end: segment.startFrame, reason: .manifestGap)) }
            let original = directory.appendingPathComponent(segment.relativePath)
            let saved = quarantine.appendingPathComponent(segment.relativePath)
            let originalExists = try exists(original), savedExists = try exists(saved)
            guard !(originalExists && savedExists) else { throw TranscriptionReplayError.invalidAudio }
            if !originalExists && !savedExists {
                gaps.append(.init(start: segment.startFrame, end: end.partialValue, reason: .missingAudio))
            } else {
                let file = savedExists ? saved : original
                try PersistentFilePolicy.validateItem(file, within: root)
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw TranscriptionReplayError.invalidAudio
                }
                let readable = try fullyReadable(file, frames: segment.frameCount)
                guard !(savedExists && readable) else { throw TranscriptionReplayError.invalidAudio }
                if readable { healthy.append(segment); durable += segment.frameCount }
                else {
                    gaps.append(.init(start: segment.startFrame, end: end.partialValue, reason: .corruptAudio))
                    quarantineNames.insert(segment.relativePath)
                }
            }
            previous = end.partialValue; total = sum.partialValue
        }
        for parent in [directory, quarantine] where try exists(parent) {
            for file in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                where audioName(file.lastPathComponent) && !names.contains(file.lastPathComponent) {
                try PersistentFilePolicy.validateItem(file, within: root)
                guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw TranscriptionReplayError.invalidAudio
                }
                guard quarantineNames.insert(file.lastPathComponent).inserted else { throw TranscriptionReplayError.invalidAudio }
            }
        }
        guard total == manifest.totalFrames, report.durableFrameCount == durable, report.timelineEndSample == previous,
              report.resumeFromSample >= 0, report.resumeFromSample <= previous,
              report.quarantinedFiles == quarantineNames.sorted(), gaps.count == report.gaps.count,
              zip(gaps, report.gaps).allSatisfy({ $0.0.start == $0.1.startSample && $0.0.end == $0.1.endSample && $0.0.reason == $0.1.reason }) else {
            throw TranscriptionReplayError.invalidAudio
        }
        return Plan(manifest: manifest, manifestBytes: manifestBytes, report: report,
            reportBytes: reportBytes, healthy: healthy)
    }

    private nonisolated static func fullyReadable(_ url: URL, frames: Int64) throws -> Bool {
        do {
            let file = try AVAudioFile(forReading: url)
            defer { file.close() }
            guard file.length == frames, file.fileFormat.sampleRate == 16_000,
                  file.fileFormat.channelCount == 1, file.fileFormat.commonFormat == .pcmFormatInt16,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 3_200) else { return false }
            var count: Int64 = 0
            while count < frames {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(3_200, frames - count)))
                guard buffer.frameLength > 0 else { return false }
                count += Int64(buffer.frameLength)
            }
            return count == frames
        } catch is CancellationError { throw CancellationError() }
        catch { return false }
    }
    private nonisolated static func bounded(_ file: URL, root: URL) throws -> Data {
        try PersistentFilePolicy.validateItem(file, within: root)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, (1...1_048_576).contains(size) else {
            throw TranscriptionReplayError.invalidAudio
        }
        return try Data(contentsOf: file)
    }
    private nonisolated static func audioName(_ value: String) -> Bool {
        value.range(of: #"^segment-[0-9]{6}\.caf$"#, options: .regularExpression) != nil
    }
    private nonisolated static func exists(_ file: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: file.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return false }
    }
    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// All native file decoding stays off MainActor and uses one bounded PCM buffer.
private actor ReplayCAFReader {
    private var file: AVAudioFile?
    private var buffer: AVAudioPCMBuffer?
    private var remaining: Int64 = 0
    func open(_ url: URL, expectedFrames: Int64, offset: Int64) throws {
        close()
        let opened = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard opened.length == expectedFrames, offset >= 0, offset < expectedFrames,
              opened.processingFormat.sampleRate == 16_000, opened.processingFormat.channelCount == 1,
              let scratch = AVAudioPCMBuffer(pcmFormat: opened.processingFormat, frameCapacity: 3_200) else {
            opened.close(); throw TranscriptionReplayError.invalidAudio
        }
        opened.framePosition = offset
        file = opened; buffer = scratch; remaining = expectedFrames - offset
    }
    func next() throws -> [Float]? {
        guard remaining > 0 else { return nil }
        guard let file, let buffer else { throw TranscriptionReplayError.invalidAudio }
        let requested = AVAudioFrameCount(min(3_200, remaining))
        try file.read(into: buffer, frameCount: requested)
        guard buffer.frameLength == requested, let samples = buffer.floatChannelData?.pointee else {
            throw TranscriptionReplayError.invalidAudio
        }
        remaining -= Int64(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }
    func close() { file?.close(); file = nil; buffer = nil; remaining = 0 }
}
