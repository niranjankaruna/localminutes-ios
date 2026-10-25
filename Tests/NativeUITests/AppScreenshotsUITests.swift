import XCTest

@MainActor
final class AppScreenshotsUITests: XCTestCase {
    private var appearance = "light"
    private var captured = Set<String>()
    private var runningApp: XCUIApplication?

    func testLightScreens() throws { try captureScreens(appearance: "light") }
    func testDarkScreens() throws { try captureScreens(appearance: "dark") }

    private func captureScreens(appearance: String) throws {
        continueAfterFailure = false
        defer { runningApp?.terminate() }
        self.appearance = appearance
        XCUIDevice.shared.orientation = .portrait

        var app = try launch(extra: ["--ui-test-library-empty"])
        try capture("record_idle", in: app, showing: app.buttons["recording.start"])
        app.buttons["recording.start"].tap()
        try capture("record_speech_model_required", in: app, showing: app.staticTexts["recording.modelRequired"])
        app.tabBars.buttons["Meetings"].tap()
        try capture("meetings_empty", in: app, showing: app.staticTexts["No meetings yet"])

        app = try launch()
        app.tabBars.buttons["Meetings"].tap()
        try capture("meetings_history", in: app, showing: app.staticTexts["UI Library Alpha"])
        app.buttons["Library actions"].tap()
        try capture("meetings_actions", in: app, showing: app.buttons["Create library backup"])
        app.buttons["Create library backup"].tap()
        try capture("meetings_backup_ready", in: app, showing: app.buttons["Save or share library backup"])
        app.buttons["Library actions"].tap()
        app.buttons["Restore library backup…"].tap()
        try capture("meetings_restore_picker", in: app, showing: app.buttons["Cancel"].firstMatch)

        app = try launch()
        app.tabBars.buttons["Meetings"].tap()
        let historySearch = app.searchFields["Search meeting titles"]
        try reveal(historySearch, in: app, initiallyDown: true)
        historySearch.tap()
        historySearch.typeText("Alpha")
        try capture("meetings_search", in: app, showing: app.staticTexts["UI Library Alpha"])

        app = try launch()
        try openMeeting("UI Library Beta", in: app)
        try capture("meeting_notes", in: app, showing: app.textViews["Original meeting notes"])
        try capture("meeting_transcript", in: app, showing: app.staticTexts["Beta separate-topic original transcript."])
        let transcriptSearch = app.textFields["Find in this transcript"]
        try reveal(transcriptSearch, in: app)
        transcriptSearch.tap()
        transcriptSearch.typeText("shared-term")
        try capture("meeting_transcript_search", in: app, showing: app.staticTexts["Beta shared-term original transcript."])

        app = try launch()
        try openMeeting("UI Library Beta", in: app)
        try capture("meeting_summary", in: app, showing: app.textViews["meeting.generatedSummary.editor"])
        let reset = app.buttons["Start a fresh summary…"]
        try reveal(reset, in: app)
        reset.tap()
        try capture("meeting_summary_reset_confirmation", in: app, showing: app.buttons["Discard progress and generate"])
        app.buttons["Cancel"].firstMatch.tap()
        try capture("meeting_questions_and_answers", in: app, showing: app.textViews["Saved answer"])
        try capture("meeting_export", in: app, showing: app.buttons["Share Markdown"])
        let share = app.buttons["Share text"]
        try reveal(share, in: app)
        share.tap()
        try wait(app.buttons["Copy"].firstMatch)
        try capture("meeting_share_sheet", in: app)

        app = try launch()
        try openMeeting("UI Library Alpha", in: app)
        let delete = app.buttons["Delete meeting"]
        try reveal(delete, in: app)
        delete.tap()
        try capture("meeting_delete_confirmation", in: app, showing: app.buttons["Delete meeting and all its data"])

        app = try launch(extra: ["--ui-test-library-content-status"])
        try openMeeting("UI Library Beta", in: app)
        try capture("meeting_no_transcript", in: app, showing: app.staticTexts["No finalized transcript is available."])
        try capture("meeting_no_summary", in: app, showing: app.buttons["meeting.generatedSummary.generate"])
        app.buttons["meeting.generatedSummary.generate"].tap()
        try capture("meeting_summary_model_required", in: app, showing: app.staticTexts["meeting.intelligence.modelRequired"])

        app = try launch()
        app.tabBars.buttons["Models"].tap()
        try capture("models_speech", in: app, showing: app.buttons["Browse Parakeet TDT v3"])
        app.segmentedControls.buttons["Summary"].tap()
        try capture("models_summary", in: app, showing: app.staticTexts["models.apple.availability"])
        let storage = app.buttons["settings.storageAudit.prepare"]
        try reveal(storage, in: app)
        storage.tap()
        try capture("models_storage_check", in: app, showing: app.buttons["settings.storageAudit.share"])
        try capture("models_about", in: app, showing: app.staticTexts["settings.appBuildIdentity"])
        try capture("models_device", in: app, showing: app.staticTexts["models.device.availableMemory"])

        app = try launch()
        app.tabBars.buttons["Models"].tap()
        try reveal(app.buttons["Browse Parakeet TDT v3"], in: app)
        app.buttons["Browse Parakeet TDT v3"].tap()
        try capture("models_parakeet_repository", in: app, showing: app.buttons["Source details"])
        app.buttons["Source details"].tap()
        try capture("models_parakeet_source", in: app, showing: app.staticTexts["Pinned revision"])
        try capture("models_parakeet_compatibility", in: app, showing: app.staticTexts["Engine compatibility"])
        try capture("models_parakeet_requirements", in: app, showing: app.staticTexts["Selected model requirements"])
        try capture("models_parakeet_download", in: app, showing: app.buttons["Download selected model"])
        let importModel = app.buttons["Import selected model from Files"]
        try reveal(importModel, in: app)
        importModel.tap()
        try capture("models_import_picker", in: app, showing: app.buttons["Cancel"].firstMatch)

        app = try launch()
        app.tabBars.buttons["Models"].tap()
        let pack = app.buttons["Open a model pack…"]
        try reveal(pack, in: app)
        pack.tap()
        try capture("models_pack_picker", in: app, showing: app.buttons["Cancel"].firstMatch)

        app = try launch(models: true)
        let installed = app.staticTexts["ui model alpha"].firstMatch
        try capture("models_installed_summary", in: app, showing: installed)
        let details = app.buttons["Model details"].firstMatch
        try reveal(details, in: app)
        details.tap()
        try capture("models_installed_details", in: app, showing: app.staticTexts["llama.cpp-b5046"].firstMatch)
        let remove = app.buttons["Remove summary model example/ui-model-alpha"]
        try reveal(remove, in: app)
        remove.tap()
        try capture("models_remove_confirmation", in: app, showing: app.buttons["Remove model"])

        app = try launch(models: true, progress: "downloading")
        try capture("models_downloading", in: app, showing: app.staticTexts["models.download.resumed"])
        app = try launch(models: true, progress: "verifying")
        try capture("models_verifying", in: app, showing: app.staticTexts["models.download.filename"])
        app = try launch(extra: ["--ui-screenshot-model-card"], models: true)
        let source = app.buttons["Source details"]
        try reveal(source, in: app)
        source.tap()
        let card = app.buttons["Read full model card"]
        try reveal(card, in: app)
        card.tap()
        try capture("models_model_card", in: app, showing: app.navigationBars["Model card"])

        app = try launch(extra: ["--ui-screenshot-recording"])
        try capture("record_active", in: app, showing: app.staticTexts["recording.elapsed"])
        try capture("record_live_transcript", in: app,
                    showing: app.staticTexts["We agreed to review the updated meeting experience on Friday."])
        try capture("record_live_notes", in: app, showing: app.textViews["Original meeting notes"])
    }

