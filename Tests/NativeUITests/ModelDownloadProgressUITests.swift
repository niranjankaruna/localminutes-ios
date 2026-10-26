import XCTest

@MainActor
final class ModelDownloadProgressUITests: XCTestCase {
    func testModelsPageRemovesUnrelatedSectionsAndEndsWithDeviceInformation() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        guard minutesTap(minutesElement("settings.about", in: app), in: app),
              minutesTap(minutesElement("settings.device", in: app), in: app) else { return }
        XCTAssertTrue(app.staticTexts["models.device.availableMemory"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Privacy and renewal"].exists)
        XCTAssertFalse(app.staticTexts["Action Button"].exists)
    }

    func testSummaryListIncludesAppleIntelligenceWithItsAvailabilityAndSelectionAction() {
        let app = launch(stage: "idle")
        defer { app.terminate() }
        guard minutesTap(minutesElement("models.apple.open", in: app), in: app) else { return }
        XCTAssertTrue(app.staticTexts["models.apple.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["models.apple.availability"].exists)
        XCTAssertTrue(app.buttons["models.apple.equip"].exists)
    }

    func testDownloadShowsBytesPercentageSpeedRemainingTimeFileAndResumeDetails() {
        let app = launch(stage: "downloading")
        defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["models.download.stage"].label, "Downloading")
        XCTAssertTrue(app.staticTexts["models.download.percent"].label.contains("50"))
        XCTAssertTrue(app.staticTexts["models.download.bytes"].exists)
        guard minutesTap(minutesElement("models.download.details", in: app), in: app) else { return }
        XCTAssertTrue(app.staticTexts["models.download.file"].label.contains("2 of 5"))
        XCTAssertTrue(app.staticTexts["models.download.filename"].label.contains("weight.bin"))
        XCTAssertTrue(app.staticTexts["models.download.speed"].exists)
        XCTAssertTrue(app.staticTexts["models.download.remaining"].exists)
        XCTAssertTrue(app.staticTexts["models.download.resumed"].exists)
    }

    func testVerificationHasItsOwnProgressAndDoesNotShowAStaleDownloadSpeedOrETA() {
        let app = launch(stage: "verifying")
        defer { app.terminate() }
        XCTAssertEqual(app.staticTexts["models.download.stage"].label, "Verifying files")
        XCTAssertTrue(app.progressIndicators["models.download.progress"].exists)
        guard minutesTap(minutesElement("models.download.details", in: app), in: app) else { return }
        XCTAssertTrue(app.staticTexts["models.download.filename"].exists)
        XCTAssertFalse(app.staticTexts["models.download.speed"].exists)
        XCTAssertFalse(app.staticTexts["models.download.remaining"].exists)
    }

    private func launch(stage: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_PROGRESS"] = stage
        app.launch()
        XCTAssertTrue(app.navigationBars[stage == "idle" ? "Summary & Q&A" : "Model transfer"].waitForExistence(timeout: 15))
        return app
    }
}
