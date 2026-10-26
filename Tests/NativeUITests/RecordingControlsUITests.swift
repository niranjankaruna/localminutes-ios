import XCTest

/// Simulator UI contract only; not physical microphone or locked-ASR evidence.
@MainActor
final class RecordingControlsUITests: XCTestCase {
    func testSharedActivityStopControlDispatchesItsExactSessionToTheApplicationOwner() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-activity-controls"]
        app.launch()
        let stop = app.buttons["recording.activity.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        guard stop.exists else { return }
        XCTAssertEqual(stop.label, "Stop Recording")
        XCTAssertTrue(stop.isEnabled)
        XCTAssertTrue(app.staticTexts["recording.activity.elapsed"].exists)
        stop.tap()
        let outcome = app.staticTexts["recording.activity.outcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 5))
        XCTAssertEqual(outcome.label, "This control belongs to an earlier recording.",
                       "A scoped synthetic Activity cannot become an unscoped idle stop")
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
    }

    func testSharedActivityTerminalTimerIsFixedAndStopIsDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-activity-finished"]
        app.launch()
        let elapsed = app.staticTexts["recording.activity.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        guard elapsed.exists else { return }
        XCTAssertEqual(elapsed.label, "1:05")
        let stop = app.buttons["recording.activity.stop"]
        XCTAssertTrue(stop.exists)
        XCTAssertFalse(stop.isEnabled)
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
    }

    func testStartExplainsMissingSpeechModelWithoutClaimingRecording() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        let record = app.tabBars.buttons["Record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        guard minutesTap(record, in: app) else { return }
        XCTAssertTrue(minutesElement("recording.modelRequired", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recording.start"].exists,
            "A missing speech model offers setup before microphone use.")
        XCTAssertFalse(app.buttons["recording.stop"].exists,
            "The new design only shows a Stop control for an active session.")
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
        guard minutesTap(app.buttons["Choose speech model"], in: app) else { return }
        XCTAssertTrue(app.buttons["models.parakeet.browse"].waitForExistence(timeout: 5))
    }
}
