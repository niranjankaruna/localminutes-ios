import XCTest

@MainActor
final class AppScreenshotsUITests: XCTestCase {
    func testLightScreens() { captureScenes(appearance: "light") }
    func testDarkScreens() { captureScenes(appearance: "dark") }

    private func captureScenes(appearance: String) {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        for scene in AppScreenshotScene.allCases {
            XCTContext.runActivity(named: "\(scene.rawValue)_\(appearance)") { _ in
                let app = XCUIApplication()
                defer { app.terminate() }
                do {
                    try capture(scene, appearance: appearance, app: app)
                } catch {
                    print("APPUI_FAILURE \(scene.rawValue)_\(appearance): \(error)")
                    print(app.debugDescription)
                    let diagnostic = XCTAttachment(screenshot: app.screenshot())
                    diagnostic.name = "diagnostic__\(appearance)__\(scene.rawValue)__"
                    diagnostic.lifetime = .keepAlways
                    add(diagnostic)
                    XCTFail("\(scene.rawValue)_\(appearance): \(error)")
                }
            }
        }
    }

    private func capture(_ scene: AppScreenshotScene, appearance: String, app: XCUIApplication) throws {
        print("APPUI_CAPTURE_BEGIN \(scene.rawValue)_\(appearance)")
        app.launchArguments = [scene.usesModelFixture ? "--ui-test-model-accessibility" : "--ui-test-library-fixture",
                               "--ui-screenshots", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launchEnvironment["LOCALMINUTES_UI_APPEARANCE"] = appearance
        app.launchEnvironment["LOCALMINUTES_SCREENSHOT_SCENE"] = scene.rawValue
        app.launch()
        let prepared = element("screenshot.ready.\(scene.rawValue)", in: app)
        guard prepared.waitForExistence(timeout: 40) else {
            throw CaptureError.notReady("App did not finish preparing this scene")
        }
        for identifier in scene.actions {
            let action = element(identifier, in: app)
            try waitUntilVisible(action, description: identifier)
            action.tap()
        }
        let target: XCUIElement
        switch scene.target {
        case "system.filePicker": target = app.buttons["Cancel"].firstMatch
        case "system.shareSheet": target = app.buttons["Copy"].firstMatch
        default: target = element(scene.target, in: app)
        }
        try waitUntilVisible(target, description: scene.target)
        if scene == .meetingNotes || scene == .recordNotes {
            let text = scene == .meetingNotes ? "Original Beta manual note." : "Original Alpha manual note."
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: target)
            guard XCTWaiter.wait(for: [loaded], timeout: 15) == .completed else {
                throw CaptureError.notReady("Original notes did not finish loading")
            }
        }
        guard !app.otherElements["localminutes.privacy.cover"].exists else {
            throw CaptureError.notReady("Privacy cover is visible")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "appui__\(appearance)__\(scene.rawValue)__"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("APPUI_CAPTURE_SAVED \(scene.rawValue)_\(appearance)")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    private func waitUntilVisible(_ element: XCUIElement, description: String) throws {
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        guard XCTWaiter.wait(for: [visible], timeout: 20) == .completed else {
            throw CaptureError.notReady("Expected visible element: \(description)")
        }
    }

    private enum CaptureError: Error { case notReady(String) }
}
