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
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["recording.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "The app must expose its recording command")
        guard start.exists else { return }
        XCTAssertTrue(start.isEnabled)
        start.tap()
        let required = app.staticTexts["recording.modelRequired"]
        XCTAssertTrue(required.waitForExistence(timeout: 5),
                      "Missing real ASR must explain the block before microphone use")
        XCTAssertEqual(required.label, "A verified speech model is required before recording.")
        XCTAssertFalse(app.staticTexts["recording.active"].exists,
                       "A denied model preflight cannot publish recording success")
        let stop = app.buttons["recording.stop"]
        XCTAssertTrue(stop.exists)
        XCTAssertFalse(stop.isEnabled)
    }
}
