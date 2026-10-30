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
            let navigation = f.application.meetingNavigation
            // Insert after startup so the intent cannot use an obsolete UI list.
            let latest = try await f.seed(id: UUID(), at: 20, title: "Latest private fixture")
            let result = try await OpenLatestMeetingIntent(application: f.application).perform()
            XCTAssertEqual(result.value, "Opening your last meeting.")
            XCTAssertNotNil(result.dialog)
            XCTAssertEqual(f.application.meetingNavigation.request?.destination, .meeting(latest.id))
            XCTAssertNotNil(f.application.meetingNavigation.request?.id)
            XCTAssertTrue(f.application.meetingNavigation === navigation,
                          "The app must retain the same router that the view observes")
            XCTAssertFalse(try XCTUnwrap(result.value).contains(latest.title), "Private titles must not be spoken or exported by the shortcut")
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
            let firstRequest = router.request?.id
            _ = try await f.seed(id: earlier, at: 100)
            let tied = try await router.openLatest()
            XCTAssertEqual(tied, .opened(earlier),
                "The SQLite history contract uses created_at DESC, id ASC; insertion order cannot choose the tie")
            XCTAssertEqual(router.request?.destination, .meeting(earlier))
            XCTAssertNotNil(router.request?.id)
            XCTAssertNotEqual(router.request?.id, firstRequest, "Repeated navigation needs a fresh observable request")
            let last = try await f.seed(id: UUID(), at: 101)
            let newest = try await router.openLatest()
            XCTAssertEqual(newest, .opened(last.id))
            XCTAssertEqual(router.request?.destination, .meeting(last.id))
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
            XCTAssertEqual(router.request?.destination, .meetings)
            let meeting = try await f.seed(id: UUID(), at: 1)
            let opened = try await router.openLatest()
            XCTAssertEqual(opened, .opened(meeting.id))
            XCTAssertEqual(router.request?.destination, .meeting(meeting.id))
            try await f.services.store.close()
            f.closed = true
            let unavailable = try await router.openLatest()
            XCTAssertEqual(unavailable, .unavailable)
            let closed = try await OpenLatestMeetingIntent(application: f.application, router: router).perform()
            XCTAssertEqual(closed.value, "Saved meetings are not available.")
            XCTAssertNotNil(closed.dialog)
            XCTAssertEqual(router.request?.destination, .meetings,
                           "A closed store must open the list instead of leaving an old meeting selected")
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
            XCTAssertNil(router.request)
            let actual = try await f.services.store.meeting(id: original.id)
            XCTAssertEqual(actual, original)
            XCTAssertNil(f.application.lastOutcome)
        }
    }

    func testExactlyThreeNavigationShortcutsRequireForegroundAndLocalUnlock() throws {
        func checkNavigationIntent<I: AppIntent>(_ type: I.Type) {
            XCTAssertTrue(type.isDiscoverable)
            switch type.authenticationPolicy {
            case .requiresLocalDeviceAuthentication: break
            default: XCTFail("Opening private app screens requires unlocking this device")
            }
            XCTAssertTrue(type.openAppWhenRun, "Earlier iOS versions must also open the app")
            if #available(iOS 26.0, *) {
                XCTAssertEqual(type.supportedModes, [.foreground(.immediate)])
            }
        }
        checkNavigationIntent(OpenRecordingIntent.self)
        checkNavigationIntent(OpenMeetingsIntent.self)
        checkNavigationIntent(OpenLatestMeetingIntent.self)
        let intent = OpenLatestMeetingIntent()
        XCTAssertTrue(intent.application === RecordingApplication.shared)
        XCTAssertTrue(OpenRecordingIntent().application === RecordingApplication.shared)
        XCTAssertTrue(OpenMeetingsIntent().application === RecordingApplication.shared)
        XCTAssertEqual(String(localized: OpenRecordingIntent.title), "Open LocalMinutes Recording")
        XCTAssertEqual(String(localized: OpenMeetingsIntent.title), "Open LocalMinutes Meetings")
        XCTAssertEqual(String(localized: OpenLatestMeetingIntent.title), "Open Last LocalMinutes Meeting")
        let intents: [Any] = [OpenRecordingIntent(), OpenMeetingsIntent(), intent]
        for value in intents {
            XCTAssertFalse(value is any AudioRecordingIntent)
            XCTAssertFalse(value is any LiveActivityIntent)
        }
        XCTAssertEqual(LocalMinutesShortcuts.appShortcuts.count, 3)
    }

    func testOpenRecordingAndMeetingsReplaceTheDetailRouteWithoutStartingRecording() async throws {
        try await fixture { f in
            let meeting = try await f.seed(id: UUID(), at: 10)
            let before = await f.application.owner?.snapshot()
            _ = try await OpenLatestMeetingIntent(application: f.application).perform()
            XCTAssertEqual(f.application.meetingNavigation.request?.destination, .meeting(meeting.id))
            let recording = try await OpenRecordingIntent(application: f.application).perform()
            XCTAssertEqual(recording.value, "Opening recording controls.")
            XCTAssertEqual(f.application.meetingNavigation.request?.destination, .recording)
            let recordingID = try XCTUnwrap(f.application.meetingNavigation.request?.id)
            let meetings = try await OpenMeetingsIntent(application: f.application).perform()
            XCTAssertEqual(meetings.value, "Opening your meetings.")
            XCTAssertEqual(f.application.meetingNavigation.request?.destination, .meetings)
            f.application.meetingNavigation.consumeRequest(recordingID)
            XCTAssertEqual(f.application.meetingNavigation.request?.destination, .meetings,
                           "A delayed view callback cannot consume a newer shortcut")
            let after = await f.application.owner?.snapshot()
            XCTAssertEqual(after, before)
            XCTAssertNil(f.application.lastOutcome)
            let unchanged = try await f.services.store.meeting(id: meeting.id)
            XCTAssertEqual(unchanged, meeting)
        }
    }

    func testNavigationStillWorksWhenPersistentServicesAreUnavailable() async throws {
        let app = RecordingApplication(services: nil)
        _ = try await OpenRecordingIntent(application: app).perform()
        XCTAssertEqual(app.meetingNavigation.request?.destination, .recording)
        _ = try await OpenMeetingsIntent(application: app).perform()
        XCTAssertEqual(app.meetingNavigation.request?.destination, .meetings)
        let last = try await OpenLatestMeetingIntent(application: app).perform()
        XCTAssertEqual(last.value, "Saved meetings are not available.")
        XCTAssertEqual(app.meetingNavigation.request?.destination, .meetings)
        let state = await app.owner?.snapshot()
        XCTAssertEqual(state?.phase, .idle)
        XCTAssertNil(state?.sessionID)
        XCTAssertNil(app.lastOutcome)
    }

    func testLateLatestLookupCannotReplaceANewerNavigationRequest() async throws {
        for closeStore in [false, true] {
            try await fixture { f in
                _ = try await f.seed(id: UUID(), at: 10)
                let boundary = LatestIntentStartBoundary()
                let router = MeetingNavigationRouter(store: f.services.store, beforeLatestRead: {
                    await boundary.wait()
                })
                let pending = Task { try await router.openLatest() }
                defer { pending.cancel(); boundary.release() }
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while !boundary.isWaiting && ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(1))
                }
                XCTAssertTrue(boundary.isWaiting)
                guard boundary.isWaiting else {
                    pending.cancel(); boundary.release(); _ = try? await pending.value
                    return
                }
                if closeStore {
                    try await f.services.store.close()
                    f.closed = true
                    router.openMeetings()
                } else {
                    router.openRecording()
                }
                let newer = router.request
                boundary.release()
                let outcome = try await pending.value
                XCTAssertEqual(outcome, .superseded)
                XCTAssertEqual(router.request, newer,
                               "Neither an old successful read nor an old failure may replace a newer destination")
            }
        }
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
    var isWaiting: Bool { continuation != nil }
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
