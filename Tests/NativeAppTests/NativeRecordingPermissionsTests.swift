import AppIntents
import Foundation
import XCTest
@testable import LocalMinutes

@MainActor
private final class RecordingPermissionsProbe: RecordingPermissionsSource {
    var microphone: RecordingMicrophonePermission = .notRequested
    var liveActivitiesEnabled = false
    var response: RecordingMicrophonePermission = .allowed
    private(set) var requests = 0

    func requestMicrophone() async {
        requests += 1
        microphone = response
    }
}

@MainActor
final class NativeRecordingPermissionsTests: XCTestCase {
    func testOpeningAndRefreshingPermissionsNeverPrompts() {
        let source = RecordingPermissionsProbe()
        let controller = RecordingPermissionsController(source: source)
        controller.refresh()
        XCTAssertEqual(controller.microphone, .notRequested)
        XCTAssertFalse(controller.liveActivitiesEnabled)
        XCTAssertEqual(source.requests, 0)
    }

    func testExplicitMicrophoneSetupWorksEvenWhenLiveActivitiesAreDisabled() async {
        let source = RecordingPermissionsProbe()
        let controller = RecordingPermissionsController(source: source)
        await controller.requestMicrophone()
        XCTAssertEqual(source.requests, 1)
        XCTAssertEqual(controller.microphone, .allowed)
        XCTAssertFalse(controller.liveActivitiesEnabled)
        XCTAssertFalse(controller.requestingMicrophone)
        await controller.requestMicrophone()
        XCTAssertEqual(source.requests, 1, "An existing grant must not show another prompt")
    }

    func testDeniedPromptRemainsDeniedAndCannotBeRequestedAgainInApp() async {
        let source = RecordingPermissionsProbe()
        source.response = .denied
        let controller = RecordingPermissionsController(source: source)
        await controller.requestMicrophone()
        XCTAssertEqual(controller.microphone, .denied)
        XCTAssertFalse(controller.requestingMicrophone)
        await controller.requestMicrophone()
        XCTAssertEqual(source.requests, 1, "A denial requires iPhone Settings, not another prompt")
    }

    func testReturningFromSettingsRefreshesMicrophoneAndLiveActivityStatus() async {
        let source = RecordingPermissionsProbe()
        source.microphone = .denied
        let controller = RecordingPermissionsController(source: source)
        await controller.requestMicrophone()
        XCTAssertEqual(source.requests, 0)
        source.microphone = .allowed
        source.liveActivitiesEnabled = true
        controller.refresh()
        XCTAssertEqual(controller.microphone, .allowed)
        XCTAssertTrue(controller.liveActivitiesEnabled)
        source.microphone = .denied
        source.liveActivitiesEnabled = false
        controller.refresh()
        XCTAssertEqual(controller.microphone, .denied)
        XCTAssertFalse(controller.liveActivitiesEnabled)
        XCTAssertEqual(source.requests, 0)
    }

    func testFailureRepliesIdentifyTheFailedRequirementAndWhereToResolveIt() throws {
        let failures: [(RecordingFailure, String)] = [
            (.microphoneDenied, "Microphone access"),
            (.activityUnavailable, "Live Activity"),
            (.captureUnavailable, "Audio could not start")
        ]
        var messages = Set<String>()
        for (failure, expected) in failures {
            let reply = RecordingIntentReplies.result(for: .requiresForeground(failure))
            let message = try XCTUnwrap(reply.value)
            XCTAssertTrue(message.contains(expected))
            XCTAssertTrue(message.contains("LocalMinutes →"))
            XCTAssertEqual(message, String(localized: RecordingIntentReplies.message(for: .blocked(failure))))
            XCTAssertEqual(RecordingForegroundRequiredError(failure: failure).errorDescription, message)
            XCTAssertNotNil(reply.dialog)
            messages.insert(message)
        }
        XCTAssertEqual(messages.count, failures.count)
    }

    func testBlockedShortcutPublishesRecordNavigationAndAnOldConsumerCannotClearANewerRequest() async throws {
        let app = RecordingApplication(services: nil)
        let reply = try await StartMeetingIntent(application: app).perform()
        XCTAssertEqual(reply.value, "A verified speech model is required before recording.")
        let first = try XCTUnwrap(app.recordingNavigationRequestID)
        _ = try await StartMeetingIntent(application: app).perform()
        let second = try XCTUnwrap(app.recordingNavigationRequestID)
        XCTAssertNotEqual(first, second)
        app.consumeRecordingNavigationRequest(first)
        XCTAssertEqual(app.recordingNavigationRequestID, second)
        app.consumeRecordingNavigationRequest(second)
        XCTAssertNil(app.recordingNavigationRequestID, "Consumed navigation must not override a later tab selection")
        let state = await app.owner?.snapshot()
        XCTAssertEqual(state?.failure, .modelUnavailable)
        XCTAssertEqual(state?.readiness.audioSessionActive, false)
    }
}
