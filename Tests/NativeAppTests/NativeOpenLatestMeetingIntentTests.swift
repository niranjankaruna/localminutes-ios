#if os(iOS)
import AppIntents
import Foundation
import XCTest
@testable import LocalMinutes

/// Actual native SDK/app/SQLite navigation contracts. No microphone, signing,
/// locked dispatch, model inference or physical authentication pass is claimed.
@MainActor
final class NativeOpenLatestMeetingIntentTests: XCTestCase {
    func testActualIntentPublishesNewestMeetingThroughTheRetainedApplicationRouterWithoutRecording() async throws {
        try await fixture { f in
            let first = try await f.seed(id: UUID(), at: 10, title: "Older private fixture")
            await f.services.initialize()
            let before = try XCTUnwrap(f.application.owner)
            let beforeSnapshot = await before.snapshot()
            // Insert after startup so the intent cannot use an obsolete UI list.
            let latest = try await f.seed(id: UUID(), at: 20, title: "Latest private fixture")
            let result = try await OpenLatestMeetingIntent(application: f.application).perform()
            XCTAssertEqual(result.value, "Opening your latest meeting.")
            XCTAssertNotNil(result.dialog)
            XCTAssertNotNil(f.application.meetingNavigation, "The app must retain the same router that the view observes")
            XCTAssertEqual(f.application.meetingNavigation?.requestedMeetingID, latest.id)
            XCTAssertNotNil(f.application.meetingNavigation?.requestID)
            XCTAssertTrue(f.application.meetingNavigation === f.application.meetingNavigation)
            XCTAssertFalse(result.value.contains(latest.title), "Private titles must not be spoken or exported by the shortcut")
            let after = await before.snapshot()
            XCTAssertEqual(after.phase, beforeSnapshot.phase)
            XCTAssertEqual(after.sessionID, beforeSnapshot.sessionID)
            XCTAssertEqual(after.readiness.audioSessionActive, beforeSnapshot.readiness.audioSessionActive)
            XCTAssertNil(f.application.lastOutcome, "Opening a meeting must never dispatch recording controls")
            let original = try await f.services.store.meeting(id: first.id)
            let newest = try await f.services.store.meeting(id: latest.id)
            XCTAssertEqual(original, first); XCTAssertEqual(newest, latest)
        }
    }

    func testRouterReadsActualSQLiteCreationOrderWithDeterministicUUIDTiesOnEveryRequest() async throws {
        try await fixture { f in
            let earlier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let later = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            _ = try await f.seed(id: later, at: 100)
            let router = MeetingNavigationRouter(store: f.services.store)
            let initial = try await router.openLatest()
            XCTAssertEqual(initial, .opened(later))
            let firstRequest = router.requestID
            _ = try await f.seed(id: earlier, at: 100)
            let tied = try await router.openLatest()
            XCTAssertEqual(tied, .opened(earlier),
                "The SQLite history contract uses created_at DESC, id ASC; insertion order cannot choose the tie")
            XCTAssertEqual(router.requestedMeetingID, earlier)
            XCTAssertNotNil(router.requestID)
            XCTAssertNotEqual(router.requestID, firstRequest, "Repeated navigation needs a fresh observable request")
            let last = try await f.seed(id: UUID(), at: 101)
            let newest = try await router.openLatest()
            XCTAssertEqual(newest, .opened(last.id))
            XCTAssertEqual(router.requestedMeetingID, last.id)
        }
    }

    func testEmptyAndClosedActualStoresReturnRecoverableResultsWithoutPublishingAStaleRoute() async throws {
        try await fixture { f in
            let router = MeetingNavigationRouter(store: f.services.store)
            let missing = try await router.openLatest()
            XCTAssertEqual(missing, .emptyLibrary)
            let empty = try await OpenLatestMeetingIntent(application: f.application, router: router).perform()
            XCTAssertEqual(empty.value, "No saved meetings yet.")
            XCTAssertNotNil(empty.dialog)
            XCTAssertNil(router.requestedMeetingID); XCTAssertNil(router.requestID)
            let meeting = try await f.seed(id: UUID(), at: 1)
            let opened = try await router.openLatest()
            XCTAssertEqual(opened, .opened(meeting.id))
            XCTAssertEqual(router.requestedMeetingID, meeting.id)
            try await f.services.store.close()
            f.closed = true
            let unavailable = try await router.openLatest()
            XCTAssertEqual(unavailable, .unavailable)
            let closed = try await OpenLatestMeetingIntent(application: f.application, router: router).perform()
            XCTAssertEqual(closed.value, "Saved meetings are not available.")
            XCTAssertNotNil(closed.dialog)
            XCTAssertNil(router.requestedMeetingID, "A closed store cannot leave an old meeting selected for a new intent")
            XCTAssertNil(router.requestID)
        }
    }

