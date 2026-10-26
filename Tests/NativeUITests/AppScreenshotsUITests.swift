import XCTest

@MainActor
final class AppScreenshotsUITests: XCTestCase {
    func testSelectedScreens() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let selection = try captureSelection()
        let total = selection.scenes.count * selection.appearances.count
        print("APPUI_SELECTION \(total) screenshots: \(selection.appearances.joined(separator: ",")); \(selection.scenes.joined(separator: ","))")
        var startedSceneCount = 0
        for appearance in selection.appearances {
            for name in selection.scenes {
                guard let scene = AppScreenshotScene(rawValue: name) else {
                    throw CaptureError.notReady("Unknown screenshot scene: \(name)")
                }
                startedSceneCount += 1
                captureScene(scene, appearance: appearance, progress: "[\(startedSceneCount)/\(total)]")
            }
        }
    }

    private struct CaptureSelection: Decodable {
        let appearances: [String]
        let scenes: [String]
    }

    private func captureSelection() throws -> CaptureSelection {
        guard let json = ProcessInfo.processInfo.environment["LOCALMINUTES_SCREENSHOT_SELECTION"] else {
            return CaptureSelection(appearances: ["light", "dark"], scenes: AppScreenshotScene.allCases.map(\.rawValue))
        }
        let selection = try JSONDecoder().decode(CaptureSelection.self, from: Data(json.utf8))
        guard !selection.scenes.isEmpty, !selection.appearances.isEmpty,
              Set(selection.scenes).count == selection.scenes.count,
              Set(selection.appearances).count == selection.appearances.count,
              selection.scenes.allSatisfy({ AppScreenshotScene(rawValue: $0) != nil }),
              selection.appearances.allSatisfy({ ["light", "dark"].contains($0) }) else {
            throw CaptureError.notReady("Invalid screenshot selection")
        }
        return selection
    }

    private func captureScene(_ scene: AppScreenshotScene, appearance: String, progress: String) {
        let progress = "\(progress) \(scene.rawValue)_\(appearance)"
        XCTContext.runActivity(named: "Screenshot \(progress)") { _ in
            print("APPUI_CAPTURE_BEGIN \(progress)")
            let app = XCUIApplication()
            defer { app.terminate() }
            do {
                try capture(scene, appearance: appearance, app: app)
                print("APPUI_CAPTURE_SAVED \(progress)")
            } catch {
                print("APPUI_FAILURE \(progress): \(error)")
                print(app.debugDescription)
                let diagnostic = XCTAttachment(screenshot: app.screenshot())
                diagnostic.name = "diagnostic__\(appearance)__\(scene.rawValue)__"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
                XCTFail("\(progress): \(error)")
            }
        }
    }

    private func capture(_ scene: AppScreenshotScene, appearance: String, app: XCUIApplication) throws {
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
        switch scene {
        case .meetingsEmpty:
            target = app.staticTexts.matching(identifier: scene.target)
                .matching(NSPredicate(format: "label == %@", "No meetings yet")).firstMatch
        case .meetingTranscript, .meetingTranscriptSearch:
            target = app.staticTexts[scene.target]
        case .meetingsRestore, .modelsImport, .modelsPack:
            target = app.buttons["Cancel"].firstMatch
        case .meetingShare:
            target = app.otherElements["ActivityListView"].cells
                .matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
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
