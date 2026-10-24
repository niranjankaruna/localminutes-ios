import AVFoundation
import CryptoKit
import Foundation
import SQLite3
import XCTest
import LocalMinutesCore
import LocalMinutesModels
import LocalMinutesPersistence
import LocalMinutesRecording
import LocalMinutesMeetingLibrary
@testable import LocalMinutesTranscription

/// Future MVP2 acceptance: actual reviewed Whisper bytes/audio and on-disk data.
/// There is no pin injection, inference replacement or current-default fallback.
@MainActor
final class SelectedModelRecoveryTests: XCTestCase {
    func testSchemaFiveMigrationPreservesV4OriginalsAndLeavesLegacySpeechModelPinUnknown() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-pin-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("meetings.sqlite")
        let id = UUID()
        let original = StoredTranscriptSegment(id: UUID(), meetingID: id, sequence: 0, startSample: 0,
            endSample: 16_000, text: "Original legacy transcript — preserve.", modelRevision: "legacy-original")
        let note = StoredManualNote(meetingID: id, text: "Original legacy manual note.", editRevision: 2,
            modifiedAt: Date(timeIntervalSince1970: 2_000))
        let initial = try SQLiteMeetingStore(databaseURL: database)
        try await initial.createMeeting(.init(id: id, title: "Legacy schema4 meeting", createdAt: Date(timeIntervalSince1970: 1_000),
            recordingState: .recovered, capturedSampleCount: 16_000))
        try await initial.appendFinalizedSegments([original], to: id)
        try await initial.saveManualNote(note)
        try await initial.close()
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else { throw MeetingStoreError.databaseFailure }
        // This owned fixture contains no pins. Removing the future table makes
        // a genuine fixed-v4 database even when the application later creates v5.
        let prepared = sqlite3_exec(connection, "DROP TABLE IF EXISTS meeting_speech_model_pins; PRAGMA user_version=4;", nil, nil, nil)
        sqlite3_close(connection)
        guard prepared == SQLITE_OK else { throw MeetingStoreError.databaseFailure }
        let reopened = try SQLiteMeetingStore(databaseURL: database)
        do {
            var check: OpaquePointer?
            guard sqlite3_open(database.path, &check) == SQLITE_OK, let check else { throw MeetingStoreError.databaseFailure }
            var statement: OpaquePointer?
            let compiled = sqlite3_prepare_v2(check, "PRAGMA user_version", -1, &statement, nil)
            let hasVersion = compiled == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW
            let version = hasVersion ? sqlite3_column_int(statement, 0) : -1
            sqlite3_finalize(statement); sqlite3_close(check)
            XCTAssertEqual(version, 5, "Meeting speech provenance requires an explicit durable schema5 migration")
            let rows = try await reopened.transcript(meetingID: id)
            let preservedNote = try await reopened.manualNote(meetingID: id)
            let pin = try await reopened.speechModelPin(meetingID: id)
            XCTAssertEqual(rows, [original]); XCTAssertEqual(preservedNote, note)
            XCTAssertNil(pin, "Migration must never invent a current/global model pin for a legacy recording")
            try await reopened.close()
        } catch { try? await reopened.close(); throw error }
    }

    func testActualWhisperPreparationPersistsCoherentImmutableMeetingPinBeforeFirstAudioFrame() async throws {
        let f = try await SelectedRecoveryFixture.create()
        do {
            guard case .ready(let directory) = await f.session.prepare(sessionID: f.id) else {
                XCTFail("Actual selected Whisper must prepare before pin assertions"); await f.remove(); return
            }
            let pin = try await f.store.speechModelPin(meetingID: f.id)
            XCTAssertEqual(pin, f.expectedPin)
            XCTAssertEqual(pin?.selection.profile, .whisperGGML)
            let meeting = try await f.store.meeting(id: f.id)
            XCTAssertEqual(meeting?.recordingState, .recording)
            XCTAssertEqual(meeting?.capturedSampleCount, 0)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".caf") },
                "Pin must precede audio and must not consume the empty CAF directory")
            if pin != nil {
                let conflicting = StoredMeetingSpeechModelPin(meetingID: f.id, selection: f.alternativeSelection)
                do { try await f.store.saveSpeechModelPin(conflicting); XCTFail("Capture provenance cannot be replaced by a later global Equip") }
                catch { XCTAssertEqual(error as? MeetingSpeechModelPinError, .immutableConflict) }
            }
            _ = await f.session.finish(sessionID: f.id, manifest: nil, disposition: .interrupted)
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            let persisted = try await reopened.speechModelPin(meetingID: f.id)
            XCTAssertEqual(persisted, f.expectedPin)
            try await reopened.close()
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testReopenedRecoveryUsesCapturedWhisperPinAfterGlobalEquipChangesWithoutRelabelingOriginals() async throws {
        let f = try await SelectedRecoveryFixture.create()
        do {
            try await f.captureUntranscribedAudio(prepare: true)
            let pin = try await f.store.speechModelPin(meetingID: f.id)
            XCTAssertEqual(pin, f.expectedPin)
            let selected = try await f.choices.select(manifest: f.alternative.manifest, profile: .whisperGGML, for: .speechRecognition)
            XCTAssertEqual(selected, f.alternativeSelection)
            let originalFiles = try f.sourceDigests()
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                let replay = f.replay(store: reopened)
                do {
                    let report = try await replay.replay(meetingID: f.id)
                    XCTAssertGreaterThan(report.replayedFrameCount, 0)
                } catch { XCTFail("Recovery must load this meeting's captured Whisper installation, not today's other choice: \(type(of: error))") }
                let rows = try await reopened.transcript(meetingID: f.id)
                XCTAssertEqual(rows.first, f.original)
                XCTAssertGreaterThan(rows.count, 1)
                let words = rows.dropFirst().map(\.text).joined(separator: " ").lowercased().split { !$0.isLetter }
                XCTAssertTrue(words.contains("returned")); XCTAssertTrue(words.contains("tents"))
                XCTAssertTrue(rows.dropFirst().allSatisfy { $0.modelRevision == f.installed.manifest.revision
                    && $0.startSample >= f.prefixFrames && $0.endSample <= f.totalFrames })
                let retainedPin = try await reopened.speechModelPin(meetingID: f.id)
                let global = try await f.choices.selected(for: .speechRecognition)
                let note = try await reopened.manualNote(meetingID: f.id)
                let meeting = try await reopened.meeting(id: f.id)
                XCTAssertEqual(retainedPin, f.expectedPin); XCTAssertEqual(global, f.alternativeSelection)
                XCTAssertEqual(note, f.note); XCTAssertEqual(meeting?.recordingState, .recovered)
                XCTAssertEqual(try f.sourceDigests(), originalFiles)
                XCTAssertEqual(f.admission.snapshot().phase, .idle)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testMissingMeetingPinRefusesRecoveryDespiteEquippedAlternativeAndPreservesDurableAudio() async throws {
        let f = try await SelectedRecoveryFixture.create()
        do {
            try await f.captureUntranscribedAudio(prepare: false)
            _ = try await f.choices.select(manifest: f.alternative.manifest, profile: .whisperGGML, for: .speechRecognition)
            let before = try f.sourceDigests()
            try await f.store.close()
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                do { _ = try await f.replay(store: reopened).replay(meetingID: f.id); XCTFail("A missing capture pin cannot select a global/default model") }
                catch { XCTAssertEqual(error as? MeetingSpeechModelPinError, .missingPin) }
                let rows = try await reopened.transcript(meetingID: f.id)
                let pin = try await reopened.speechModelPin(meetingID: f.id)
                XCTAssertEqual(rows, [f.original]); XCTAssertNil(pin)
                XCTAssertEqual(try f.sourceDigests(), before)
                XCTAssertEqual(f.admission.snapshot().phase, .idle)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
        } catch { await f.remove(); throw error }
        await f.remove()
    }

    func testCorruptPinAndRemovedCapturedInstallationCannotFallBackToAnEquippedWhisperAlternative() async throws {
        let f = try await SelectedRecoveryFixture.create()
        do {
            try await f.captureUntranscribedAudio(prepare: true)
            guard let legitimate = try await f.store.speechModelPin(meetingID: f.id) else {
                XCTFail("Actual capture preparation must persist its genuine pin before a corruption fixture can mutate it")
                await f.remove(); return
            }
            _ = try await f.choices.select(manifest: f.alternative.manifest, profile: .whisperGGML, for: .speechRecognition)
            let before = try f.sourceDigests()
            try await f.store.close()
            try f.replacePinJSON("{invalid pin json")
            let reopened = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                do { _ = try await f.replay(store: reopened).replay(meetingID: f.id); XCTFail("Corrupt capture metadata cannot trigger a different speech model") }
                catch { XCTAssertEqual(error as? MeetingSpeechModelPinError, .invalidPin) }
                let rows = try await reopened.transcript(meetingID: f.id)
                XCTAssertEqual(rows, [f.original]); XCTAssertEqual(try f.sourceDigests(), before)
                try await reopened.close()
            } catch { try? await reopened.close(); throw error }
            try f.replacePinJSON(String(decoding: try JSONEncoder().encode(legitimate), as: UTF8.self))
            try await f.models.remove(modelID: f.installed.manifest.modelID)
            let missing = try SQLiteMeetingStore(databaseURL: f.database)
            do {
                do { _ = try await f.replay(store: missing).replay(meetingID: f.id); XCTFail("An installed alternative is not authority to replace a missing captured model") }
                catch { XCTAssertEqual(error as? TranscriptionReplayError, .modelUnavailable) }
                let rows = try await missing.transcript(meetingID: f.id)
                let pin = try await missing.speechModelPin(meetingID: f.id)
                XCTAssertEqual(rows, [f.original]); XCTAssertEqual(pin, legitimate)
                XCTAssertEqual(try f.sourceDigests(), before)
                XCTAssertEqual(f.admission.snapshot().phase, .idle)
                try await missing.close()
            } catch { try? await missing.close(); throw error }
        } catch { await f.remove(); throw error }
        await f.remove()
    }
}