    private func launch(extra: [String] = [], models: Bool = false, progress: String = "idle") throws -> XCUIApplication {
        runningApp?.terminate()
        let app = XCUIApplication()
        app.launchArguments = [models ? "--ui-test-model-accessibility" : "--ui-test-library-fixture",
                               "--ui-screenshots", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launchEnvironment["LOCALMINUTES_UI_APPEARANCE"] = appearance
        app.launchEnvironment["LOCALMINUTES_UI_MODEL_PROGRESS"] = progress
        runningApp = app
        app.launch()
        if models { try wait(app.navigationBars["Models"]) }
        else { try wait(app.tabBars.buttons["Meetings"]) }
        return app
    }

    private func openMeeting(_ title: String, in app: XCUIApplication) throws {
        app.tabBars.buttons["Meetings"].tap()
        let meeting = app.staticTexts[title].firstMatch
        try wait(meeting)
        meeting.tap()
        let titleField = app.textFields["Meeting name"]
        try wait(titleField)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: titleField)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        try wait(app.textViews["Original meeting notes"])
    }

    private func wait(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 20) else {
            XCTFail("Screenshot destination did not appear: \(element)")
            throw CaptureError.missingScreen
        }
    }

    private func capture(_ name: String, in app: XCUIApplication, showing element: XCUIElement? = nil) throws {
        if let element { try reveal(element, in: app) }
        XCTAssertTrue(captured.insert(name).inserted, "Screenshot names must be unique")
        XCTAssertFalse(app.otherElements["localminutes.privacy.cover"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "appui__\(appearance)__\(name)__"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, initiallyDown: Bool = false) throws {
        for _ in 0..<45 {
            let window = app.frame
            var top = window.minY + 8
            var bottom = window.maxY - 8
            for bar in app.navigationBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) {
                top = max(top, bar.frame.maxY + 8)
            }
            for bar in app.tabBars.allElementsBoundByIndex where bar.exists && bar.frame.intersects(window) {
                bottom = min(bottom, bar.frame.minY - 8)
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            let viewport = CGRect(x: window.minX + 8, y: top, width: window.width - 16, height: bottom - top)
            // Navigation bars and sheets are not inside the scrolling content viewport.
            if element.exists && element.isHittable &&
                (viewport.contains(element.frame) || element.elementType == .navigationBar ||
                 app.sheets.firstMatch.exists || app.buttons["Cancel"].firstMatch.exists) { return }
            var upward = !initiallyDown
            var distance = min(160, viewport.height * 0.4)
            if element.exists && !element.frame.isEmpty {
                if element.frame.minY < viewport.minY {
                    upward = false
                    distance = min(distance, max(30, viewport.minY - element.frame.minY + 12))
                } else if element.frame.maxY > viewport.maxY {
                    upward = true
                    distance = min(distance, max(30, element.frame.maxY - viewport.maxY + 12))
                }
            }
            let startY = viewport.midY + (upward ? distance / 2 : -distance / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: window.width - 10, dy: startY - window.minY))
            let end = origin.withOffset(CGVector(dx: window.width - 10, dy: startY - window.minY + (upward ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Could not reveal screenshot content: \(element)")
        throw CaptureError.missingScreen
    }

    private enum CaptureError: Error { case missingScreen }
}
