import XCTest

@MainActor
final class AnswerEditingUITests: XCTestCase {
    func testSavedAnswerEditorExplicitSaveNavigationAndRelaunchPreserveOnlyItsDisplayCopy() {
        let app = minutesLibraryApp(token: UUID())
        app.launch(); defer { app.terminate() }
        guard minutesOpenMeeting("UI Library Beta", in: app), minutesSelect("Ask", in: app) else { return }
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.edit.")).firstMatch
        guard minutesTap(edit, in: app) else { return }
        let editor = app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.editor.")).firstMatch
        minutesWaitForValue("Seeded Beta private answer.", editor)
        editor.tap(); editor.typeText(" User-reviewed UI answer edit.")
        guard let expected = editor.value as? String else { XCTFail("Missing edited answer"); return }
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.save.")).firstMatch
        guard minutesTap(save, in: app) else { return }
        let content = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.content.")).firstMatch
        minutesWaitForValue(expected, content)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.saved.")).firstMatch.exists)
        app.navigationBars.buttons["Meetings"].tap()
        guard minutesOpenMeeting("UI Library Alpha", in: app), minutesSelect("Ask", in: app) else { return }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meeting.qa.answer.content.")).firstMatch.exists)
        app.terminate(); app.launch()
        guard minutesOpenMeeting("UI Library Beta", in: app), minutesSelect("Ask", in: app) else { return }
        minutesWaitForValue(expected, content)
        guard minutesSelect("Notes", in: app) else { return }
        minutesWaitForValue("Original Beta manual note.", app.staticTexts["meeting.notes.content"])
        guard minutesSelect("Transcript", in: app) else { return }
        XCTAssertTrue(app.staticTexts["Beta shared-term original transcript."].waitForExistence(timeout: 5))
    }
}
