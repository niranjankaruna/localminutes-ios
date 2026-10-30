import XCTest
import UIKit

@MainActor
final class AppScreenshotsUITests: XCTestCase {
    func testSelectedScreens() async throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        let selection = try captureSelection()
        let total = selection.scenes.count * selection.appearances.count
        print("APPUI_SELECTION \(total) screenshots")
        var index = 0
        for appearance in selection.appearances {
            for name in selection.scenes {
                guard let scene = AppScreenshotScene(rawValue: name) else { throw CaptureError.notReady("Unknown scene: \(name)") }
                index += 1
                let progress = "[\(index)/\(total)] \(name)_\(appearance)"
                let app = XCUIApplication()
                print("APPUI_CAPTURE_BEGIN \(progress)")
                do {
                    try await capture(scene, appearance: appearance, app: app)
                    print("APPUI_CAPTURE_SAVED \(progress)")
                } catch {
                    print("APPUI_FAILURE \(progress): \(error)")
                    print(app.debugDescription)
                    let diagnostic = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    diagnostic.name = "diagnostic__\(appearance)__\(name)__"
                    diagnostic.lifetime = .keepAlways
                    add(diagnostic)
                    XCTFail("\(progress): \(error)")
                }
                app.terminate()
            }
        }
    }

    private struct CaptureSelection: Decodable {
        let appearances: [String]
        let scenes: [String]
    }

    private func captureSelection() throws -> CaptureSelection {
        guard let json = ProcessInfo.processInfo.environment["LOCALMINUTES_SCREENSHOT_SELECTION"] else {
            return .init(appearances: ["light", "dark"], scenes: AppScreenshotScene.allCases.map(\.rawValue))
        }
        let result = try JSONDecoder().decode(CaptureSelection.self, from: Data(json.utf8))
        guard !result.scenes.isEmpty, !result.appearances.isEmpty,
              Set(result.scenes).count == result.scenes.count,
              Set(result.appearances).count == result.appearances.count,
              result.scenes.allSatisfy({ AppScreenshotScene(rawValue: $0) != nil }),
              result.appearances.allSatisfy({ ["light", "dark"].contains($0) }) else {
            throw CaptureError.notReady("Invalid screenshot selection")
        }
        return result
    }

    private func capture(_ scene: AppScreenshotScene, appearance: String, app: XCUIApplication) async throws {
        app.launchArguments = [scene.usesModelFixture ? "--ui-test-model-accessibility" : "--ui-test-library-fixture",
                               "--ui-screenshots", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launchEnvironment["LOCALMINUTES_UI_APPEARANCE"] = appearance
        app.launchEnvironment["LOCALMINUTES_SCREENSHOT_SCENE"] = scene.rawValue
        if scene == .recordPermissionPrompt { app.resetAuthorizationStatus(for: .microphone) }
        app.launch()
        guard element("screenshot.ready.\(scene.rawValue)", in: app).waitForExistence(timeout: 40) else {
            throw CaptureError.notReady("The app did not prepare the scene")
        }

        for action in scene.actions { try await perform(action, in: app) }
        let spec = scene.specification
        if let title = spec.alertTitle {
            guard app.alerts[title].waitForExistence(timeout: 10) else {
                throw CaptureError.notReady("Missing confirmation: \(title)")
            }
        }
        if spec.keyboard == true, !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            throw CaptureError.notReady("The expected keyboard is missing")
        }
        try await reveal(spec.required, scene: scene, in: app)

        // A hittable element may still be partly covered by navigation, a tab bar,
        // the keyboard or another sheet. Verify every required frame, and wait for
        // three stable layout samples before taking the image and its receipt.
        var previous: [CGRect] = []
        var stable = 0
        var checks: [[String: Any]] = []
        for _ in 0..<30 {
            checks = try checkedElements(scene, in: app)
            let frames = spec.required.map { element($0, in: app).frame }
            if frames.count == previous.count && zip(frames, previous).allSatisfy({ near($0.0, $0.1) }) {
                stable += 1
            } else { stable = 1 }
            previous = frames
            if stable >= 3 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard stable >= 3 else { throw CaptureError.notReady("Layout did not settle") }
        if scene != .recordPermissionPrompt && element("localminutes.privacy.cover", in: app).exists {
            throw CaptureError.notReady("Privacy cover is visible")
        }
        if let title = spec.alertTitle {
            let alert = app.alerts[title]
            guard alert.staticTexts[title].exists, alert.buttons["Cancel"].isHittable,
                  app.frame.contains(alert.frame) else {
                throw CaptureError.notReady("Confirmation title, Cancel, or full dialog is not visible")
            }
        }
        if scene == .recordPermissionPrompt {
            let prompt = element("system.microphonePrompt", in: app)
            guard prompt.exists, prompt.staticTexts.allElementsBoundByIndex.contains(where: {
                $0.label.localizedCaseInsensitiveContains("microphone")
            }), prompt.buttons.count >= 2 else {
                throw CaptureError.notReady("The native microphone permission prompt is missing")
            }
        }
        if [.modelsSpeechVariants, .modelsSummaryVariants].contains(scene) {
            try validateDownloadButton(in: app)
        }

        let screenshot = XCUIScreen.main.screenshot()
        guard let pixels = screenshot.image.cgImage else { throw CaptureError.notReady("Missing screenshot pixels") }
        let proof: [String: Any] = [
            "schemaVersion": 1, "scene": scene.rawValue, "appearance": appearance,
            "presentation": spec.presentation, "window": rect(app.frame), "viewport": rect(viewport(in: app)),
            "chromeBounds": regions(in: app).chrome.map { rect($0) },
            "pixelWidth": pixels.width, "pixelHeight": pixels.height,
            "stableSamples": stable, "checks": checks, "alertTitle": spec.alertTitle ?? "",
            "keyboardVisible": app.keyboards.firstMatch.exists,
            "contract": ["required": spec.required, "presentation": spec.presentation,
                         "alertTitle": spec.alertTitle ?? "", "keyboard": spec.keyboard == true,
                         "expectedText": spec.expectedText ?? [:]]
        ]
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "appui__\(appearance)__\(scene.rawValue)__"
        attachment.lifetime = .keepAlways
        add(attachment)
        let evidence = XCTAttachment(data: try JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]),
                                     uniformTypeIdentifier: "public.json")
        evidence.name = "appui_validation__\(appearance)__\(scene.rawValue)__"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    private func perform(_ action: String, in app: XCUIApplication) async throws {
        switch action {
        case "@historyDelete":
            let row = element("meeting.history.row.10000000-0000-0000-0000-000000000001", in: app)
            try await reveal([row.identifier], scene: nil, in: app)
            row.press(forDuration: 1)
            let delete = app.buttons["Delete meeting"].firstMatch
            guard delete.waitForExistence(timeout: 5), delete.isHittable else {
                throw CaptureError.notReady("History deletion menu did not open")
            }
            delete.tap()
        case "@composeQuestion":
            let field = element("meeting.qa.question", in: app)
            guard field.waitForExistence(timeout: 10), field.isHittable else {
                throw CaptureError.notReady("Question composer is unavailable")
            }
            field.tap()
            field.typeText("What did we agree to review on Friday?")
        case "@markdown":
            let markdown = app.segmentedControls["meeting.export.format"].buttons["Markdown"]
            guard markdown.waitForExistence(timeout: 10), markdown.isHittable else {
                throw CaptureError.notReady("Export format picker is unavailable")
            }
            markdown.tap()
        default:
            try await reveal([action], scene: nil, in: app)
            let control = element(action, in: app)
            guard control.isHittable, control.isEnabled else { throw CaptureError.notReady("Action is unavailable: \(action)") }
            control.tap()
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        if identifier == "system.cancel" { return app.alerts.firstMatch.buttons["Cancel"] }
        if identifier == "system.done" { return app.navigationBars.buttons["Done"].firstMatch }
        if identifier == "system.filePicker" {
            return app.navigationBars.matching(NSPredicate(format:
                "identifier == %@ OR identifier == %@ OR label == %@ OR label == %@", "Recents", "Browse", "Recents", "Browse")).firstMatch
        }
        if identifier == "system.shareSheet" {
            return app.otherElements["ActivityListView"].cells.matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        }
        if identifier == "system.microphonePrompt" {
            if app.alerts.firstMatch.exists { return app.alerts.firstMatch }
            return XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        }
        let pieces = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        if pieces.count == 2 {
            let query: XCUIElementQuery
            switch pieces[0] {
            case "buttonPrefix": query = app.buttons
            case "textPrefix": query = app.staticTexts
            case "text": return app.staticTexts[pieces[1]].firstMatch
            default: query = app.descendants(matching: .any)
            }
            return query.matching(NSPredicate(format: "identifier BEGINSWITH %@", pieces[1])).firstMatch
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func navigationBars(in app: XCUIApplication) -> [XCUIElement] {
        // The presented navigation stack is last in the accessibility hierarchy.
        // Its only button may be disabled while an edit conflict is displayed.
        let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
        return bars.last.map { [$0] } ?? []
    }

    private func regions(in app: XCUIApplication) -> (content: CGRect, chrome: [CGRect]) {
        let window = app.frame
        let bars = navigationBars(in: app)
        var chrome = bars.map(\.frame)
        var top = bars.map { $0.frame.maxY }.max() ?? window.minY
        var bottom = window.maxY - 8
        for bar in app.tabBars.allElementsBoundByIndex where bar.exists &&
            bar.buttons.allElementsBoundByIndex.contains(where: { $0.isHittable }) {
            bottom = min(bottom, bar.frame.minY)
        }
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
        let meetingTabs = element("meeting.content.tabs", in: app)
        if meetingTabs.exists, meetingTabs.isHittable {
            let frame = CGRect(x: window.minX, y: meetingTabs.frame.minY - 8, width: window.width,
                               height: meetingTabs.frame.height + 16)
            chrome.append(frame); top = max(top, frame.maxY)
        }
        let stop = element("recording.stop", in: app)
        let timer = element("recording.elapsed", in: app)
        if stop.exists, stop.isHittable, timer.exists {
            let tabs = element("recording.content.tabs", in: app)
            let start = min(stop.frame.minY, timer.frame.minY) - 8
            let end = max(stop.frame.maxY, tabs.exists ? tabs.frame.maxY : timer.frame.maxY) + 8
            let frame = CGRect(x: window.minX, y: start, width: window.width, height: end - start)
            chrome.append(frame); top = max(top, frame.maxY)
        }
        let composer = element("meeting.qa.question", in: app)
        if composer.exists, composer.isHittable || !composer.isEnabled {
            let end = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : window.maxY
            let frame = CGRect(x: window.minX, y: composer.frame.minY - 12, width: window.width,
                               height: end - composer.frame.minY + 12)
            if frame.height > 0 { chrome.append(frame); bottom = min(bottom, frame.minY) }
        }
        top = min(top, bottom)
        return (CGRect(x: window.minX, y: top, width: window.width, height: max(0, bottom - top)), chrome)
    }

    private func viewport(in app: XCUIApplication) -> CGRect { regions(in: app).content }

    private func allowedBounds(for item: XCUIElement, scene: AppScreenshotScene?, in app: XCUIApplication) -> (CGRect, String) {
        if let scene, ["confirmation", "menu", "systemSheet", "systemPermission", "hostedActivity", "hostedLaunch"].contains(scene.specification.presentation) {
            return (app.frame, "overlay")
        }
        if let frame = regions(in: app).chrome.first(where: { $0.contains(item.frame) }) {
            return (frame, "navigation")
        }
        // Menus and confirmation actions during a multi-step journey have no scene
        // argument yet. They must be visible but are not scrollable page content.
        if scene == nil && (app.alerts.firstMatch.exists || app.menus.firstMatch.exists) {
            return (app.frame, "overlay")
        }
        return (viewport(in: app), "content")
    }

    private func reveal(_ identifiers: [String], scene: AppScreenshotScene?, in app: XCUIApplication) async throws {
        for attempt in 0..<24 {
            let items = identifiers.map { element($0, in: app) }
            if items.allSatisfy({ item in
                let bounds = allowedBounds(for: item, scene: scene, in: app).0
                return item.exists && !item.frame.isEmpty && bounds.contains(item.frame)
                    && (item.isHittable || !item.isEnabled || scene == .recordPermissionPrompt)
            }) { return }
            if let scene, ["confirmation", "menu", "systemSheet", "systemPermission"].contains(scene.specification.presentation) {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            if attempt < 4 && items.contains(where: { !$0.exists }) {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            let bounds = viewport(in: app)
            let containers = (app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex)
                .filter { $0.exists && $0.isHittable && $0.frame.intersects(bounds) && $0.frame.height > 80 }
            guard let container = containers.max(by: { $0.frame.height < $1.frame.height }), bounds.height > 80 else {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }
            let frames = items.filter {
                $0.exists && !$0.frame.isEmpty && allowedBounds(for: $0, scene: scene, in: app).1 == "content"
            }.map(\.frame)
            let hasMissing = items.contains(where: { !$0.exists })
            let firstY = frames.map(\.minY).min() ?? bounds.minY
            let lastY = frames.map(\.maxY).max() ?? bounds.maxY
            if !hasMissing, lastY - firstY > bounds.height + 1 {
                throw CaptureError.notReady("Required content cannot fit in one viewport; split this scene into sections")
            }
            let upward = hasMissing || lastY > bounds.maxY || firstY >= bounds.minY
            let overflow = upward ? lastY - bounds.maxY : bounds.minY - firstY
            // Move only enough to clear the measured overlap. Fixed large swipes
            // can oscillate between clipping the top and bottom of a valid group.
            let distance = min(140, min(bounds.height * 0.3, hasMissing ? 140 : max(16, overflow + 8)))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let dragX = min(bounds.maxX - 12, container.frame.maxX - 12)
            let startY = bounds.midY + (upward ? distance / 2 : -distance / 2)
            origin.withOffset(CGVector(dx: dragX - app.frame.minX, dy: startY - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
                    dx: dragX - app.frame.minX, dy: startY - app.frame.minY + (upward ? -distance : distance))))
            try await Task.sleep(for: .milliseconds(200))
        }
        throw CaptureError.notReady("Required content is missing or clipped: \(identifiers.joined(separator: ", "))")
    }

    private func checkedElements(_ scene: AppScreenshotScene, in app: XCUIApplication) throws -> [[String: Any]] {
        try scene.specification.required.map { identifier in
            let item = element(identifier, in: app)
            let (bounds, region) = allowedBounds(for: item, scene: scene, in: app)
            guard item.exists, !item.frame.isEmpty, bounds.contains(item.frame),
                  item.isHittable || !item.isEnabled || scene == .recordPermissionPrompt else {
                throw CaptureError.notReady("Required content is obscured: \(identifier)")
            }
            let value = item.value as? String ?? ""
            if let expected = scene.specification.expectedText?[identifier],
               !(item.label + " " + value).localizedCaseInsensitiveContains(expected) {
                throw CaptureError.notReady("Incorrect state for \(identifier): expected \(expected)")
            }
            return ["identifier": identifier, "frame": rect(item.frame), "region": region,
                    "label": item.label, "value": value, "enabled": item.isEnabled]
        }
    }

    private func validateDownloadButton(in app: XCUIApplication) throws {
        let button = element("buttonPrefix:models.download.", in: app)
        let label = element("textPrefix:models.download.label.", in: app)
        guard label.label == "Download", label.isHittable, button.frame.contains(label.frame),
              button.frame.width >= 44, button.frame.height >= 44, button.frame.height <= 80 else {
            throw CaptureError.notReady("Download must show its title in a compact, unclipped button")
        }
    }

    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 &&
            abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
    private func rect(_ value: CGRect) -> [Double] {
        [Double(value.minX), Double(value.minY), Double(value.width), Double(value.height)]
    }
    private enum CaptureError: Error { case notReady(String) }
}
