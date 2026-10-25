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
        for _ in 0..<20 {
            let window = app.frame
            var top = window.minY + 8
            var bottom = window.maxY - 8
            for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
                if bar.frame.intersects(window) { top = max(top, bar.frame.maxY + 8) }
            }
            for bar in app.tabBars.allElementsBoundByIndex where bar.exists {
                if bar.frame.intersects(window) { bottom = min(bottom, bar.frame.minY - 8) }
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && keyboard.frame.intersects(window) {
                bottom = min(bottom, keyboard.frame.minY - 8)
            }
            guard bottom > top else { return }
            let viewport = CGRect(x: window.minX + 8, y: top,
                                  width: max(0, window.width - 16), height: bottom - top)
            // A large accessibility cell may exceed the entire screen. Reveal
            // its heading for row lookup; individual controls still require
            // their complete frames before the unchanged tap/assertions.
            let target: XCUIElement
            if element.exists && element.elementType == .cell && element.staticTexts.firstMatch.exists {
                target = element.staticTexts.firstMatch
            } else {
                target = element
            }
            var upward = true
            var distance = min(140, viewport.height * 0.4)
            if target.exists && !target.frame.isEmpty {
                let frame = target.frame
                if viewport.contains(frame) && target.isHittable { return }
                if frame.minY < viewport.minY {
                    upward = false
                    distance = min(distance, max(30, viewport.minY - frame.minY + 12))
                } else if frame.maxY > viewport.maxY {
                    distance = min(distance, max(30, frame.maxY - viewport.maxY + 12))
                }
            }
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let endY = startY + (upward ? -distance : distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Drag along the list gutter rather than inside a note TextEditor.
            let dragX = viewport.maxX - window.minX - 2
            let start = origin.withOffset(CGVector(dx: dragX, dy: startY - window.minY))
            let end = origin.withOffset(CGVector(dx: dragX, dy: endY - window.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
}
