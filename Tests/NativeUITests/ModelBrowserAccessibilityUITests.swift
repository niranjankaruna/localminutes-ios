import XCTest

/// Real verified synthetic installations. The redesigned list opens focused
/// details; selection/removal still announce the actual purpose and repository.
@MainActor
final class ModelBrowserAccessibilityUITests: XCTestCase {
    func testInstalledModelSpokenActionsIncludePurposeAndDistinctModelIdentity() {
        let app = launchModels(largestText: false)
        defer { app.terminate() }
        var spoken: Set<String> = []
        for name in ["alpha", "beta"] {
            guard minutesTap(minutesElement("models.open.ui-model-\(name)", in: app), in: app) else { return }
            for id in ["models.equip.ui-model-\(name)", "models.remove.ui-model-\(name)"] {
                let button = app.buttons[id]
                minutesReveal(button, in: app)
                XCTAssertTrue(button.exists)
                XCTAssertTrue(button.label.localizedCaseInsensitiveContains("summary"))
                XCTAssertTrue(button.label.contains("example/ui-model-\(name)"))
                XCTAssertTrue(spoken.insert(button.label).inserted)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertEqual(spoken.count, 4)
    }

    func testInstalledModelActionsRemainReachableWith44PointTargetsAtLargestAccessibilityText() {
        let app = launchModels(largestText: true)
        defer { app.terminate() }
        for name in ["alpha", "beta"] {
            guard minutesTap(minutesElement("models.open.ui-model-\(name)", in: app), in: app) else { return }
            for id in ["models.equip.ui-model-\(name)", "models.remove.ui-model-\(name)"] {
                let button = app.buttons[id]
                minutesReveal(button, in: app)
                XCTAssertTrue(button.exists); XCTAssertTrue(button.isEnabled); XCTAssertTrue(button.isHittable)
                XCTAssertGreaterThanOrEqual(button.frame.width, 44)
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
                XCTAssertTrue(app.frame.contains(button.frame))
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    private func launchModels(largestText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_AX5"] = largestText ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.navigationBars["Summary model"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["ui.fixture.models.failure"].exists)
        return app
    }
}