    func testAlreadyCancelledNativeIntentDoesNotPublishOrChangeTheActualMeeting() async throws {
        try await fixture { f in
            let original = try await f.seed(id: UUID(), at: 100)
            let router = MeetingNavigationRouter(store: f.services.store)
            let boundary = LatestIntentStartBoundary()
            let call = LatestIntentCancelledCall()
            let operation = Task { @MainActor in
                await boundary.wait()
                do {
                    let reply = try await OpenLatestMeetingIntent(application: f.application, router: router).perform()
                    call.returnedValue = reply.value
                } catch { call.error = error }
            }
            operation.cancel()
            boundary.release()
            await operation.value
            XCTAssertTrue(call.error is CancellationError, "A cancelled intent must propagate CancellationError")
            XCTAssertNil(call.returnedValue)
            XCTAssertNil(router.requestedMeetingID); XCTAssertNil(router.requestID)
            let actual = try await f.services.store.meeting(id: original.id)
            XCTAssertEqual(actual, original)
            XCTAssertNil(f.application.lastOutcome)
        }
    }

    func testNativeSDKRequiresLocalUnlockForegroundAndASeparateFourthDiscoverableShortcut() throws {
        func acceptsAppIntent<I: AppIntent>(_: I.Type) {}
        acceptsAppIntent(OpenLatestMeetingIntent.self)
        let intent = OpenLatestMeetingIntent()
        XCTAssertTrue(intent.application === RecordingApplication.shared)
        XCTAssertTrue(OpenLatestMeetingIntent.isDiscoverable)
        XCTAssertEqual(String(localized: OpenLatestMeetingIntent.title), "Open Latest LocalMinutes Meeting")
        switch OpenLatestMeetingIntent.authenticationPolicy {
        case .requiresLocalDeviceAuthentication: break
        default: XCTFail("Private history requires unlocking this device, independently of recording-control policy")
        }
        XCTAssertFalse((intent as Any) is any AudioRecordingIntent)
        XCTAssertFalse((intent as Any) is any LiveActivityIntent)
        XCTAssertTrue(OpenLatestMeetingIntent.openAppWhenRun, "iOS18 compatibility must open the app")
        if #available(iOS 26.0, *) {
            let modes = OpenLatestMeetingIntent.supportedModes
            XCTAssertTrue(modes.contains(.foreground(.immediate)))
            XCTAssertFalse(modes.contains(.background))
            XCTAssertFalse(modes.contains(.foreground(.dynamic)))
        }
        XCTAssertEqual(LocalMinutesShortcuts.appShortcuts.count, 4)
    }

    private func fixture(_ body: @MainActor (LatestIntentFixture) async throws -> Void) async throws {
        let f = try LatestIntentFixture()
        do { try await body(f) }
        catch { await f.cleanup(); throw error }
        await f.cleanup()
    }
}

@MainActor
private final class LatestIntentFixture {
    let root: URL
    let services: LocalMinutesServices
    let application: RecordingApplication
    var closed = false

    init() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        root = parent.appendingPathComponent("localminutes-latest-intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        services = try LocalMinutesServices(rootURL: root)
        application = RecordingApplication(services: services)
    }
    func seed(id: UUID, at timestamp: TimeInterval, title: String = "Private latest-meeting fixture") async throws -> MeetingRecord {
        let meeting = MeetingRecord(id: id, title: title, createdAt: Date(timeIntervalSince1970: timestamp),
            recordingState: .completed)
        try await services.store.createMeeting(meeting)
        return meeting
    }
    func cleanup() async {
        await application.owner?.stop()
        guard let snapshot = await application.owner?.snapshot(),
              !snapshot.cleanupPending, !snapshot.readiness.audioSessionActive else {
            XCTFail("Intent fixture still owns recording resources; its directory is retained"); return
        }
        if !closed {
            do { try await services.store.close(); closed = true }
            catch { XCTFail("Intent fixture database did not close"); return }
        }
        guard root.lastPathComponent.hasPrefix("localminutes-latest-intent-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("localminutes-latest-intent-".count))) != nil else {
            XCTFail("Intent fixture cleanup ownership mismatch"); return
        }
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Intent fixture cleanup failed") }
    }
}

@MainActor
private final class LatestIntentStartBoundary {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(); continuation = nil
    }
}

@MainActor
private final class LatestIntentCancelledCall {
    var returnedValue: String?
    var error: (any Error)?
}
#endif
