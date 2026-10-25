import XCTest

/// Existing real Beta SQLite fixture, without changing its seed or running a
/// model. Observe actual answer-edit controls, explicit Save and relaunch.
@MainActor
final class AnswerEditingUITests: XCTestCase {
    func testSavedAnswerEditorExplicitSaveNavigationAndRelaunchPreserveOnlyItsDisplayCopy() {
        let token = UUID()
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = token.uuidString
        app.launch()
        defer { app.terminate() }
        guard openHistory(app), openMeeting("UI Library Beta", in: app) else { return }
        let editor = app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.editor.")).firstMatch
        reveal(editor, in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "A saved answer must expose a real editable display copy")
        guard editor.exists else { return }
        waitForValue("Seeded Beta private answer.", element: editor)
        editor.tap(); editor.typeText(" User-reviewed UI answer edit.")
        guard let edited = editor.value as? String else { XCTFail("Edited answer needs a readable value"); return }
        XCTAssertTrue(edited.contains("User-reviewed UI answer edit."))
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.save.")).firstMatch
        reveal(save, in: app)
        XCTAssertTrue(save.exists); XCTAssertTrue(save.isEnabled)
        guard save.exists && save.isEnabled else { return }
        save.tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.saved.")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "Explicit Save must acknowledge its durable answer edit")
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Alpha", in: app) else { return }
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.editor.")).firstMatch.exists,
            "Alpha cannot show Beta's saved answer or editor")
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Beta", in: app) else { return }
        reveal(editor, in: app); waitForValue(edited, element: editor)
        app.terminate(); app.launch()
        guard openHistory(app), openMeeting("UI Library Beta", in: app) else { return }
        reveal(editor, in: app); waitForValue(edited, element: editor)
        let notes = app.textViews["Original meeting notes"]
        reveal(notes, in: app); waitForValue("Original Beta manual note.", element: notes)
        let original = app.staticTexts["Beta shared-term original transcript."]
        reveal(original, in: app)
        XCTAssertTrue(original.exists, "Editing generated display text must preserve the original transcript")
    }

    private func openHistory(_ app: XCUIApplication) -> Bool {
        let history = app.tabBars.buttons["Meetings"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        guard history.exists else { return false }
        history.tap()
        let loaded = app.staticTexts["UI Library Beta"].waitForExistence(timeout: 5)
        XCTAssertTrue(loaded, "The actual persisted Beta fixture must load before answer-edit assertions")
        return loaded
    }

    private func openMeeting(_ title: String, in app: XCUIApplication) -> Bool {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        guard row.exists else { return false }
        row.tap()
        let name = app.textFields["Meeting name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        return name.exists
    }

    private func waitForValue(_ value: String, element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let window = app.frame
            var top = window.minY + 8, bottom = window.maxY - 8
            for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) {
                top = max(top, bar.frame.maxY + 8)
            }
            for bar in app.tabBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) {
                bottom = min(bottom, bar.frame.minY - 8)
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && keyboard.frame.intersects(window) { bottom = min(bottom, keyboard.frame.minY - 8) }
            guard bottom > top else { return }
            let viewport = CGRect(x: window.minX + 8, y: top, width: max(0, window.width - 16), height: bottom - top)
            if element.exists && !element.frame.isEmpty && viewport.contains(element.frame) && element.isHittable { return }
            let upward = !element.exists || element.frame.minY >= viewport.minY
            let distance = min(120, viewport.height * 0.4)
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.maxX - window.minX - 2, dy: startY - window.minY))
            let end = origin.withOffset(CGVector(dx: viewport.maxX - window.minX - 2,
                dy: startY + (upward ? -distance : distance) - window.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
}
