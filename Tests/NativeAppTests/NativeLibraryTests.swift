#if os(iOS)
import CryptoKit
import AVFoundation
import Darwin
import Synchronization
import Foundation
import XCTest
@testable import LocalMinutes

/// Actual app services/SQLite/CAF/archive paths; no microphone permission or
/// hardware capture is requested by a library replacement test.
@MainActor
final class NativeLibraryTests: XCTestCase {
    func testDefaultAppManagerResumesPinnedDownloadThroughItsConfiguredTransportAndPublishesVerifiedInstallation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeResumeURLProtocol.self]
        try await withFixture(configuration: configuration) { f in
            let manifest = f.integrityManifest()
            let artifact = try XCTUnwrap(manifest.artifacts.first)
            let prefix = Data(f.modelBytes.prefix(8))
            let factory = ModelTransferFactory(appRootURL: f.root, configuration: configuration)
            let progress = try factory.checkpointDirectory(for: artifact)
            try FileManager.default.createDirectory(at: progress, withIntermediateDirectories: true)
            try PersistentFilePolicy.protectDirectory(progress)
            try PersistentFilePolicy.writeAtomically(prefix, to: progress.appendingPathComponent("partial.bin"), within: progress)
            let checkpoint = ModelDownloadCheckpoint(downloadURL: artifact.downloadURL, revision: manifest.revision,
                fileName: artifact.fileName, expectedByteCount: artifact.byteCount, sha256: artifact.sha256,
                strongETag: "\"native-fixture\"", receivedByteCount: Int64(prefix.count),
                partialSHA256: SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined())
            try PersistentFilePolicy.writeAtomically(try JSONEncoder().encode(checkpoint),
                to: progress.appendingPathComponent("checkpoint.json"), within: progress)
            NativeResumeURLProtocol.prepare(bytes: f.modelBytes, offset: prefix.count)
            defer { NativeResumeURLProtocol.clear() }
            let transfer = Task { try await f.services.models.download(manifest) }
            // A missing native download completion is a failure, not permission
            // to leave this focused app job waiting until its overall timeout.
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(8)) }
                catch { return }
                transfer.cancel()
            }
            defer { deadline.cancel() }
            do {
                let installed = try await transfer.value
                XCTAssertEqual(installed.manifest, manifest)
                XCTAssertEqual(try Data(contentsOf: installed.files[.summary]!), f.modelBytes)
            } catch { XCTFail("The actual app manager must resume its pinned partial download: \(type(of: error))") }
            let headers = NativeResumeURLProtocol.headers()
            XCTAssertEqual(headers.count, 1)
            XCTAssertEqual(headers.first?.0, "bytes=8-")
            XCTAssertEqual(headers.first?.1, "\"native-fixture\"")
            let published = try await f.services.models.current(modelID: manifest.modelID)
            XCTAssertNotNil(published, "A separate unused factory cannot establish app download integration")
        }
    }

    func testAppSceneSamplingUsesActualResidentMemoryAndOneRetainedPrivateEnduranceRecorder() async throws {
        try await withFixture { f in
            var info = mach_task_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            guard status == KERN_SUCCESS, info.resident_size > 0 else {
                XCTFail("Native task_info setup must return an actual current-process measurement"); return
            }
            let facts = NativeEnduranceFacts.current(visibility: .foreground)
            let measured = try XCTUnwrap(facts.residentMemoryBytes, "OS measurement is required on this supported native host")
            XCTAssertGreaterThan(measured, 0)
            XCTAssertLessThanOrEqual(abs(measured - Int64(clamping: info.resident_size)), 128 * 1_024 * 1_024)
            let recorder = try XCTUnwrap(f.services.endurance, "Default services must retain the app's actual sampler")
            let before = recorder.snapshot().totalSampleCount
            try f.application.recordScenePhase(.active)
            let after = recorder.snapshot()
            XCTAssertEqual(after.totalSampleCount, before + 1)
            XCTAssertEqual(after.samples.last?.facts.visibility, .foreground)
            XCTAssertGreaterThan(after.samples.last?.facts.residentMemoryBytes ?? 0, 0)
            XCTAssertEqual(after.transcription.identity, f.services.metrics?.snapshot().identity)
            let exported = try EnduranceMetricsExportCodec.encode(after)
            XCTAssertEqual(try EnduranceMetricsExportCodec.decodeValidated(exported), after)
            let text = String(decoding: exported, as: UTF8.self)
            XCTAssertFalse(text.contains(f.root.path)); XCTAssertFalse(text.contains("deviceLocked"))
            XCTAssertFalse(text.contains("transcript" + "Text"))
        }
    }

    func testDefaultServicesOpenSelectedGenerationAndKeepOuterModelStorageAndSelection() async throws {
        try await withFixture { f in
            let old = try await f.seedCurrent()
            let generation = UUID()
            let root = f.root.appendingPathComponent("LibraryGenerations/" + generation.uuidString)
            let incoming = try await f.closedLibrary(at: root, title: "Restored selected generation")
            let model = try await f.installIntegrityFixture()
            let pointer = try JSONEncoder().encode(ActiveLibrarySelection(generationID: generation))
            try PersistentFilePolicy.writeAtomically(pointer,
                to: f.root.appendingPathComponent("activeLibrary.json"), within: f.root)
            let reopened = try LocalMinutesServices(rootURL: f.root)
            f.stores.append(reopened.store)
            let rows = try await reopened.store.history()
            XCTAssertEqual(rows.map(\.id), [incoming])
            XCTAssertFalse(rows.contains { $0.id == old }, "Current library is the committed UUID generation")
            let original = try await f.services.store.meeting(id: old)
            XCTAssertNotNil(original, "Selection never rewrites the old database")
            let kept = try await reopened.models.current(modelID: model.manifest.modelID)
            XCTAssertEqual(kept?.installationID, model.installationID)
            let selection = try await reopened.modelSelections.selected(for: .summary)
            XCTAssertEqual(selection?.manifest, model.manifest)
            XCTAssertEqual(selection?.installationID, model.installationID)
            XCTAssertEqual(try Data(contentsOf: model.files[.summary]!), f.modelBytes)
        }
    }

    func testRestoringClosedBackupRebindsAppServicesAndOwnerWhilePreservingPreviousLibraryAndModels() async throws {
        try await withFixture { f in
            let oldID = try await f.seedCurrent()
            let model = try await f.installIntegrityFixture()
            let source = f.root.appendingPathComponent("InputSnapshot", isDirectory: true)
            let restoredID = try await f.closedLibrary(at: source, title: "Incoming backup library")
            let archive = f.root.appendingPathComponent("incoming.localminutesbackup", isDirectory: true)
            _ = try MeetingArchive.export(snapshotRoot: source, to: archive)
            let oldOwner = try XCTUnwrap(f.application.owner)
            do { try await f.application.restoreLibrary(from: archive) }
            catch { XCTFail("Actual application restore must complete: \(type(of: error))"); return }
            let current = try XCTUnwrap(f.application.services)
            f.stores.append(current.store)
            XCTAssertFalse(current === f.services)
            XCTAssertFalse(f.application.owner === oldOwner)
            let active = try LibraryArchiveCoordinator.activeLibraryRoot(at: f.root)
            XCTAssertNotEqual(active, f.root)
            let rows = try await current.store.history()
            XCTAssertEqual(rows.map(\.id), [restoredID])
            let note = try await current.store.manualNote(meetingID: restoredID)
            XCTAssertEqual(note?.text, "Original café note — preserved 📝")
            let transcript = try await current.store.transcript(meetingID: restoredID)
            XCTAssertEqual(transcript.map(\.text), ["Original archived synthetic transcript."])
            let oldStore = try SQLiteMeetingStore(databaseURL: f.root.appendingPathComponent("meetings.sqlite"))
            f.stores.append(oldStore)
            let original = try await oldStore.meeting(id: oldID)
            XCTAssertNotNil(original, "A validated restore retains the previous library for rollback")
            let kept = try await current.models.current(modelID: model.manifest.modelID)
            XCTAssertEqual(kept?.installationID, model.installationID)
            XCTAssertEqual(try Data(contentsOf: model.files[.summary]!), f.modelBytes)
            XCTAssertEqual(current.heavyAdmission?.snapshot().phase, .idle)
            await current.initialize()
            XCTAssertEqual(current.startup.state, .ready)
            let outcome = try await f.application.perform(.stop(expectedSessionID: nil))
            XCTAssertEqual(outcome, .idle)
        }
    }

    func testRestoreRefusesSharedRecordingAdmissionBeforeClosingOrReplacingCurrentData() async throws {
        try await withFixture { f in
            let originalID = try await f.seedCurrent()
            await f.services.initialize()
            let source = f.root.appendingPathComponent("BusyInputSnapshot", isDirectory: true)
            _ = try await f.closedLibrary(at: source, title: "Must not activate while recording")
            let archive = f.root.appendingPathComponent("busy.localminutesbackup", isDirectory: true)
            _ = try MeetingArchive.export(snapshotRoot: source, to: archive)
            let lease = try f.services.usage.beginRecording(meetingID: originalID)
            defer { f.services.usage.endRecording(lease) }
            do { try await f.application.restoreLibrary(from: archive); XCTFail("An admitted recording excludes restore") }
            catch { XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .busy) }
            XCTAssertTrue(f.application.services === f.services)
            let rows = try await f.services.store.history()
            XCTAssertEqual(rows.map(\.id), [originalID], "Refusal leaves the actual existing store open")
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("activeLibrary.json").path))
        }
    }

    func testInvalidSelectedGenerationFailsWithoutFallingBackToOrRewritingLegacyData() async throws {
        try await withFixture { f in
            let original = try await f.seedCurrent()
            let bytes = Data(#"{"schemaVersion":1,"generationID":"../../Models"}"#.utf8)
            try PersistentFilePolicy.writeAtomically(bytes,
                to: f.root.appendingPathComponent("activeLibrary.json"), within: f.root)
            do {
                let opened = try LocalMinutesServices(rootURL: f.root)
                f.stores.append(opened.store)
                XCTFail("An invalid active pointer cannot silently reopen the legacy library")
            } catch { XCTAssertEqual(error as? LibraryArchiveCoordinatorError, .invalidActivePointer) }
            let retained = try await f.services.store.meeting(id: original)
            XCTAssertNotNil(retained)
            XCTAssertEqual(try Data(contentsOf: f.root.appendingPathComponent("activeLibrary.json")), bytes)
        }
    }

    func testAppDeleteMeetingRemovesAudioTranscriptNotesSummaryAnswersAndPendingCacheAndRefreshesSelection() async throws {
        try await withFixture { f in
            let id = try await f.closedLibrary(at: f.root, title: "Delete this meeting")
            let other = try await f.seedCurrent()
            let model = try await f.installIntegrityFixture()
            let summaryID = UUID()
            for (documentID, kind, question) in [
                (summaryID, GeneratedDocumentKind.summary, Optional<String>.none),
                (UUID(), GeneratedDocumentKind.questionAnswer, Optional("Who owns the guide?"))
            ] {
                try await f.services.store.createGeneratedDocument(.init(id: documentID,
                    meetingID: id, kind: kind, originalJSON: Data(#"{"fixture":"generated meeting material"}"#.utf8),
                    question: question, editedText: "Generated meeting material", modelRevision: "fixture-revision",
                    promptVersion: "fixture-prompt", createdAt: Date(timeIntervalSince1970: 2_000),
                    modifiedAt: Date(timeIntervalSince1970: 2_000)))
            }
            _ = try await f.services.store.saveGeneratedDocumentEdit(id: summaryID, meetingID: id,
                text: "Edited summary private to this meeting", expectedRevision: 0,
                modifiedAt: Date(timeIntervalSince1970: 2_001))
            let cache = f.root.appendingPathComponent("SummaryCheckpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let partial = cache.appendingPathComponent(id.uuidString + ".json")
            // Even a corrupt owned checkpoint may contain raw quoted text and
            // must not be left behind or prevent this meeting's deletion.
            try Data("corrupt unfinished map with private quote".utf8).write(to: partial)
            await f.services.initialize()
            await f.services.library.open(id: id)
            let deleted = await f.services.deleteMeeting(id: id)
            XCTAssertTrue(deleted, "The actual app service must delete the complete meeting")
            let meeting = try await f.services.store.meeting(id: id)
            let transcript = try await f.services.store.transcript(meetingID: id)
            let note = try await f.services.store.manualNote(meetingID: id)
            let documents = try await f.services.store.generatedDocuments(meetingID: id)
            let matches = try await f.services.store.searchTranscript(meetingID: id, query: "archived")
            XCTAssertNil(meeting); XCTAssertTrue(transcript.isEmpty); XCTAssertNil(note)
            XCTAssertTrue(documents.isEmpty); XCTAssertTrue(matches.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.services.meetingsDirectory.appendingPathComponent(id.uuidString).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
            XCTAssertNil(f.services.library.selected)
            let history = try await f.services.store.history()
            XCTAssertEqual(history.map(\.id), [other])
            let keptModel = try await f.services.models.current(modelID: model.manifest.modelID)
            XCTAssertEqual(keptModel?.installationID, model.installationID)
        }
    }

    private func withFixture(configuration: URLSessionConfiguration = .ephemeral,
                             _ body: @MainActor (NativeLibraryFixture) async throws -> Void) async throws {
        let fixture = try NativeLibraryFixture(configuration: configuration)
        do { try await body(fixture) }
        catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
    }
}

@MainActor
private final class NativeLibraryFixture {
    let parent: URL
    let root: URL
    let services: LocalMinutesServices
    let application: RecordingApplication
    var stores: [SQLiteMeetingStore] = []
    let modelBytes = Data("GGUFsynthetic integrity-only payload; never loaded for inference".utf8)

    init(configuration: URLSessionConfiguration = .ephemeral) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        parent = support.appendingPathComponent("LocalMinutesNativeLibraryTests", isDirectory: true)
        root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        services = try LocalMinutesServices(rootURL: root, modelConfiguration: configuration)
        application = RecordingApplication(services: services)
        stores = [services.store]
    }

    func seedCurrent() async throws -> UUID {
        let id = UUID()
        try await services.store.createMeeting(.init(id: id, title: "Previous original library",
            createdAt: Date(timeIntervalSince1970: 1_000), recordingState: .completed))
        return id
    }

    func closedLibrary(at directory: URL, title: String) async throws -> UUID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try SQLiteMeetingStore(databaseURL: directory.appendingPathComponent("meetings.sqlite"))
        let id = UUID()
        do {
            let meeting = directory.appendingPathComponent("Meetings/" + id.uuidString, isDirectory: true)
            let writer = try SegmentCAFWriter(directory: meeting, sessionID: id, maximumSegmentFrames: 16_000)
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000, channels: 1, interleaved: false))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
            buffer.frameLength = 320
            let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
            for index in 0..<320 { samples[index] = 0.125 }
            try writer.append(buffer)
            _ = try writer.finish()
            try await store.createMeeting(.init(id: id, title: title,
                createdAt: Date(timeIntervalSince1970: 2_000), recordingState: .completed, capturedSampleCount: 320))
            try await store.appendFinalizedSegments([.init(id: UUID(), meetingID: id, sequence: 0,
                startSample: 0, endSample: 320, text: "Original archived synthetic transcript.",
                modelRevision: StreamingEnglishModel.manifest.revision)], to: id)
            try await store.saveManualNote(.init(meetingID: id, text: "Original café note — preserved 📝",
                editRevision: 2, modifiedAt: Date(timeIntervalSince1970: 2_000)))
            try await store.close()
            return id
        } catch { try? await store.close(); throw error }
    }

    func installIntegrityFixture() async throws -> VerifiedModel {
        let source = root.appendingPathComponent("IntegrityModelInput", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try modelBytes.write(to: source.appendingPathComponent("integrity.gguf"))
        let manifest = integrityManifest()
        let model = try await services.models.importDirectory(source, manifest: manifest)
        _ = try await services.modelSelections.select(manifest: manifest, profile: .llamaGGUF, for: .summary)
        return model
    }

    func integrityManifest() -> ModelManifest {
        let revision = String(repeating: "b", count: 40)
        let digest = SHA256.hash(data: modelBytes).map { String(format: "%02x", $0) }.joined()
        return ModelManifest(modelID: "native-restore-integrity-fixture", purpose: .summary,
            upstreamRepository: URL(string: "https://huggingface.co/example/integrity-fixture")!, revision: revision,
            licenseIdentifier: "MIT", licenseNotice: "Synthetic storage fixture, not an inference model.",
            runtimeVersion: "llama.cpp-b5046", artifacts: [.init(role: .summary, fileName: "integrity.gguf",
                byteCount: Int64(modelBytes.count), sha256: digest,
                downloadURL: URL(string: "https://huggingface.co/example/integrity-fixture/resolve/\(revision)/integrity.gguf")!,
                digestProvenance: .upstreamReported)])
    }

    func cleanup() async {
        if let snapshot = await application.owner?.snapshot(), snapshot.cleanupPending || snapshot.readiness.audioSessionActive {
            XCTFail("Unexpected recording resources; keep fixture for cleanup"); return
        }
        if let current = application.services { stores.append(current.store) }
        for store in stores { try? await store.close() }
        guard root.deletingLastPathComponent() == parent,
              parent.lastPathComponent == "LocalMinutesNativeLibraryTests",
              UUID(uuidString: root.lastPathComponent) != nil,
              root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside owned native fixture"); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Owned native fixture cleanup failed") }
    }
}

private final class NativeResumeURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State: Sendable {
        let bytes: Data
        let offset: Int
        var requests: [(String?, String?)] = []
    }
    private static let state = Mutex<State?>(nil)
    static func prepare(bytes: Data, offset: Int) { state.withLock { $0 = State(bytes: bytes, offset: offset) } }
    static func clear() { state.withLock { $0 = nil } }
    static func headers() -> [(String?, String?)] { state.withLock { $0?.requests ?? [] } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.state.withLock { value -> (Data, Int, Int)? in
            guard var next = value else { return nil }
            next.requests.append((request.value(forHTTPHeaderField: "Range"), request.value(forHTTPHeaderField: "If-Range")))
            value = next
            return (Data(next.bytes.dropFirst(next.offset)), next.offset, next.bytes.count)
        }
        guard let (body, offset, total) = response, let url = request.url,
              let header = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(body.count), "Content-Range": "bytes \(offset)-\(total - 1)/\(total)",
                               "ETag": "\"native-fixture\""]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: header, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
