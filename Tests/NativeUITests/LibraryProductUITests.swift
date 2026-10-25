import XCTest

/// Simulator product flow only. The DEBUG hook seeds actual SQLite and
/// synthetic CAF/prior generated documents, never inference or a mock screen.
@MainActor
final class LibraryProductUITests: XCTestCase {
    func testActualHistoryDetailsAndTranscriptSearchStayWithinTheSelectedMeeting() {
        let app = libraryApp(token: UUID())
        app.launch()
        defer { app.terminate() }
        guard openMeetings(app) else { return }
        guard openMeeting("UI Library Alpha", in: app) else { return }
        let search = app.textFields["Find in this transcript"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        guard search.exists else { return }
        search.tap(); search.typeText("shared-term")
        XCTAssertTrue(app.staticTexts["Alpha shared-term original transcript."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Beta shared-term original transcript."].exists)
        XCTAssertFalse(app.staticTexts["Alpha separate-topic original transcript."].exists,
            "Search must actually filter the selected transcript rather than leave all rows visible")
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Beta", in: app) else { return }
        let secondSearch = app.textFields["Find in this transcript"]
        XCTAssertTrue(secondSearch.waitForExistence(timeout: 5))
        guard secondSearch.exists else { return }
        secondSearch.tap(); secondSearch.typeText("shared-term")
        XCTAssertTrue(app.staticTexts["Beta shared-term original transcript."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alpha shared-term original transcript."].exists)
        let note = app.textViews["Original meeting notes"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        waitForValue("Original Beta manual note.", of: note)
    }

    func testManualNoteNavigationAndRelaunchPreserveTheEditWithoutChangingAnotherMeeting() {
        let token = UUID()
        let app = libraryApp(token: token)
        app.launch()
        defer { app.terminate() }
        guard openMeetings(app), openMeeting("UI Library Alpha", in: app) else { return }
        let editor = app.textViews["Original meeting notes"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        guard editor.exists else { return }
        waitForValue("Original Alpha manual note.", of: editor)
        editor.tap()
        editor.typeText(" UI navigation edit preserved.")
        let expected = editor.value as? String
        XCTAssertTrue(expected?.contains("UI navigation edit preserved.") == true)
        XCTAssertNotEqual(expected, "Original Alpha manual note.")
        // Navigate immediately: the real editor must bind/flush its own meeting,
        // rather than relying on this test sleeping past a debounce timer.
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Beta", in: app) else { return }
        let otherEditor = app.textViews["Original meeting notes"]
        XCTAssertTrue(otherEditor.waitForExistence(timeout: 5))
        waitForValue("Original Beta manual note.", of: otherEditor)
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Alpha", in: app) else { return }
        guard let expected else { XCTFail("A typed edit must have a visible value"); return }
        waitForValue(expected, of: app.textViews["Original meeting notes"])
        app.terminate()
        // Same UUID-owned root; the hook must reopen, never reseed or wipe it.
        app.launch()
        guard openMeetings(app), openMeeting("UI Library Alpha", in: app) else { return }
        waitForValue(expected, of: app.textViews["Original meeting notes"])
        XCTAssertTrue(app.staticTexts["Alpha shared-term original transcript."].exists,
            "Editing notes must leave the original transcript available")
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Beta", in: app) else { return }
        waitForValue("Original Beta manual note.", of: app.textViews["Original meeting notes"])
    }

    func testEditableGeneratedSummaryAndAskMissingModelStaySeparateFromOriginalsAndOtherMeetings() {
        let app = libraryApp(token: UUID())
        app.launch()
        defer { app.terminate() }
        guard openMeetings(app), openMeeting("UI Library Alpha", in: app) else { return }
        waitForValue("Original Alpha manual note.", of: app.textViews["Original meeting notes"])
        let summary = app.textViews["meeting.generatedSummary.editor"]
        reveal(summary, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "Selected details needs a separate editable Summary section")
        guard summary.exists else { return }
        waitForValue("Seeded Alpha generated summary.", of: summary)
        summary.tap(); summary.typeText(" UI generated-summary edit.")
        let expectedSummary = summary.value as? String
        XCTAssertTrue(expectedSummary?.contains("UI generated-summary edit.") == true)
        XCTAssertTrue(app.buttons["meeting.generatedSummary.generate"].exists)
        let question = app.textFields["meeting.qa.question"]
        reveal(question, in: app)
        XCTAssertTrue(question.waitForExistence(timeout: 5), "Ask must be a real selected-meeting product action")
        guard question.exists else { return }
        question.tap(); question.typeText("What planning source was recorded?")
        let ask = app.buttons["meeting.qa.ask"]
        XCTAssertTrue(ask.exists); XCTAssertTrue(ask.isEnabled)
        guard ask.exists && ask.isEnabled else { return }
        ask.tap()
        let unavailable = app.staticTexts["meeting.intelligence.modelRequired"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertEqual(unavailable.label,
            "Download the summary model to summarize this meeting or ask questions.")
        XCTAssertFalse(app.staticTexts["meeting.qa.answer"].exists,
            "Missing real model must never manufacture an answer or display another meeting's saved answer")
        XCTAssertFalse(app.staticTexts["Seeded Beta private answer."].exists)
        XCTAssertFalse(app.progressIndicators["meeting.intelligence.running"].exists)
        let plain = app.buttons["meeting.export.text"]
        reveal(plain, in: app)
        XCTAssertTrue(plain.exists); XCTAssertTrue(plain.isEnabled)
        XCTAssertEqual(plain.label, "Share text")
        let markdown = app.buttons["meeting.export.markdown"]
        XCTAssertTrue(markdown.exists); XCTAssertTrue(markdown.isEnabled)
        XCTAssertEqual(markdown.label, "Share Markdown")
        XCTAssertTrue(app.staticTexts["Sharing sends the selected meeting to the app you choose."].exists)
        // Payload bytes and source isolation have independent real exporter
        // tests. This UI case observes the real controls, not an external send.
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Beta", in: app) else { return }
        waitForValue("Original Beta manual note.", of: app.textViews["Original meeting notes"])
        let otherSummary = app.textViews["meeting.generatedSummary.editor"]
        reveal(otherSummary, in: app)
        XCTAssertTrue(otherSummary.waitForExistence(timeout: 5))
        waitForValue("Seeded Beta generated summary.", of: otherSummary)
        app.navigationBars.buttons["Meetings"].tap()
        guard openMeeting("UI Library Alpha", in: app) else { return }
        waitForValue("Original Alpha manual note.", of: app.textViews["Original meeting notes"])
        if let expectedSummary {
            let restoredSummary = app.textViews["meeting.generatedSummary.editor"]
            reveal(restoredSummary, in: app)
            waitForValue(expectedSummary, of: restoredSummary)
        } else { XCTFail("Generated editor must retain a visible value") }
        app.tabBars.buttons["Models"].tap()
        // The owner replaced the legacy single-Qwen settings screen with the
        // repository browser and independent Equip choices. Preserve missing-
        // model semantics against that actual screen; do not make a network call.
        let summaryPurpose = app.segmentedControls.buttons["Summary"]
        XCTAssertTrue(summaryPurpose.waitForExistence(timeout: 5))
        guard summaryPurpose.exists else { return }
        summaryPurpose.tap()
        let missing = app.staticTexts["No verified model installed for this purpose."]
        reveal(missing, in: app)
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Equip")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Remove"].exists, "No installed model can be offered for removal")
        XCTAssertFalse(app.buttons["Download selected model"].exists,
            "Download requires an explicitly inspected compatible file; absent weights cannot be shown as ready")
        let repository = app.textFields["Hugging Face repository"]
        for _ in 0..<6 {
            if repository.exists && repository.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(repository.exists); XCTAssertTrue(repository.isHittable)
        guard repository.exists && repository.isHittable else { return }
        repository.tap(); repository.typeText("microsoft/Phi-3-mini-4k-instruct-gguf")
        XCTAssertTrue(app.buttons["Look up repository"].exists)
        XCTAssertTrue(app.buttons["Look up repository"].isEnabled,
            "The missing-model flow must expose the current Phi repository lookup without pretending to install it")
    }

    private func libraryApp(token: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = token.uuidString
        return app
    }

    private func openMeetings(_ app: XCUIApplication) -> Bool {
        let meetings = app.tabBars.buttons["Meetings"]
        XCTAssertTrue(meetings.waitForExistence(timeout: 8),
            "The DEBUG fixture must initialize real services and the actual product home view")
        guard meetings.exists else { return false }
        meetings.tap()
        XCTAssertTrue(app.staticTexts["UI Library Alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["UI Library Beta"].exists)
        let ready = app.staticTexts["UI Library Alpha"].exists && app.staticTexts["UI Library Beta"].exists
        if ready { print("LIBRARY_UI_REAL_FIXTURE_READY") }
        return ready
    }

    private func openMeeting(_ title: String, in app: XCUIApplication) -> Bool {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        guard row.exists else { return false }
        row.tap()
        let notes = app.textViews["Original meeting notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        waitForValue(title, of: app.textFields["Meeting name"])
        return notes.exists
    }

    private func waitForValue(_ value: String, of element: XCUIElement) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
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
