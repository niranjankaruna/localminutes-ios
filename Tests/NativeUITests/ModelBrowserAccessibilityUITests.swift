import XCTest

/// Actual product accessibility tree and hit regions, using two real verified
/// synthetic installations. No network, model evaluation or VoiceOver audio claim.
@MainActor
final class ModelBrowserAccessibilityUITests: XCTestCase {
    func testInstalledModelSpokenActionsIncludePurposeAndDistinctModelIdentity() {
        let app = launchModels(largestText: false)
        defer { app.terminate() }
        var spokenLabels: Set<String> = []
        for repository in ["example/ui-model-alpha", "example/ui-model-beta"] {
            guard let row = installedRow(repository, in: app) else { continue }
            for action in ["Equip", "Remove"] {
                let button = row.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", action)).firstMatch
                XCTAssertTrue(button.exists, "The actual installed row must expose its \(action) action")
                guard button.exists else { continue }
                XCTAssertTrue(button.label.localizedCaseInsensitiveContains("summary"),
                    "VoiceOver must announce the model purpose for \(action), not a bare repeated verb")
                XCTAssertTrue(button.label.localizedCaseInsensitiveContains(repository),
                    "VoiceOver must identify which installed model \(action) affects")
                XCTAssertTrue(spokenLabels.insert(button.label).inserted,
                    "Installed model actions must have distinct spoken labels")
            }
        }
        XCTAssertEqual(spokenLabels.count, 4, "Both installed models need distinguishable Equip and Remove actions")
    }

    func testInstalledModelActionsRemainReachableWith44PointTargetsAtLargestAccessibilityText() {
        let app = launchModels(largestText: true)
        defer { app.terminate() }
        for repository in ["example/ui-model-alpha", "example/ui-model-beta"] {
            guard let row = installedRow(repository, in: app) else { continue }
            for action in ["Equip", "Remove"] {
                let button = row.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", action)).firstMatch
                reveal(button, in: app)
                XCTAssertTrue(button.exists, "Largest accessibility text must retain \(action) for \(repository)")
                guard button.exists else { continue }
                XCTAssertTrue(button.isEnabled)
                XCTAssertTrue(button.isHittable, "Scrolling must reveal the complete actionable control at AX5")
                XCTAssertGreaterThanOrEqual(button.frame.width, 44, "\(action) needs a 44-point touch width")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44, "\(action) needs a 44-point touch height")
                XCTAssertTrue(app.frame.contains(button.frame), "\(action) must fit on screen after scrolling at AX5")
            }
        }
    }

    private func launchModels(largestText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_AX5"] = largestText ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 10),
            "The DEBUG fixture must install both synthetic manifests and show the actual ModelBrowserView")
        XCTAssertFalse(app.staticTexts["ui.fixture.models.failure"].exists)
        return app
    }

    private func installedRow(_ repository: String, in app: XCUIApplication) -> XCUIElement? {
        let row = app.cells.containing(.staticText, identifier: repository).firstMatch
        reveal(row, in: app)
        XCTAssertTrue(row.exists, "The actual Form must contain installed model \(repository)")
        return row.exists ? row : nil
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
}
