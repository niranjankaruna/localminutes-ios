import XCTest

/// Simulator UI contract only; not physical microphone or locked-ASR evidence.
@MainActor
final class RecordingControlsUITests: XCTestCase {
    func testScreenshotReadinessPreservesRecordingControlIdentifiers() {
        for scene in ["record_idle", "record_active"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-library-fixture", "--ui-screenshots"]
            app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
            app.launchEnvironment["LOCALMINUTES_SCREENSHOT_SCENE"] = scene
            app.launch()
            defer { app.terminate() }
            let markers = app.descendants(matching: .any).matching(identifier: "screenshot.ready.\(scene)")
            XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 40))
            XCTAssertEqual(markers.count, 1, "Readiness belongs to one leaf, never the recording controls.")
            let control = app.buttons[scene == "record_idle" ? "recording.start" : "recording.stop"]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable)
            XCTAssertTrue(app.staticTexts["recording.elapsed"].isHittable)
            XCTAssertTrue(app.scrollViews["recording.content.scroll"].exists)
        }
    }

    func testColdOpenRecordingShortcutOnlyOpensRecordAndOffersPermissionsWithoutASpeechModel() {
        let app = minutesLibraryApp(arguments: ["--ui-test-recording-shortcut"])
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(minutesElement("recording.modelRequired", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Record"].isSelected)
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
        guard minutesTap(app.buttons["recording.permissions"], in: app) else { return }
        XCTAssertTrue(minutesElement("recording.permissions.microphone", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(minutesElement("recording.permissions.liveActivities", in: app).exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Reviewing permission status must not prompt for access")
    }

    func testRecordingPermissionsAreAccessibleFromSettingsBeforeModelSetup() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        guard minutesTap(app.tabBars.buttons["Settings"], in: app) else { return }
        guard minutesTap(minutesElement("settings.recordingPermissions", in: app), in: app) else { return }
        XCTAssertTrue(minutesElement("recording.permissions.microphone", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(minutesElement("recording.permissions.liveActivities", in: app).exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testOpenLastMeetingShortcutSelectsNewestSavedMeetingWithoutRecording() {
        let app = minutesLibraryApp(arguments: ["--ui-test-last-meeting-shortcut"])
        app.launch(); defer { app.terminate() }
        let summary = app.staticTexts["meeting.generatedSummary.content"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        minutesWaitForValue("Seeded Alpha generated summary.", summary)
        XCTAssertTrue(app.tabBars.buttons["Meetings"].isSelected)
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testOpenMeetingsShortcutReplacesAPendingDetailRouteWithTheList() {
        let app = minutesLibraryApp(arguments: ["--ui-test-meetings-shortcut"])
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(minutesHistoryRow("UI Library Alpha", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(minutesHistoryRow("UI Library Beta", in: app).exists)
        XCTAssertTrue(app.tabBars.buttons["Meetings"].isSelected)
        XCTAssertFalse(app.staticTexts["meeting.generatedSummary.content"].exists)
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
    }

    func testOpenLastMeetingWithEmptyLibraryShowsMeetingsWithoutRecording() {
        let app = minutesLibraryApp(arguments: ["--ui-test-library-empty", "--ui-test-last-meeting-shortcut"])
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(minutesElement("meeting.history.empty", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Meetings"].isSelected)
        XCTAssertFalse(app.staticTexts["recording.active"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNewFinalizedTranscriptScrollsIntoViewWhileStopAndTimerStayAtTheTop() async throws {
        let app = transcriptApp(stream: "finalized")
        app.launch(); defer { app.terminate() }
        let stop = app.buttons["recording.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15))
        guard stop.exists else { return }
        let initialStopFrame = stop.frame
        let latest = app.staticTexts["recording.liveTranscript.20000000-0000-0000-0000-000000000025"]
        try await waitForTranscriptEnd(latest, in: app)
        XCTAssertTrue(latest.isHittable, "New speech should be visible without a manual swipe.")
        XCTAssertTrue(stop.isHittable)
        XCTAssertEqual(stop.frame.minY, initialStopFrame.minY, accuracy: 1)
        let timer = app.staticTexts["recording.elapsed"]
        XCTAssertTrue(timer.isHittable)
        let tabs = app.segmentedControls["recording.content.tabs"]
        XCTAssertFalse(stop.frame.intersects(timer.frame), "The compact recording controls must not overlap.")
        XCTAssertLessThanOrEqual(stop.frame.maxY, tabs.frame.minY)
        XCTAssertLessThanOrEqual(timer.frame.maxY, tabs.frame.minY)
    }

    func testGrowingPartialTranscriptScrollsItsLastLineIntoView() async throws {
        let app = transcriptApp(stream: "partial")
        app.launch(); defer { app.terminate() }
        let partial = app.staticTexts["recording.liveTranscript.partial"]
        try await waitForTranscriptEnd(partial, in: app)
        XCTAssertTrue(partial.label.hasSuffix("Latest partial words."))
        XCTAssertTrue(app.buttons["recording.stop"].isHittable)
    }

    private func transcriptApp(stream: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "--ui-screenshots",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launchEnvironment["LOCALMINUTES_SCREENSHOT_SCENE"] = "record_live_transcript"
        app.launchEnvironment["LOCALMINUTES_UI_TRANSCRIPT_STREAM"] = stream
        return app
    }

    private func waitForTranscriptEnd(_ element: XCUIElement, in app: XCUIApplication) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if element.exists, app.tabBars.firstMatch.exists {
                let frame = element.frame
                let lowerEdge = app.tabBars.firstMatch.frame.minY
                let tabs = app.segmentedControls["recording.content.tabs"]
                if !frame.isEmpty, tabs.exists,
                   frame.maxY > tabs.frame.maxY, frame.maxY <= lowerEdge + 1 { return }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The newest transcript text did not scroll above the tab bar: \(element.debugDescription)")
    }

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
        XCTAssertTrue(minutesElement("models.family.parakeet-v2", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(minutesElement("models.repository.open", in: app).exists)
    }
}
