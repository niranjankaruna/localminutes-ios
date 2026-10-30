#if DEBUG && os(iOS)
import AVFoundation
import Foundation
import SwiftUI

/// Harness bootstrap only: persisted synthetic SQLite/CAF/generated fixtures,
/// not inference output. The entire hook is excluded from compiled Release.
@MainActor
enum LibraryUITestFixture {
    static let releaseCanary = "LOCALMINUTES_DEBUG_LIBRARY_FIXTURE_CANARY_v1"
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-library-fixture")
    }
    static var token: UUID? {
        guard let value = ProcessInfo.processInfo.environment["LOCALMINUTES_UI_LIBRARY_TOKEN"] else { return nil }
        return UUID(uuidString: value)
    }

    static func makeApplication(token: UUID) async throws -> RecordingApplication? {
        let parent = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent("LocalMinutesLibraryUIFixtures", isDirectory: true)
        let root = parent.appendingPathComponent(token.uuidString, isDirectory: true)
        let marker = root.appendingPathComponent("fixture-seeded.txt")
        let pagination = ProcessInfo.processInfo.arguments.contains("--ui-test-library-pagination")
        let empty = ProcessInfo.processInfo.arguments.contains("--ui-test-library-empty")
            || AppScreenshotFixture.scene == .meetingsEmpty
            || AppScreenshotFixture.scene == .meetingsLoading || AppScreenshotFixture.scene == .meetingsFailure
        let services = try LocalMinutesServices(rootURL: root)
        do {
            if FileManager.default.fileExists(atPath: marker.path) {
                guard try String(contentsOf: marker, encoding: .utf8) == token.uuidString else {
                    throw LibraryUIFixtureError.invalidFixture
                }
                // Reopen the same token-owned database. Never replace edits or
                // reseed a terminated app's existing fixture on a second launch.
                guard try await services.store.history(limit: 104).count == (empty ? 0 : pagination ? 103 : 2) else {
                    throw LibraryUIFixtureError.invalidFixture
                }
            } else {
                guard try await services.store.history().isEmpty else {
                    throw LibraryUIFixtureError.invalidFixture
                }
                if !empty {
                    try await seed("Alpha", in: services, at: Date(timeIntervalSince1970: 2_000))
                    try await seed("Beta", in: services, at: Date(timeIntervalSince1970: 1_000))
                }
                if pagination && !empty {
                    for index in 0..<101 {
                        try await services.store.createMeeting(.init(id: UUID(),
                            title: index == 0 ? "UI Earlier Archive Target" : "UI Archive Meeting \(index)",
                            createdAt: Date(timeIntervalSince1970: Double(index)), recordingState: .completed))
                    }
                }
                try PersistentFilePolicy.writeAtomically(Data(token.uuidString.utf8), to: marker, within: root)
            }
            let application = RecordingApplication(services: services)
            if ProcessInfo.processInfo.arguments.contains("--ui-test-last-meeting-shortcut")
                || ProcessInfo.processInfo.arguments.contains("--ui-test-meetings-shortcut") {
                _ = try await OpenLatestMeetingIntent(application: application).perform()
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-meetings-shortcut") {
                _ = try await OpenMeetingsIntent(application: application).perform()
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-test-recording-shortcut") {
                // Exercise a cold navigation intent before the root exists.
                _ = try await OpenRecordingIntent(application: application).perform()
            }
            return application
        } catch {
            try? await services.store.close()
            throw error
        }
    }

    private static func seed(_ name: String, in services: LocalMinutesServices, at date: Date) async throws {
        let id = AppScreenshotFixture.requested
            ? (name == "Alpha" ? AppScreenshotFixture.meetingID : AppScreenshotFixture.detailMeetingID) : UUID()
        let source = AppScreenshotFixture.requested
            ? UUID(uuidString: name == "Alpha" ? "20000000-0000-0000-0000-000000000001" : "20000000-0000-0000-0000-000000000002")!
            : UUID()
        let audioDirectory = services.meetingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: false)
        let writer = try SegmentCAFWriter(directory: audioDirectory, sessionID: id, maximumSegmentFrames: 16_000)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000),
              let samples = pcm.floatChannelData?.pointee else { throw LibraryUIFixtureError.invalidFixture }
        pcm.frameLength = 32_000
        samples.update(repeating: 0.125, count: 32_000)
        try writer.append(pcm)
        let manifest = try writer.finish()
        guard manifest.totalFrames == 32_000 else { throw LibraryUIFixtureError.invalidFixture }
        try await services.store.createMeeting(.init(id: id, title: "UI Library \(name)", createdAt: date,
            recordingState: .completed, capturedSampleCount: manifest.totalFrames))
        if name == "Beta", ProcessInfo.processInfo.arguments.contains("--ui-test-library-content-status")
            || AppScreenshotFixture.scene?.isEmptyMeeting == true {
            // Dedicated status case: audio/notes exist, while this meeting has
            // no transcript or generated summary. Original product flows retain
            // their unchanged full Alpha/Beta default fixtures.
            try await services.store.saveManualNote(.init(meetingID: id, text: "Original Beta manual note.",
                editRevision: 0, modifiedAt: date))
            return
        }
        let structured = AppScreenshotFixture.scene == .meetingSummaryStructured && name == "Beta"
        let text = structured ? "We agreed to review the updated meeting experience on Friday." : "\(name) shared-term original transcript."
        try await services.store.appendFinalizedSegments([
            .init(id: source, meetingID: id, sequence: 0, startSample: 0, endSample: 16_000,
                  text: text, modelRevision: ParakeetCoreMLModel.manifest.revision),
            .init(id: UUID(), meetingID: id, sequence: 1, startSample: 16_000, endSample: 32_000,
                  text: "\(name) separate-topic original transcript.", modelRevision: ParakeetCoreMLModel.manifest.revision)
        ], to: id)
        try await services.store.saveManualNote(.init(meetingID: id,
            text: AppScreenshotFixture.scene == .meetingNotesEmpty && name == "Beta" ? "" : "Original \(name) manual note.",
            editRevision: 0, modifiedAt: date))
        // Seed an explicitly synthetic prior result to exercise editing/citation
        // presentation without downloading, loading or pretending to run a model.
        var original = try JSONSerialization.data(withJSONObject: [
            "meeting_id": id.uuidString,
            "evidence": [["source_id": source.uuidString, "start_sample": 0,
                          "end_sample": 16_000, "quote": text]]
        ], options: [.sortedKeys])
        let answerOriginal = original
        if structured {
            let evidence: [[String: Any]] = [["source_id": source.uuidString, "start_sample": 0, "end_sample": 16_000, "quote": text]]
            original = try JSONSerialization.data(withJSONObject: [
                "schema_version": 2, "meeting_id": id.uuidString,
                "overview": ["text": "The team agreed on the next review.", "evidence": evidence],
                "bullets": [["text": "Review the updated meeting experience on Friday.", "evidence": evidence]]
            ])
        }
        let summaryID = UUID()
        try await services.store.createGeneratedDocument(.init(id: summaryID, meetingID: id, kind: .summary,
            originalJSON: original, question: nil, editedText: structured ? "The team agreed on the next review." : "Seeded \(name) generated summary.",
            modelRevision: LocalMinutesServices.summaryManifest.revision, promptVersion: "synthetic-ui-fixture-v1",
            createdAt: date, modifiedAt: date))
        if AppScreenshotFixture.scene == .meetingSummaryEdited && name == "Beta" {
            _ = try await services.store.saveGeneratedDocumentEdit(id: summaryID, meetingID: id,
                text: "Reviewed summary: the team will review the updated meeting experience on Friday.",
                expectedRevision: 0, modifiedAt: date)
        }
        if name == "Beta" {
            let answerID = AppScreenshotFixture.requested ? UUID(uuidString: "30000000-0000-0000-0000-000000000002")! : UUID()
            try await services.store.createGeneratedDocument(.init(id: answerID, meetingID: id, kind: .questionAnswer,
                originalJSON: answerOriginal, question: "What is the Beta planning source?",
                editedText: "Seeded Beta private answer.", modelRevision: LocalMinutesServices.summaryManifest.revision,
                promptVersion: "synthetic-ui-fixture-v1", createdAt: date, modifiedAt: date))
        }
    }
}