@MainActor
private final class SelectedRecoveryFixture {
    let root: URL, recordings: URL, directory: URL, database: URL
    let id = UUID()
    let store: SQLiteMeetingStore, models: ModelInstallationManager
    let installed: VerifiedModel, alternative: VerifiedModel
    let session: LiveTranscriptionSession
    let choices: ModelSelectionStore
    let usage = MeetingUsageRegistry(), admission = HeavyModelAdmission()
    let samples: [Float]
    let prefixFrames: Int64 = 16_000
    var totalFrames: Int64 { prefixFrames + Int64(samples.count) + 48_000 }
    var expectedPin: StoredMeetingSpeechModelPin {
        .init(meetingID: id, selection: .init(manifest: installed.manifest, profile: .whisperGGML, installationID: installed.installationID))
    }
    var alternativeSelection: StoredModelSelection {
        .init(manifest: alternative.manifest, profile: .whisperGGML, installationID: alternative.installationID)
    }
    var original: StoredTranscriptSegment {
        .init(id: UUID(uuidString: "77777777-0000-0000-0000-000000000001")!, meetingID: id, sequence: 0,
            startSample: 0, endSample: prefixFrames, text: "Original synthetic prefix, never ASR output.", modelRevision: "original-prefix")
    }
    var note: StoredManualNote {
        .init(meetingID: id, text: "Original selected-model recovery note — Café.", editRevision: 3, modifiedAt: Date(timeIntervalSince1970: 2_000))
    }

