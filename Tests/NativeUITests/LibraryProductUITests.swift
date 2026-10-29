import XCTest

/// Real SQLite/CAF fixtures and actual product views. Navigation follows the
/// approved focused views; persistence and cross-meeting isolation remain real.
@MainActor
final class LibraryProductUITests: XCTestCase {
    func testDeleteSummaryCanBeCancelledAndConfirmedWithoutDeletingMeetingContent() {
        let app = minutesLibraryApp(token: UUID())
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        let summary = app.staticTexts["meeting.generatedSummary.content"]
        minutesWaitForValue("Seeded Beta generated summary.", summary)
        guard minutesTap(app.buttons["meeting.summary.options"], in: app),
              minutesTap(app.buttons["meeting.summary.delete"], in: app) else { return }
        XCTAssertTrue(app.buttons["meeting.summary.delete.confirm"].waitForExistence(timeout: 5))
        guard minutesTap(app.buttons["Cancel"].firstMatch, in: app) else { return }
        minutesWaitForValue("Seeded Beta generated summary.", summary)

        guard minutesTap(app.buttons["meeting.summary.options"], in: app),
              minutesTap(app.buttons["meeting.summary.delete"], in: app),
              minutesTap(app.buttons["meeting.summary.delete.confirm"], in: app) else { return }
        XCTAssertTrue(app.staticTexts["No summary yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(summary.exists)
        XCTAssertTrue(app.buttons["meeting.generatedSummary.generate"].exists)
        guard minutesSelect("Ask", in: app) else { return }
        XCTAssertTrue(app.staticTexts["Seeded Beta private answer."].waitForExistence(timeout: 5))
        guard minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue("Original Beta manual note.", app.staticTexts["meeting.notes.content"])
        guard minutesSelect("Transcript", in: app) else { return }
        XCTAssertTrue(app.staticTexts["Beta shared-term original transcript."].waitForExistence(timeout: 5))

        app.terminate(); app.launch()
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        XCTAssertTrue(app.staticTexts["No summary yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(summary.exists)
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Alpha", in: app) else { return }
        minutesWaitForValue("Seeded Alpha generated summary.", summary)
    }

    func testCitationOpensTheSelectedMeetingsTranscriptAndPlayback() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        let sources = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "meeting.sources.")).firstMatch
        guard minutesTap(sources, in: app) else { return }
        let citation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.citation.")).firstMatch
        guard minutesTap(citation, in: app) else { return }
        XCTAssertTrue(app.segmentedControls["meeting.content.tabs"].buttons["Transcript"].isSelected)
        XCTAssertTrue(app.staticTexts["Beta shared-term original transcript."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alpha shared-term original transcript."].exists)
        let stop = app.buttons["meeting.playback.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        if stop.exists { _ = minutesTap(stop, in: app) }
    }

    func testActualHistoryDetailsAndTranscriptSearchStayWithinTheSelectedMeeting() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Alpha", in: app), minutesSelect("Transcript", in: app) else { return }
        let search = app.textFields["meeting.transcript.search"]
        guard minutesTap(search, in: app) else { return }
        search.typeText("shared-term")
        XCTAssertTrue(app.staticTexts["Alpha shared-term original transcript."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Beta shared-term original transcript."].exists)
        XCTAssertFalse(app.staticTexts["Alpha separate-topic original transcript."].exists)
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Beta", in: app), minutesSelect("Transcript", in: app) else { return }
        guard minutesTap(search, in: app) else { return }
        search.typeText("shared-term")
        XCTAssertTrue(app.staticTexts["Beta shared-term original transcript."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Alpha shared-term original transcript."].exists)
        guard minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue("Original Beta manual note.", app.staticTexts["meeting.notes.content"])
    }

    func testManualNoteNavigationAndRelaunchPreserveTheEditWithoutChangingAnotherMeeting() {
        let app = minutesLibraryApp(token: UUID())
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Alpha", in: app), minutesSelect("Notes", in: app) else { return }
        guard minutesTap(app.buttons["meeting.notes.edit"], in: app) else { return }
        let editor = app.textViews["meeting.notes.editor"]
        minutesWaitForValue("Original Alpha manual note.", editor)
        editor.tap(); editor.typeText(" UI navigation edit preserved.")
        guard let expected = editor.value as? String else { XCTFail("Missing edited notes"); return }
        XCTAssertTrue(expected.contains("UI navigation edit preserved."))
        guard minutesTap(app.buttons["meeting.notes.done"], in: app) else { return }
        minutesWaitForValue(expected, app.staticTexts["meeting.notes.content"])
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Beta", in: app), minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue("Original Beta manual note.", app.staticTexts["meeting.notes.content"])
        app.terminate(); app.launch()
        guard minutesOpenMeeting("UI Library Alpha", in: app), minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue(expected, app.staticTexts["meeting.notes.content"])
        guard minutesSelect("Transcript", in: app) else { return }
        XCTAssertTrue(app.staticTexts["Alpha shared-term original transcript."].waitForExistence(timeout: 5))
    }

    func testEditableGeneratedSummaryAndAskMissingModelStaySeparateFromOriginalsAndOtherMeetings() {
        let app = minutesLibraryApp()
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Alpha", in: app) else { return }
        minutesWaitForValue("Seeded Alpha generated summary.", app.staticTexts["meeting.generatedSummary.content"])
        guard minutesTap(app.buttons["meeting.summary.edit"], in: app) else { return }
        let editor = app.textViews["meeting.generatedSummary.editor"]
        minutesWaitForValue("Seeded Alpha generated summary.", editor)
        editor.tap(); editor.typeText(" UI generated-summary edit.")
        guard let expected = editor.value as? String else { XCTFail("Missing summary edit"); return }
        guard minutesTap(app.buttons["meeting.summary.save"], in: app), minutesSelect("Ask", in: app) else { return }
        let question = app.textFields["meeting.qa.question"]
        guard minutesTap(question, in: app) else { return }
        question.typeText("What planning source was recorded?")
        guard minutesTap(app.buttons["meeting.qa.ask"], in: app) else { return }
        XCTAssertTrue(app.staticTexts["meeting.intelligence.modelRequired"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Seeded Beta private answer."].exists)
        XCTAssertFalse(app.progressIndicators["meeting.intelligence.running"].exists)
        guard minutesTap(app.buttons["meeting.export.open"], in: app) else { return }
        XCTAssertTrue(app.buttons["meeting.export.text"].waitForExistence(timeout: 5))
        guard minutesTap(app.segmentedControls["meeting.export.format"].buttons["Markdown"], in: app) else { return }
        XCTAssertTrue(app.buttons["meeting.export.markdown"].exists)
        // Inspect controls; never send an external share.
        app.navigationBars.buttons["Done"].tap()
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Beta", in: app) else { return }
        minutesWaitForValue("Seeded Beta generated summary.", app.staticTexts["meeting.generatedSummary.content"])
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Alpha", in: app) else { return }
        minutesWaitForValue(expected, app.staticTexts["meeting.generatedSummary.content"])
        guard minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue("Original Alpha manual note.", app.staticTexts["meeting.notes.content"])
        app.navigationBars.buttons["Meetings"].tap()
        app.tabBars.buttons["Settings"].tap()
        guard minutesTap(minutesElement("settings.models.summary", in: app), in: app) else { return }
        let family = minutesElement("models.family.qwen25", in: app)
        minutesReveal(family, in: app)
        XCTAssertTrue(family.exists)
        XCTAssertFalse(app.textFields["Hugging Face repository"].exists)
        XCTAssertFalse(minutesElement("models.repository.open", in: app).exists)
    }
}
