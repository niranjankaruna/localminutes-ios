import XCTest

/// Exercise real native controls against the existing owned library fixtures.
/// No microphone, model inference, external sharing or destructive action runs.
@MainActor
final class DesignInteractionUITests: XCTestCase {
    func testMeetingDeletionOffersVisibleCancelAndKeepsTheMeetingInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = minutesLibraryApp()
            app.launchEnvironment["LOCALMINUTES_UI_APPEARANCE"] = appearance
            app.launch(); defer { app.terminate() }
            guard minutesOpenMeeting("UI Library Beta", in: app),
                  minutesTap(app.buttons["meeting.actions"], in: app),
                  minutesTap(app.buttons["meeting.delete"], in: app) else { return }
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.buttons["meeting.delete.confirm"].exists)
            let cancel = alert.buttons["Cancel"]
            XCTAssertTrue(cancel.isHittable, "Cancelling deletion must be explicit in \(appearance) mode.")
            guard cancel.isHittable else { return }
            cancel.tap()
            XCTAssertEqual(app.staticTexts["meeting.title"].label, "UI Library Beta")
            app.navigationBars.buttons["Meetings"].tap()
            XCTAssertTrue(minutesHistoryRow("UI Library Beta", in: app).waitForExistence(timeout: 5))
        }
    }

    func testSummaryResetAndDeletionCanBeCancelledWithoutChangingTheSavedSummary() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        let summary = minutesElement("meeting.generatedSummary.content", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let original = summary.label
        for action in ["meeting.summary.reset", "meeting.summary.delete"] {
            guard minutesTap(app.buttons["meeting.summary.options"], in: app),
                  minutesTap(app.buttons[action], in: app) else { return }
            let cancel = app.alerts.firstMatch.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            XCTAssertTrue(cancel.isHittable)
            guard cancel.isHittable else { return }
            cancel.tap()
            XCTAssertTrue(summary.exists)
            XCTAssertEqual(summary.label, original)
        }
    }

    func testModelRemovalHasACancelActionAtLargestTextAndKeepsItsDownload() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_AX5"] = "1"
        app.launch()
        defer { app.terminate() }
        guard minutesTap(minutesElement("models.family.qwen25", in: app), in: app),
              minutesTap(app.buttons["models.remove.ui-model-alpha"], in: app) else { return }
        let cancel = app.alerts.firstMatch.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        guard cancel.isHittable else { return }
        cancel.tap()
        let useModel = app.buttons["models.equip.ui-model-alpha"]
        minutesReveal(useModel, in: app)
        XCTAssertTrue(useModel.isHittable)
        XCTAssertGreaterThanOrEqual(useModel.frame.height, 44)
        XCTAssertFalse(app.buttons["models.download.ui-model-alpha"].exists)
    }

    func testMeetingAndExportChoicesAdaptAtLargestText() {
        let app = minutesLibraryApp()
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_AX5"] = "1"
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        XCTAssertFalse(app.segmentedControls["meeting.content.tabs"].exists,
            "Accessibility text must not be squeezed into four segments.")
        let choices = minutesElement("meeting.content.tabs", in: app)
        guard minutesTap(choices, in: app), minutesTap(app.buttons["Notes"], in: app) else { return }
        let notes = app.staticTexts["meeting.notes.content"]
        minutesReveal(notes, in: app)
        XCTAssertEqual(notes.label, "Original Beta manual note.")
        guard minutesTap(app.buttons["meeting.export.open"], in: app) else { return }
        XCTAssertFalse(app.segmentedControls["meeting.export.format"].exists)
        let format = minutesElement("meeting.export.format", in: app)
        minutesReveal(format, in: app)
        XCTAssertTrue(format.isHittable)
        XCTAssertGreaterThanOrEqual(format.frame.height, 44)
        let share = app.buttons["meeting.export.text"]
        minutesReveal(share, in: app)
        XCTAssertTrue(share.isHittable)
        XCTAssertGreaterThanOrEqual(share.frame.height, 44)
        XCTAssertTrue(app.frame.contains(share.frame))
    }
}
