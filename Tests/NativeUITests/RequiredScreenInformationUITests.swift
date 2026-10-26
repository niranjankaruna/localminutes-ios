import XCTest

@MainActor
final class RequiredScreenInformationUITests: XCTestCase {
    func testActualRecordAndModelsScreensExplainMicrophoneLiveActivityAndDisplayVersionAndBuild() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        guard minutesTap(minutesElement("settings.privacy", in: app), in: app) else { return }
        let microphone = app.staticTexts["recording.microphoneExplanation"]
        minutesReveal(microphone, in: app)
        XCTAssertTrue(microphone.label.localizedCaseInsensitiveContains("microphone"))
        XCTAssertTrue(microphone.label.localizedCaseInsensitiveContains("permission"))
        let activity = app.staticTexts["recording.liveActivityExplanation"]
        minutesReveal(activity, in: app)
        XCTAssertTrue(activity.label.localizedCaseInsensitiveContains("Live Activit"))
        XCTAssertTrue(activity.label.localizedCaseInsensitiveContains("stop"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        guard minutesTap(minutesElement("settings.about", in: app), in: app) else { return }
        let identity = app.staticTexts["settings.appBuildIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertNotNil(identity.label.range(of: #"Version [0-9]+(?:\.[0-9]+)* \(build [0-9]+\)"#, options: .regularExpression))
    }

    func testActualHistoryRowsReportOnlyTheirOwnPersistedTranscriptAndSummaryAvailability() {
        let app = minutesLibraryApp(arguments: ["--ui-test-library-content-status"])
        app.launch(); defer { app.terminate() }
        for (name, expected) in [
            ("Alpha", "Transcript available. Summary available."),
            ("Beta", "No transcript. Summary not generated.")
        ] {
            let row = minutesHistoryRow("UI Library \(name)", in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            XCTAssertEqual(row.value as? String, expected,
                "Healthy status is available to VoiceOver without repeating it visually on every row.")
        }
        XCTAssertFalse(app.staticTexts["Transcript complete"].exists)
    }
}
