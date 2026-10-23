import XCTest

/// Simulator UI contract only; not physical microphone or locked-ASR evidence.
@MainActor
final class RecordingControlsUITests: XCTestCase {
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
