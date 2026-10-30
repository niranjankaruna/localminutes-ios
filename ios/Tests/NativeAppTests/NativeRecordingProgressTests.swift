#if os(iOS)
import Foundation
import XCTest
@testable import LocalMinutes

/// Actual app-retained metric origin/counters composed with a domain-state
/// fixture. Injected source counts establish no microphone, ASR or phone pass.
@MainActor
final class NativeRecordingProgressTests: XCTestCase {
    func testPresenterUsesActualDefaultServiceFirstPCMOriginAndMeasuredPendingSamples() async throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
        let parent = support.appendingPathComponent("LocalMinutesNativeProgressTests", isDirectory: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let services = try LocalMinutesServices(rootURL: root)
        do {
            let metrics = try XCTUnwrap(services.metrics)
            metrics.beginEpoch()
            XCTAssertNil(metrics.firstAudioQueuedAtNanoseconds)
            try metrics.audioQueued(startSample: 0, frameCount: 320, queueDepth: 1)
            try metrics.processed(startSample: 0, frameCount: 320, workStartedAtNanoseconds: metrics.nowNanoseconds())
            try metrics.audioQueued(startSample: 320, frameCount: 320, queueDepth: 1)
            let origin = try XCTUnwrap(metrics.firstAudioQueuedAtNanoseconds)
            let recording = RecordingSnapshot(phase: .recording, sessionID: UUID(),
                readiness: .init(audioSessionActive: true, firstBufferAccepted: true, activityActive: true),
                failure: nil, cleanupPending: false)
            let progress = RecordingProgressPresenter.make(recording: recording,
                firstAudioQueuedAtNanoseconds: origin, observedAtNanoseconds: origin + 2_400_000_000,
                metrics: metrics.snapshot())
            XCTAssertEqual(progress.elapsedSeconds, 2)
            XCTAssertEqual(progress.backlogSeconds, 0.02)
            XCTAssertEqual(progress.status, .processing)
            XCTAssertEqual(metrics.firstAudioQueuedAtNanoseconds, origin, "A display projection never resets recording metrics")
            XCTAssertEqual(metrics.snapshot().capturedSampleCount, 640)
            XCTAssertEqual(metrics.snapshot().processedSampleCount, 320)
        } catch {
            try? await services.store.close()
            try? Self.remove(root, within: parent)
            throw error
        }
        try await services.store.close()
        try Self.remove(root, within: parent)
    }

    private static func remove(_ root: URL, within parent: URL) throws {
        guard root.deletingLastPathComponent() == parent, parent.lastPathComponent == "LocalMinutesNativeProgressTests",
              UUID(uuidString: root.lastPathComponent) != nil, root.resolvingSymlinksInPath().standardizedFileURL == root else {
            XCTFail("Refuse cleanup outside owned native progress fixture"); return
        }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
