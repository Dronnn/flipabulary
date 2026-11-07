import XCTest

final class FlipabularyVisualTests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemory", "-UITestDemoData", "-UITestResetPreferences",
            "-DebugSupportPreview",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        app.buttons["words.more"].tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.exists { button.tap() }
    }

    @MainActor
    func testCaptureReviewPresentation() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        attach("review-front", app)

        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        attach("review-back", app)
    }

    @MainActor
    func testCaptureDarkAppearance() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        openSettings(app)
        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        attach("settings", app)
        back(app)
        attach("words", app)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])

        app.buttons["words.add"].tap()
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))
        attach("editor", app)
        app.buttons["card.close"].tap()

        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        attach("review-front", app)
        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        attach("review-back", app)

        app.buttons["review.close"].tap()
        let end = app.sheets.buttons["End session"]
        if end.waitForExistence(timeout: 2) { end.tap() }
        if app.buttons["review.done"].exists {
            app.buttons["review.done"].tap()
        } else {
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.buttons["words.add"].waitForExistence(timeout: 5))

        openSettings(app)
        app.staticTexts["Stack settings"].tap()
        XCTAssertTrue(app.navigationBars["Stack"].waitForExistence(timeout: 3))
        attach("stack-settings", app)
        back(app)

        app.staticTexts["Learning rules"].tap()
        XCTAssertTrue(app.navigationBars["Learning rules"].waitForExistence(timeout: 3))
        attach("learning-rules", app)
        back(app)

        app.staticTexts["Widgets"].tap()
        XCTAssertTrue(app.navigationBars["List widget"].waitForExistence(timeout: 3))
        attach("widget-config", app)
        back(app)

        app.staticTexts["Support Flipabulary"].tap()
        XCTAssertTrue(app.navigationBars["Support"].waitForExistence(timeout: 5))
        attach("support", app)
        app.buttons["Close"].tap()
        back(app)
    }

    @MainActor
    func testCaptureLaunchOverlay() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemory", "-UITestDemoData", "-UITestResetPreferences",
            "-DebugShowLaunchOverlay", "-DebugHoldLaunchOverlay",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Flipabulary"].waitForExistence(timeout: 8))
        attach("launch", app)
    }

    @MainActor
    func testCaptureAppScreens() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        attach("words", app)

        app.buttons["words.add"].tap()
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))
        attach("editor", app)
        app.buttons["card.close"].tap()

        openSettings(app)
        attach("settings", app)

        app.staticTexts["Learning rules"].tap()
        XCTAssertTrue(app.navigationBars["Learning rules"].waitForExistence(timeout: 3))
        attach("learning-rules", app)
        back(app)

        app.staticTexts["Stack settings"].tap()
        XCTAssertTrue(app.navigationBars["Stack"].waitForExistence(timeout: 3))
        attach("stack-settings", app)
        back(app)

        app.staticTexts["Widgets"].tap()
        XCTAssertTrue(app.navigationBars["List widget"].waitForExistence(timeout: 3))
        attach("widget-config", app)
        back(app)

        app.staticTexts["Import & Export"].tap()
        XCTAssertTrue(app.navigationBars["Import & Export"].waitForExistence(timeout: 3))
        attach("import-export", app)
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
        back(app)

        app.staticTexts["Local notifications that respect your review workload."].tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 3))
        attach("reminders", app)
        back(app)

        app.staticTexts["Support Flipabulary"].tap()
        XCTAssertTrue(app.navigationBars["Support"].waitForExistence(timeout: 5))
        attach("support", app)
        app.buttons["Close"].tap()

        back(app)
        app.buttons["words.more"].tap()
        app.buttons["Stacks"].tap()
        XCTAssertTrue(app.navigationBars["Stacks"].waitForExistence(timeout: 3))
        attach("stacks", app)
    }
}
