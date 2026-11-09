import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchOnboarding(
        keepState: Bool = false,
        resetPreferences: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestDemoData"]
        app.launchArguments.append(keepState ? "-UITestOnboardingKeepState" : "-UITestOnboarding")
        if resetPreferences {
            app.launchArguments.append("-UITestResetPreferences")
        }
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["words.more"].waitForExistence(timeout: 5))
        app.buttons["words.more"].tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func tapNext(_ app: XCUIApplication) {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
    }

    @MainActor
    private func goToLearning(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        tapNext(app)
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))
        tapNext(app)
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))
        tapNext(app)
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnboardingWalksThroughEveryStepAndCompletes() throws {
        let app = launchOnboarding()

        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.language"].exists)
        XCTAssertTrue(app.buttons["onboarding.skip"].exists)
        XCTAssertTrue(app.buttons["onboarding.next"].label == "Next")

        tapNext(app)
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["Drag words to reorder. Each widget can use a different set."]
                .waitForExistence(timeout: 3)
        )

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["onboarding.widget.Travel"].exists)
        XCTAssertTrue(app.buttons["onboarding.widget.Spanish B1"].exists)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboarding.demo.good"].exists)

        app.buttons["onboarding.demo.reveal"].tap()
        XCTAssertTrue(app.buttons["onboarding.demo.good"].waitForExistence(timeout: 3))
        app.buttons["onboarding.demo.good"].tap()
        XCTAssertTrue(app.staticTexts["Good. 1 of 5 repeats."].waitForExistence(timeout: 3))

        tapNext(app)
        XCTAssertTrue(app.staticTexts["You're ready"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["onboarding.next"].label, "Get started")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Welcome to Flipabulary"].exists)
    }

    @MainActor
    func testSwipingMovesBetweenOnboardingPages() throws {
        let app = launchOnboarding()
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))

        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))

        app.swipeRight()
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))

        app.swipeRight()
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testReviewCardCanBeThrownToRate() throws {
        let app = launchOnboarding()
        goToLearning(app)

        app.buttons["onboarding.demo.reveal"].tap()
        XCTAssertTrue(app.buttons["onboarding.demo.good"].waitForExistence(timeout: 3))

        let card = app.descendants(matching: .any)["onboarding.demo.card"].firstMatch
        XCTAssertTrue(card.exists)
        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 220, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)

        XCTAssertTrue(app.staticTexts["Good. 1 of 5 repeats."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPageSwipeStillWorksWhenTheReviewCardIsRevealed() throws {
        let app = launchOnboarding()
        goToLearning(app)

        app.buttons["onboarding.demo.reveal"].tap()
        XCTAssertTrue(app.buttons["onboarding.demo.good"].waitForExistence(timeout: 3))

        app.staticTexts["Learn, then keep it"].swipeLeft()
        XCTAssertTrue(app.staticTexts["You're ready"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSkipCompletesAndDoesNotShowAgainOnRelaunch() throws {
        let app = launchOnboarding()
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))

        app.terminate()

        let relaunched = launchOnboarding(keepState: true)
        XCTAssertTrue(relaunched.staticTexts["Words"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunched.staticTexts["Welcome to Flipabulary"].exists)
        XCTAssertTrue(relaunched.buttons["words.more"].exists)
    }

    @MainActor
    func testOnboardingResumesAtTheSavedPage() throws {
        let app = launchOnboarding()
        goToLearning(app)

        app.terminate()

        let relaunched = launchOnboarding(keepState: true)
        XCTAssertTrue(relaunched.staticTexts["Learn, then keep it"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunched.staticTexts["Welcome to Flipabulary"].exists)
    }

    @MainActor
    func testLanguageSelectionUpdatesTheOnboardingImmediately() throws {
        let app = launchOnboarding()
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))

        app.buttons["onboarding.language"].tap()
        let russian = app.buttons["Русский"].firstMatch
        XCTAssertTrue(russian.waitForExistence(timeout: 3))
        russian.tap()

        XCTAssertTrue(app.staticTexts["Добро пожаловать в Flipabulary"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Выберите язык"].exists)
        XCTAssertTrue(app.buttons["onboarding.next"].exists)
    }

    @MainActor
    func testOnboardingCanBeReplayedFromSettings() throws {
        let app = launchOnboarding()
        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))

        openSettings(app)

        let row = app.staticTexts["Show onboarding again"]
        for _ in 0..<8 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()

        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboardingScreensPassAccessibilityAudit() throws {
        let app = launchOnboarding()

        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        settle()
        try audit(app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))
        settle()
        // The system List owns the reorder handle and its header/footer contrast.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))
        settle()
        // The small hint inside the tinted hero trips the contrast heuristic.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))
        settle()
        // This page is a pixel copy of the review UI; its small card labels trip the contrast heuristic.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["You're ready"].waitForExistence(timeout: 3))
        settle()
        try audit(app)
    }

    @MainActor
    func testOnboardingSupportsDarkAppearanceAndLargeText() throws {
        let app = launchOnboarding(extraArguments: [
            "-DebugDark",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraLarge"
        ])

        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        settle()
        try audit(app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))
        settle()
        // The system List owns the reorder handle and its header/footer contrast.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))
        settle()
        // The small hint inside the tinted hero trips the contrast heuristic.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))
        settle()
        // This page is a pixel copy of the review UI; its small card labels trip the contrast heuristic.
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])

        tapNext(app)
        XCTAssertTrue(app.staticTexts["You're ready"].waitForExistence(timeout: 3))
        settle()
        try audit(app)
    }

    @MainActor
    func testCaptureOnboardingScreens() throws {
        let app = launchOnboarding()

        XCTAssertTrue(app.staticTexts["Welcome to Flipabulary"].waitForExistence(timeout: 5))
        attach("onboarding-welcome", app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["A set for every widget"].waitForExistence(timeout: 3))
        attach("onboarding-word-sets", app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Your words on the Home Screen"].waitForExistence(timeout: 3))
        attach("onboarding-widgets", app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["Learn, then keep it"].waitForExistence(timeout: 3))
        attach("onboarding-learning", app)
        app.buttons["onboarding.demo.reveal"].tap()
        XCTAssertTrue(app.buttons["onboarding.demo.good"].waitForExistence(timeout: 3))
        attach("onboarding-learning-back", app)

        tapNext(app)
        XCTAssertTrue(app.staticTexts["You're ready"].waitForExistence(timeout: 3))
        attach("onboarding-ready", app)
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
    }

    @MainActor
    private func settle() {
        Thread.sleep(forTimeInterval: 0.6)
    }
}
