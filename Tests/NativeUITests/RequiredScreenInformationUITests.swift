import XCTest

@MainActor
final class RequiredScreenInformationUITests: XCTestCase {
    func testActualRecordAndModelsScreensExplainMicrophoneLiveActivityAndDisplayVersionAndBuild() {
        let app = launchLibrary(statusVariant: false)
        defer { app.terminate() }
        let microphone = app.staticTexts["recording.microphoneExplanation"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        if microphone.exists {
            XCTAssertTrue(microphone.label.localizedCaseInsensitiveContains("microphone"))
            XCTAssertTrue(microphone.label.localizedCaseInsensitiveContains("permission"))
        }
        let activity = app.staticTexts["recording.liveActivityExplanation"]
        XCTAssertTrue(activity.exists)
        if activity.exists {
            XCTAssertTrue(activity.label.localizedCaseInsensitiveContains("Live Activit"))
            XCTAssertTrue(activity.label.localizedCaseInsensitiveContains("stop"))
        }
        app.tabBars.buttons["Models"].tap()
        let identity = app.staticTexts["settings.appBuildIdentity"]
        reveal(identity, in: app)
        XCTAssertTrue(identity.exists, "The actual Models/settings screen must identify the installed app version and build")
        if identity.exists {
            XCTAssertNotNil(identity.label.range(of: #"Version [0-9]+(?:\.[0-9]+)* \(build [0-9]+\)"#,
                                                options: .regularExpression))
        }
    }

    func testActualHistoryRowsReportOnlyTheirOwnPersistedTranscriptAndSummaryAvailability() {
        let app = launchLibrary(statusVariant: true)
        defer { app.terminate() }
        app.tabBars.buttons["Meetings"].tap()
        for (title, transcript, summary) in [
            ("UI Library Alpha", "Transcript available", "Summary available"),
            ("UI Library Beta", "No transcript", "Summary not generated")
        ] {
            let row = app.cells.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            guard row.exists else { continue }
            let transcriptStatus = row.staticTexts["meeting.history.transcriptStatus"]
            let summaryStatus = row.staticTexts["meeting.history.summaryStatus"]
            XCTAssertTrue(transcriptStatus.exists); XCTAssertTrue(summaryStatus.exists)
            if transcriptStatus.exists { XCTAssertEqual(transcriptStatus.label, transcript) }
            if summaryStatus.exists { XCTAssertEqual(summaryStatus.label, summary) }
            XCTAssertFalse(row.staticTexts["Transcript complete"].exists,
                "Synthetic audio and a completed recording do not establish completed recognition")
        }
    }

    private func launchLibrary(statusVariant: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if statusVariant { app.launchArguments.append("--ui-test-library-content-status") }
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Meetings"].waitForExistence(timeout: 10),
            "A real seeded library must load before required product-information assertions")
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
}
