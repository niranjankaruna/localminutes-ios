import XCTest

/// Real verified synthetic installations. The redesigned list opens focused
/// details; selection/removal announce the family, variant and model purpose.
@MainActor
final class ModelBrowserAccessibilityUITests: XCTestCase {
    func testAttributionNoticeKeepsItsIdentifierAcrossDisclosureChangesInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-library-fixture", "--ui-screenshots",
                                   "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
            app.launchEnvironment["LOCALMINUTES_SCREENSHOT_SCENE"] = "models_model_card"
            app.launchEnvironment["LOCALMINUTES_UI_APPEARANCE"] = appearance
            app.launch(); defer { app.terminate() }
            XCTAssertTrue(minutesElement("screenshot.ready.models_model_card", in: app).waitForExistence(timeout: 40))

            let toggle = app.buttons["models.license.open"]
            let notice = app.staticTexts["models.license.notice"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            guard notice.waitForExistence(timeout: 5) else {
                XCTFail("The expanded attribution must keep its own identifier in \(appearance) mode.")
                continue
            }
            XCTAssertTrue(notice.isHittable)
            XCTAssertTrue(notice.label.contains("NVIDIA Parakeet TDT 0.6B v2"))
            let originalText = notice.label
            guard minutesTap(toggle, in: app) else { continue }
            let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
            XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
            guard minutesTap(toggle, in: app) else { continue }
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertEqual(notice.label, originalText)
            XCTAssertTrue(notice.isHittable)
        }
    }

    func testCatalogueOffersNamedFamiliesAndNoRepositoryLookupOrImport() {
        let app = launchModels(largestText: false)
        defer { app.terminate() }
        for family in ["qwen25", "qwen3", "phi3", "phi4", "gemma3", "gemma4"] {
            let heading = minutesElement("models.family.\(family)", in: app)
            minutesReveal(heading, in: app)
            XCTAssertTrue(heading.exists)
        }
        XCTAssertFalse(app.textFields["Hugging Face repository"].exists)
        XCTAssertFalse(app.buttons["Look up repository"].exists)
        XCTAssertFalse(minutesElement("models.repository.open", in: app).exists)
        XCTAssertFalse(app.buttons["models.import"].exists)
        XCTAssertFalse(app.buttons["models.pack.import"].exists)
    }

    func testRemovingOneDownloadedVariantReturnsItsDownloadActionAndPreservesTheOther() {
        let app = launchModels(largestText: false)
        defer { app.terminate() }
        guard minutesTap(minutesElement("models.family.qwen25", in: app), in: app),
              minutesTap(app.buttons["models.remove.ui-model-alpha"], in: app),
              minutesTap(app.buttons["models.remove.confirm"], in: app) else { return }
        XCTAssertTrue(app.buttons["models.download.ui-model-alpha"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["models.remove.ui-model-alpha"].exists)
        let other = app.buttons["models.equip.ui-model-beta"]
        minutesReveal(other, in: app)
        XCTAssertTrue(other.exists)
        XCTAssertTrue(app.buttons["models.remove.ui-model-beta"].exists)
    }

    func testSpeechCatalogueHasOnlyParakeetV2AndV3() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-model-accessibility"]
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_PURPOSE"] = "speech"
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Speech models"].waitForExistence(timeout: 15))
        for id in ["parakeet-v2", "parakeet-v3"] {
            let heading = minutesElement("models.family.\(id)", in: app)
            minutesReveal(heading, in: app)
            XCTAssertTrue(heading.exists)
        }
        XCTAssertFalse(minutesElement("models.repository.open", in: app).exists)
        XCTAssertFalse(app.buttons["models.pack.import"].exists)
    }

    func testInstalledModelSpokenActionsIncludePurposeAndDistinctModelIdentity() {
        let app = launchModels(largestText: false)
        defer { app.terminate() }
        guard minutesTap(minutesElement("models.family.qwen25", in: app), in: app) else { return }
        var spoken: Set<String> = []
        for name in ["alpha", "beta"] {
            guard minutesTap(minutesElement("models.open.ui-model-\(name)", in: app), in: app) else { return }
            for id in ["models.equip.ui-model-\(name)", "models.remove.ui-model-\(name)"] {
                let button = app.buttons[id]
                minutesReveal(button, in: app)
                XCTAssertTrue(button.exists)
                XCTAssertTrue(button.label.localizedCaseInsensitiveContains("summary"))
                XCTAssertTrue(button.label.contains("Qwen 2.5"))
                XCTAssertTrue(button.label.contains(name == "alpha" ? "0.5B" : "1.5B"))
                XCTAssertTrue(spoken.insert(button.label).inserted)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertEqual(spoken.count, 4)
    }

    func testInstalledModelActionsRemainReachableWith44PointTargetsAtLargestAccessibilityText() {
        let app = launchModels(largestText: true)
        defer { app.terminate() }
        guard minutesTap(minutesElement("models.family.qwen25", in: app), in: app) else { return }
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
        XCTAssertTrue(app.navigationBars["Summary & Q&A"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["ui.fixture.models.failure"].exists)
        return app
    }
}
