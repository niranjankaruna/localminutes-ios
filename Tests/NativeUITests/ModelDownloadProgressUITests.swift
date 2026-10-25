import XCTest

/// Actual product view/accessibility tree; progress values are a UI boundary
/// fixture. Real HTTP progress and Darwin memory have independent native tests.
@MainActor
final class ModelDownloadProgressUITests: XCTestCase {
    func testModelsPageRemovesUnrelatedSectionsAndEndsWithDeviceInformation() {
        let app = launch(stage: "idle")
        defer { app.terminate() }
        XCTAssertFalse(app.staticTexts["Privacy and renewal"].exists)
        XCTAssertFalse(app.staticTexts["Action Button"].exists)
        let device = app.staticTexts["models.device.heading"]
        reveal(device, in: app)
        XCTAssertTrue(device.exists, "The final section must clearly identify this iPhone")
        XCTAssertTrue(app.staticTexts["models.device.availableMemory"].exists)
    }

    func testSummaryListIncludesAppleIntelligenceWithItsAvailabilityAndSelectionAction() {
        let app = launch(stage: "idle")
        defer { app.terminate() }
        let choice = app.staticTexts["models.apple.title"]
        reveal(choice, in: app)
        XCTAssertTrue(choice.exists, "The system model must be discoverable alongside downloaded summary choices")
        XCTAssertEqual(choice.label, "Apple Intelligence")
        XCTAssertTrue(app.staticTexts["models.apple.availability"].exists)
        XCTAssertTrue(app.buttons["models.apple.equip"].exists, "Unavailable devices keep an honest, disabled system-model choice")
    }

    func testDownloadShowsBytesPercentageSpeedRemainingTimeFileAndResumeDetails() {
        let app = launch(stage: "downloading")
        defer { app.terminate() }
        let stage = app.staticTexts["models.download.stage"]
        reveal(stage, in: app)
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(stage.label, "Downloading")
        XCTAssertTrue(app.staticTexts["models.download.bytes"].exists)
        XCTAssertTrue(app.staticTexts["models.download.percent"].label.contains("50"))
        XCTAssertTrue(app.staticTexts["models.download.file"].label.contains("2 of 5"))
        XCTAssertTrue(app.staticTexts["models.download.filename"].label.contains("weight.bin"))
        XCTAssertTrue(app.staticTexts["models.download.speed"].exists)
        XCTAssertTrue(app.staticTexts["models.download.remaining"].exists)
        XCTAssertTrue(app.staticTexts["models.download.resumed"].exists)
    }

    func testVerificationHasItsOwnProgressAndDoesNotShowAStaleDownloadSpeedOrETA() {
        let app = launch(stage: "verifying")
        defer { app.terminate() }
        let stage = app.staticTexts["models.download.stage"]
        reveal(stage, in: app)
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertEqual(stage.label, "Verifying files")
        XCTAssertTrue(app.progressIndicators["models.download.progress"].exists)
        XCTAssertFalse(app.staticTexts["models.download.speed"].exists)
        XCTAssertFalse(app.staticTexts["models.download.remaining"].exists)
    }

    private func launch(stage: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_PROGRESS"] = stage
        app.launch()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 15))
        return app
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            app.swipeUp()
        }
    }
}
