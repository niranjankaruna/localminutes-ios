import XCTest

/// The 103-row fixture exercises actual SQLite pagination and title search.
@MainActor
final class HistoryPaginationUITests: XCTestCase {
    func testHistoryOffersExplicitNextPageAndExhaustsItsActualOlderRows() {
        let app = launchHistory()
        defer { app.terminate() }
        guard minutesTap(app.buttons["meeting.history.actions"], in: app),
              minutesTap(app.buttons["meeting.history.loadMore.menu"], in: app) else { return }
        guard minutesTap(app.buttons["meeting.history.actions"], in: app) else { return }
        XCTAssertFalse(app.buttons["meeting.history.loadMore.menu"].exists,
            "The menu must stop offering another page after the last three rows are loaded.")
        app.navigationBars["Meetings"].tap()
        searchForOlderMeeting(in: app)
    }

    func testHistoryTitleSearchFindsAndOpensAStoredMeetingBeyondTheInitialPage() {
        let app = launchHistory()
        defer { app.terminate() }
        searchForOlderMeeting(in: app)
    }

    private func launchHistory() -> XCUIApplication {
        let app = minutesLibraryApp(arguments: ["--ui-test-library-pagination"])
        app.launch()
        XCTAssertTrue(minutesHistoryRow("UI Library Alpha", in: app).waitForExistence(timeout: 10))
        return app
    }

    private func searchForOlderMeeting(in app: XCUIApplication) {
        let search = app.searchFields["Search meeting titles"]
        guard minutesTap(search, in: app) else { return }
        search.typeText("Earlier Archive Target")
        guard minutesOpenMeeting("UI Earlier Archive Target", in: app) else { return }
        XCTAssertEqual(app.staticTexts["meeting.title"].label, "UI Earlier Archive Target")
        guard minutesSelect("Notes", in: app) else { return }
        XCTAssertTrue(app.staticTexts["meeting.notes.content"].exists)
    }
}
