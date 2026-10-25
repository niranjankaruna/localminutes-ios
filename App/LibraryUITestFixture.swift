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
        let services = try LocalMinutesServices(rootURL: root)
        do {
            if FileManager.default.fileExists(atPath: marker.path) {
                guard try String(contentsOf: marker, encoding: .utf8) == token.uuidString else {
                    throw LibraryUIFixtureError.invalidFixture
                }
                // Reopen the same token-owned database. Never replace edits or
                // reseed a terminated app's existing fixture on a second launch.
                guard try await services.store.history(limit: 104).count == (pagination ? 103 : 2) else {
                    throw LibraryUIFixtureError.invalidFixture
                }
            } else {
                guard try await services.store.history().isEmpty else {
                    throw LibraryUIFixtureError.invalidFixture
                }
                try await seed("Alpha", in: services, at: Date(timeIntervalSince1970: 2_000))
                try await seed("Beta", in: services, at: Date(timeIntervalSince1970: 1_000))
                if pagination {
                    for index in 0..<101 {
                        try await services.store.createMeeting(.init(id: UUID(),
                            title: index == 0 ? "UI Earlier Archive Target" : "UI Archive Meeting \(index)",
                            createdAt: Date(timeIntervalSince1970: Double(index)), recordingState: .completed))
                    }
                }
                try PersistentFilePolicy.writeAtomically(Data(token.uuidString.utf8), to: marker, within: root)
            }
            return RecordingApplication(services: services)
        } catch {
            try? await services.store.close()
            throw error
        }
    }

    private static func seed(_ name: String, in services: LocalMinutesServices, at date: Date) async throws {
        let id = UUID()
        let source = UUID()
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
        if name == "Beta", ProcessInfo.processInfo.arguments.contains("--ui-test-library-content-status") {
            // Dedicated status case: audio/notes exist, while this meeting has
            // no transcript or generated summary. Original product flows retain
            // their unchanged full Alpha/Beta default fixtures.
            try await services.store.saveManualNote(.init(meetingID: id, text: "Original Beta manual note.",
                editRevision: 0, modifiedAt: date))
            return
        }
        let text = "\(name) shared-term original transcript."
        try await services.store.appendFinalizedSegments([
            .init(id: source, meetingID: id, sequence: 0, startSample: 0, endSample: 16_000,
                  text: text, modelRevision: StreamingEnglishModel.manifest.revision),
            .init(id: UUID(), meetingID: id, sequence: 1, startSample: 16_000, endSample: 32_000,
                  text: "\(name) separate-topic original transcript.", modelRevision: StreamingEnglishModel.manifest.revision)
        ], to: id)
        try await services.store.saveManualNote(.init(meetingID: id, text: "Original \(name) manual note.",
            editRevision: 0, modifiedAt: date))
        // Seed an explicitly synthetic prior result to exercise editing/citation
        // presentation without downloading, loading or pretending to run a model.
        let original = try JSONSerialization.data(withJSONObject: [
            "meeting_id": id.uuidString,
            "evidence": [["source_id": source.uuidString, "start_sample": 0,
                          "end_sample": 16_000, "quote": text]]
        ], options: [.sortedKeys])
        try await services.store.createGeneratedDocument(.init(id: UUID(), meetingID: id, kind: .summary,
            originalJSON: original, question: nil, editedText: "Seeded \(name) generated summary.",
            modelRevision: LocalMinutesServices.summaryManifest.revision, promptVersion: "synthetic-ui-fixture-v1",
            createdAt: date, modifiedAt: date))
        if name == "Beta" {
            try await services.store.createGeneratedDocument(.init(id: UUID(), meetingID: id, kind: .questionAnswer,
                originalJSON: original, question: "What is the Beta planning source?",
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
            if let application { LocalMinutesHomeView(application: application) }
            else if finished {
                Text("Library fixture unavailable.").accessibilityIdentifier("ui.fixture.library.failure")
            } else { ProgressView("Preparing library fixture…") }
        }
        .accessibilityIdentifier(LibraryUITestFixture.releaseCanary)
        .task {
            guard !finished else { return }
            defer { finished = true }
            guard let token = LibraryUITestFixture.token else { return }
            application = try? await LibraryUITestFixture.makeApplication(token: token)
        }
    }
}
#endif
