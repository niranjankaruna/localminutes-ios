import AppIntents
import AVFoundation
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

    func testOpenRecordingNavigatesWithoutARecordAttemptAndAnOldConsumerCannotClearANewerRequest() async throws {
        let app = RecordingApplication(services: nil)
        let reply = try await OpenRecordingIntent(application: app).perform()
        XCTAssertEqual(reply.value, "Opening recording controls.")
        XCTAssertEqual(app.meetingNavigation.request?.destination, .recording)
        let first = try XCTUnwrap(app.meetingNavigation.request?.id)
        _ = try await OpenRecordingIntent(application: app).perform()
        let second = try XCTUnwrap(app.meetingNavigation.request?.id)
        XCTAssertNotEqual(first, second)
        app.meetingNavigation.consumeRequest(first)
        XCTAssertEqual(app.meetingNavigation.request?.id, second)
        app.meetingNavigation.consumeRequest(second)
        XCTAssertNil(app.meetingNavigation.request, "Consumed navigation must not override a later tab selection")
        let state = await app.owner?.snapshot()
        XCTAssertEqual(state?.phase, .idle)
        XCTAssertNil(state?.sessionID)
        XCTAssertNil(state?.failure)
        XCTAssertNil(app.lastOutcome)
        XCTAssertEqual(state?.readiness.audioSessionActive, false)
    }

    func testAudioRejectionMessagesUseTheNativeDomainCodeAndStage() {
        let cases: [(AVAudioSession.ErrorCode, String)] = [
            (.cannotStartRecording, "iOS did not allow"),
            (.cannotStartPlaying, "iOS did not allow"),
            (.cannotInterruptOthers, "iOS did not allow"),
            (.insufficientPriority, "another audio session has priority"),
            (.siriIsRecording, "another audio session has priority")
        ]
        let outcome = RecordingIntentOutcome.requiresForeground(.captureUnavailable)
        for (code, expected) in cases {
            let diagnostic = CaptureFailureDiagnostic(sessionID: UUID(), stage: .sessionActivation,
                error: NSError(domain: NSOSStatusErrorDomain, code: Int(code.rawValue)))
            let message = String(localized: RecordingIntentReplies.message(for: outcome, diagnostic: diagnostic))
            XCTAssertTrue(message.contains(expected))
        }
        let generic = String(localized: RecordingIntentReplies.message(for: outcome))
        let unrelatedErrors: [(String, CaptureFailureDiagnostic.Stage, Int)] = [
            ("UnrelatedErrorDomain", .sessionActivation,
             Int(AVAudioSession.ErrorCode.cannotStartRecording.rawValue)),
            (NSOSStatusErrorDomain, .inputPreparation, Int(AVAudioSession.ErrorCode.cannotStartRecording.rawValue)),
            (NSOSStatusErrorDomain, .sessionActivation, -1234)
        ]
        for (domain, stage, code) in unrelatedErrors {
            let diagnostic = CaptureFailureDiagnostic(sessionID: UUID(), stage: stage,
                error: NSError(domain: domain, code: code))
            XCTAssertEqual(String(localized: RecordingIntentReplies.message(for: outcome, diagnostic: diagnostic)), generic,
                           "An unknown error or a different operation must not be diagnosed as an iOS start restriction")
        }
    }
}