private enum LibraryUIFixtureError: Error { case invalidFixture }

@MainActor
struct LibraryUITestFixtureRoot: View {
    @State private var application: RecordingApplication?
    @State private var finished = false
    var body: some View {
        Group {
            if let application {
                if AppScreenshotFixture.scene?.isLaunch == true {
                    ScreenshotLaunchView().screenshotReady(true)
                } else if AppScreenshotFixture.scene?.isActivity == true {
                    RecordingActivityTestScreen(application: application,
                        finished: AppScreenshotFixture.scene == .activityFinished)
                        .dynamicTypeSize(.large).screenshotReady(true)
                } else if ProcessInfo.processInfo.environment["LOCALMINUTES_UI_LIBRARY_AX5"] == "1" {
                    LocalMinutesHomeView(application: application).dynamicTypeSize(.accessibility5)
                } else {
                    if AppScreenshotFixture.requested {
                        LocalMinutesHomeView(application: application).dynamicTypeSize(.large).screenshotReady(true)
                    } else {
                        LocalMinutesHomeView(application: application)
                    }
                }
            }
            else if finished {
                Text("Library fixture unavailable.").accessibilityIdentifier("ui.fixture.library.failure")
            } else { ProgressView("Preparing library fixture…") }
        }
        .accessibilityIdentifier(LibraryUITestFixture.releaseCanary)
        .preferredColorScheme(AppScreenshotFixture.colorScheme)
        .task {
            guard !finished else { return }
            defer { finished = true }
            guard let token = LibraryUITestFixture.token else { return }
            do {
                let prepared = try await LibraryUITestFixture.makeApplication(token: token)
                if let prepared { try await AppScreenshotFixture.prepare(prepared) }
                application = prepared
            } catch { application = nil }
        }
    }
}
#endif
