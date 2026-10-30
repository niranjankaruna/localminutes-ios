import XCTest

/// Actual Models UI and owned persistent SQLite/CAF fixture. This observes a
/// simulator metadata report, never physical file protection or a share send.
@MainActor
final class StoragePrivacyReportUITests: XCTestCase {
    func testModelsPrepareStorageCheckReportsActualSimulatorCountsAndOffersExplicitShare() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-library-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LOCALMINUTES_UI_LIBRARY_TOKEN"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }

        let models = app.tabBars.buttons["Settings"]
        XCTAssertTrue(models.waitForExistence(timeout: 10),
            "The existing fixture must initialize actual app services before inspecting their owned storage")
        guard models.exists else { return }
        models.tap()
        guard minutesTap(minutesElement("settings.about", in: app), in: app),
              minutesTap(minutesElement("settings.storage", in: app), in: app) else { return }
        XCTAssertTrue(app.navigationBars["Storage check"].waitForExistence(timeout: 5))

        let prepare = app.buttons["settings.storageAudit.prepare"]
        reveal(prepare, in: app)
        XCTAssertTrue(prepare.waitForExistence(timeout: 5), "Models must expose Prepare storage check")
        guard prepare.exists else { return }
        XCTAssertEqual(prepare.label, "Prepare storage check")
        XCTAssertTrue(prepare.isEnabled)
        XCTAssertTrue(prepare.isHittable)
        guard prepare.isEnabled && prepare.isHittable else { return }
        prepare.tap()

        let ready = app.staticTexts["settings.storageAudit.ready"]
        reveal(ready, in: app)
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        XCTAssertEqual(ready.label, "Storage check ready")
        let environment = app.staticTexts["settings.storageAudit.environment"]
        reveal(environment, in: app)
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        XCTAssertEqual(environment.label, "Environment: iOS Simulator",
            "Simulator observations must never be presented as physical iPhone protection evidence")
        assertPositiveCount("settings.storageAudit.itemCount", prefix: "Inspected items: ", in: app)
        assertPositiveCount("settings.storageAudit.groupCount", prefix: "Metadata groups: ", in: app)

        let share = app.buttons["settings.storageAudit.share"]
        reveal(share, in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 5), "Preparing the report must offer Share storage check")
        guard share.exists else { return }
        XCTAssertEqual(share.label, "Share storage check")
        XCTAssertTrue(share.isEnabled)
        XCTAssertTrue(share.isHittable)
        // Do not tap: external sharing remains an explicit owner action.
    }

    private func assertPositiveCount(_ identifier: String, prefix: String, in app: XCUIApplication) {
        let count = app.staticTexts[identifier]
        reveal(count, in: app)
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        guard count.exists else { return }
        XCTAssertTrue(count.label.hasPrefix(prefix))
        let value = Int(count.label.dropFirst(prefix.count))
        XCTAssertGreaterThan(value ?? 0, 0, "The actual fixture root must produce nonempty metadata counts")
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
            var upward = true
            var distance = min(140, viewport.height * 0.4)
            if element.exists && !element.frame.isEmpty {
                let frame = element.frame
                if viewport.contains(frame) && element.isHittable { return }
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
            let dragX = viewport.maxX - window.minX - 2
            let start = origin.withOffset(CGVector(dx: dragX, dy: startY - window.minY))
            let end = origin.withOffset(CGVector(dx: dragX, dy: endY - window.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
}
