import XCTest

/// Real persisted 103-row fixture. No replacement history screen or model work.
@MainActor
final class HistoryPaginationUITests: XCTestCase {
    func testHistoryOffersExplicitNextPageAndExhaustsItsActualOlderRows() {
        let app = launchHistory()
        defer { app.terminate() }
        let more = app.buttons["meeting.history.loadMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5),
            "History must expose a reachable Load more meetings action for its remaining stored rows")
        guard more.exists else { return }
        reveal(more, in: app)
        XCTAssertEqual(more.label, "Load more meetings")
        XCTAssertTrue(more.isEnabled); XCTAssertTrue(more.isHittable)
        guard more.isEnabled && more.isHittable else { return }
        more.tap()
        let exhausted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: more)
        XCTAssertEqual(XCTWaiter.wait(for: [exhausted], timeout: 5), .completed,
            "After reading the final three rows, history must stop offering another page")
        searchForOlderMeeting(in: app)
    }

    func testHistoryTitleSearchFindsAndOpensAStoredMeetingBeyondTheInitialPage() {
        let app = launchHistory()
        defer { app.terminate() }
        searchForOlderMeeting(in: app)
    }

    private func launchHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "--ui-test-library-pagination",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launch()
        let meetings = app.tabBars.buttons["Meetings"]
        XCTAssertTrue(meetings.waitForExistence(timeout: 10))
        if meetings.exists { meetings.tap() }
        XCTAssertTrue(app.staticTexts["UI Library Alpha"].waitForExistence(timeout: 5))
        return app
    }

    private func searchForOlderMeeting(in app: XCUIApplication) {
        let search = app.searchFields["Search meeting titles"]
        for _ in 0..<3 {
            if search.exists && search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        guard search.exists else { return }
        reveal(search, in: app)
        XCTAssertTrue(search.isHittable)
        guard search.isHittable else { return }
        search.tap(); search.typeText("Earlier Archive Target")
        let older = app.staticTexts["UI Earlier Archive Target"]
        XCTAssertTrue(older.waitForExistence(timeout: 5),
            "Title search must query the full SQLite library, including meetings outside the first page")
        guard older.exists else { return }
        reveal(older, in: app)
        XCTAssertTrue(older.isHittable)
        guard older.isHittable else { return }
        older.tap()
        let title = app.textFields["Meeting name"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "UI Earlier Archive Target"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertTrue(app.textViews["Original meeting notes"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let window = app.frame
            var top = window.minY + 8, bottom = window.maxY - 8
            // Search fields belong to the navigation bar itself. Other rows
            // must fit below it and above tabs/keyboard before tapping.
            if element.elementType != .searchField {
                for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
                    if bar.frame.intersects(window) { top = max(top, bar.frame.maxY + 8) }
                }
            }
            for bar in app.tabBars.allElementsBoundByIndex where bar.exists {
                if bar.frame.intersects(window) { bottom = min(bottom, bar.frame.minY - 8) }
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && keyboard.frame.intersects(window) { bottom = min(bottom, keyboard.frame.minY - 8) }
            guard bottom > top else { return }
            let viewport = CGRect(x: window.minX + 8, y: top, width: max(0, window.width - 16), height: bottom - top)
            var upward = true
            var distance = min(140, viewport.height * 0.4)
            if element.exists && !element.frame.isEmpty {
                if viewport.contains(element.frame) && element.isHittable { return }
                if element.frame.minY < viewport.minY {
                    upward = false; distance = min(distance, max(30, viewport.minY - element.frame.minY + 12))
                } else if element.frame.maxY > viewport.maxY {
                    distance = min(distance, max(30, element.frame.maxY - viewport.maxY + 12))
                }
            }
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = viewport.maxX - window.minX - 2
            origin.withOffset(CGVector(dx: x, dy: startY - window.minY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: startY - window.minY + (upward ? -distance : distance))))
        }
    }
}
