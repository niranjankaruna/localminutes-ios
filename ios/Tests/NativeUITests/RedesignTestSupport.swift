import XCTest

@MainActor
extension XCTestCase {
    func minutesLibraryApp(token: UUID = UUID(), arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = token.uuidString
        return app
    }

    func minutesElement(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    func minutesTap(_ element: XCUIElement, in app: XCUIApplication,
                    file: StaticString = #filePath, line: UInt = #line) -> Bool {
        minutesReveal(element, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 8), file: file, line: line)
        guard element.exists else { return false }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        guard element.isHittable else { return false }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, file: file, line: line)
        guard element.isEnabled else { return false }
        element.tap()
        return true
    }

    func minutesHistoryRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "meeting.history.row.", title)).firstMatch
    }

    @discardableResult
    func minutesOpenMeeting(_ title: String, in app: XCUIApplication) -> Bool {
        guard minutesTap(minutesHistoryRow(title, in: app), in: app) else { return false }
        let heading = app.staticTexts["meeting.title"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: heading)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        return heading.exists
    }

    @discardableResult
    func minutesSelect(_ section: String, in app: XCUIApplication) -> Bool {
        minutesTap(app.segmentedControls["meeting.content.tabs"].buttons[section], in: app)
    }

    func minutesWaitForValue(_ value: String, _ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", value, value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    func minutesReveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            let window = app.frame
            if element.exists && element.isHittable,
               app.navigationBars.allElementsBoundByIndex.contains(where: { $0.exists && $0.frame.contains(element.frame) }) { return }
            var top = window.minY + 8, bottom = window.maxY - 8
            if element.elementType != .searchField {
                for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) {
                    top = max(top, bar.frame.maxY + 8)
                }
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
            let distance = min(140, viewport.height * 0.4)
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.maxX - window.minX - 2, dy: startY - window.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: viewport.maxX - window.minX - 2, dy: startY - window.minY + (upward ? -distance : distance))))
        }
    }
}