    private init(root: URL, models: ModelInstallationManager, store: SQLiteMeetingStore,
                 installed: VerifiedModel, alternative: VerifiedModel, samples: [Float]) {
        self.root = root; self.models = models; self.store = store
        self.installed = installed; self.alternative = alternative; self.samples = samples
        recordings = root.appendingPathComponent("Meetings", isDirectory: true)
        database = root.appendingPathComponent("meetings.sqlite")
        directory = recordings.appendingPathComponent(id.uuidString, isDirectory: true)
        session = LiveTranscriptionSession(models: models, store: store, meetingsDirectory: recordings,
            selectedSpeechModel: { installed.manifest })
        choices = ModelSelectionStore(rootURL: root.appendingPathComponent("Choices"), models: models,
            availableProfiles: [.whisperGGML], canChangeSelection: { true })
    }

    static func create() async throws -> SelectedRecoveryFixture {
        let environment = ProcessInfo.processInfo.environment
        let model = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_WHISPER_MODEL_PATH"]))
        let audioURL = URL(fileURLWithPath: try XCTUnwrap(environment["LOCALMINUTES_WHISPER_FIXTURE_PATH"]))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("localminutes-selected-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var store: SQLiteMeetingStore?
        do {
            let audioData = try Data(contentsOf: audioURL)
            XCTAssertEqual(audioData.count, 74_138)
            let digest = SHA256.hash(data: audioData).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23")
            guard audioData.count == 74_138, digest == "9ce35224156f071ab58eb7feb8a5ceae600f6f9f353da2a6cbf797b6b1ac8a23" else {
                throw StreamingASRError.invalidSamples
            }
            // Existing LibriSpeech6930-75918-0000, CC-BY-4.0; Panayotov/Povey,
            // LibriVox source. No new audio or network fixture is introduced.
            let audio = try AVAudioFile(forReading: audioURL, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard audio.processingFormat.sampleRate == 16_000, audio.processingFormat.channelCount == 1,
                  audio.length > 0, audio.length <= 480_000,
                  let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else {
                throw StreamingASRError.invalidSamples
            }
            try audio.read(into: buffer)
            XCTAssertEqual(Int64(buffer.frameLength), audio.length)
            let samples = Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData?.pointee), count: Int(buffer.frameLength)))
            let source = root.appendingPathComponent("Import")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            try FileManager.default.copyItem(at: model, to: source.appendingPathComponent("ggml-tiny.en.bin"))
            let models = ModelInstallationManager(rootURL: root.appendingPathComponent("Models"), availableBytes: { _ in .max })
            let installed = try await models.importDirectory(source, manifest: manifest(modelID: "capture-whisper-tiny-en"))
            let alternative = try await models.importDirectory(source, manifest: manifest(modelID: "other-equipped-whisper-tiny-en"))
            let opened = try SQLiteMeetingStore(databaseURL: root.appendingPathComponent("meetings.sqlite"))
            store = opened
            return .init(root: root, models: models, store: opened, installed: installed, alternative: alternative, samples: samples)
        } catch { try? await store?.close(); try? FileManager.default.removeItem(at: root); throw error }
    }

    private static func manifest(modelID: String) -> ModelManifest {
        let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
        let repository = "https://huggingface.co/ggerganov/whisper.cpp"
        return .init(modelID: modelID, purpose: .speechRecognition, upstreamRepository: URL(string: repository)!,
            revision: revision, licenseIdentifier: "MIT", licenseNotice: "OpenAI Whisper, MIT; GGML conversion whisper.cpp. https://github.com/openai/whisper/blob/main/LICENSE",
            runtimeVersion: "whisper.cpp-1.7.5", sampleRate: 16_000,
            artifacts: [.init(role: .whisper, fileName: "ggml-tiny.en.bin", byteCount: 77_704_715,
                sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
                downloadURL: URL(string: repository + "/resolve/" + revision + "/ggml-tiny.en.bin")!,
                digestProvenance: .independentlyDownloaded)])
    }

    func captureUntranscribedAudio(prepare: Bool) async throws {
        if prepare {
            guard case .ready = await session.prepare(sessionID: id) else { throw StreamingASRError.invalidModel }
        } else {
            try await store.createMeeting(.init(id: id, title: "Legacy meeting without model pin", createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .recovered))
        }
        let writer = try SegmentCAFWriter(directory: directory, sessionID: id, maximumSegmentFrames: 16_000)
        let all = [Float](repeating: 0, count: Int(prefixFrames)) + samples + [Float](repeating: 0, count: 48_000)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        for offset in stride(from: 0, to: all.count, by: 3_200) {
            let count = min(3_200, all.count - offset)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            let target = try XCTUnwrap(buffer.floatChannelData?.pointee)
            for index in 0..<count { target[index] = all[offset + index] }
            try writer.append(buffer)
        }
        let manifest = try writer.finish()
        XCTAssertEqual(manifest.totalFrames, totalFrames)
        // Simulate durable-file publication before ASR ingress at termination.
        // No audio is offered to the live recognizer or fake transcript supplied.
        if prepare { _ = await session.finish(sessionID: id, manifest: nil, disposition: .interrupted) }
        try await store.appendFinalizedSegments([original], to: id)
        try await store.saveManualNote(note)
        try await store.updateRecordingState(id: id, state: .recovered, capturedSampleCount: totalFrames)
    }
    func replay(store: SQLiteMeetingStore) -> MeetingTranscriptionReplayCoordinator {
        .init(store: store, models: models, recordingsRoot: recordings, usage: usage, admission: admission,
            modelPolicy: .capturedPinRequired)
    }
    func sourceDigests() throws -> [String: String] {
        var result: [String: String] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "caf" || url.lastPathComponent == "capture-manifest.json" {
            result[url.lastPathComponent] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
    func replacePinJSON(_ value: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open(database.path, &connection) == SQLITE_OK, let connection else { throw MeetingStoreError.databaseFailure }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, "UPDATE meeting_speech_model_pins SET selection_json=? WHERE meeting_id=?", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw MeetingStoreError.databaseFailure }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let boundValue = value.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        let boundID = id.uuidString.withCString { sqlite3_bind_text(statement, 2, $0, -1, transient) }
        guard boundValue == SQLITE_OK, boundID == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE,
              sqlite3_changes(connection) == 1 else { throw MeetingStoreError.databaseFailure }
    }
    func remove() async {
        if session.transcript.sessionID == id { _ = await session.finish(sessionID: id, manifest: nil, disposition: .interrupted) }
        try? await store.close()
        guard root.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              root.lastPathComponent.hasPrefix("localminutes-selected-recovery-"), root.resolvingSymlinksInPath() == root else {
            return XCTFail("Unsafe selected recovery fixture cleanup")
        }
        try? FileManager.default.removeItem(at: root)
    }
}
