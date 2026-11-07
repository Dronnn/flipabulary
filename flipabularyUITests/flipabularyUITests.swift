import XCTest

final class FlipabularyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(
        demo: Bool = true,
        resetPreferences: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"]
        if demo { app.launchArguments.append("-UITestDemoData") }
        if resetPreferences { app.launchArguments.append("-UITestResetPreferences") }
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
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    func testEmptyStateAndAddWordFlow() throws {
        let app = launch(demo: false)
        XCTAssertTrue(app.staticTexts["Your word list is empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add your first word"].exists)

        app.buttons["words.add"].tap()
        let word = app.textFields["card.word"]
        let translation = app.textFields["card.translation"]
        XCTAssertTrue(word.waitForExistence(timeout: 3))
        word.tap()
        word.typeText("ephemeral")
        translation.tap()
        translation.typeText("мимолетный")
        app.buttons["card.save"].tap()

        XCTAssertTrue(app.staticTexts["ephemeral"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["мимолетный"].exists)
    }

    @MainActor
    func testValidationAndAddAnotherKeepsSheetOpen() throws {
        let app = launch(demo: false)
        app.buttons["words.add"].tap()
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))

        app.buttons["card.save"].tap()
        XCTAssertTrue(app.staticTexts["Enter a word."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Enter a translation."].exists)

        app.textFields["card.word"].tap()
        app.textFields["card.word"].typeText("mitigate")
        app.textFields["card.translation"].tap()
        app.textFields["card.translation"].typeText("смягчать")

        let addAnother = app.descendants(matching: .any)["card.addAnother"]
        XCTAssertTrue(addAnother.exists)
        addAnother.tap()
        app.buttons["card.save"].tap()

        XCTAssertTrue(app.staticTexts["Saved. Add another word."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["card.word"].exists)
        app.buttons["card.close"].tap()
    }

    @MainActor
    func testAddAnotherSavesEveryWord() throws {
        let app = launch(demo: false)
        app.buttons["words.add"].tap()
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))

        let addAnother = app.descendants(matching: .any)["card.addAnother"]
        XCTAssertTrue(addAnother.exists)
        addAnother.tap()

        for (word, translation) in [("alpha", "one"), ("beta", "two"), ("gamma", "three")] {
            app.textFields["card.word"].tap()
            app.textFields["card.word"].typeText(word)
            app.textFields["card.translation"].tap()
            app.textFields["card.translation"].typeText(translation)
            app.buttons["card.save"].tap()
            XCTAssertTrue(app.staticTexts["Saved. Add another word."].waitForExistence(timeout: 5))
            XCTAssertTrue(app.textFields["card.word"].exists)
        }

        app.buttons["card.close"].tap()
        XCTAssertTrue(app.staticTexts["alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["beta"].exists)
        XCTAssertTrue(app.staticTexts["gamma"].exists)
    }

    @MainActor
    func testImportExportScreenOpens() throws {
        let app = launch()
        app.buttons["words.more"].tap()
        let importExport = app.buttons["Import & Export"].firstMatch
        XCTAssertTrue(importExport.waitForExistence(timeout: 3))
        importExport.tap()
        XCTAssertTrue(app.navigationBars["Import & Export"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["import.csv"].exists)
        XCTAssertTrue(app.buttons["import.anki"].exists)
        XCTAssertTrue(app.buttons["export.stack"].exists)
    }

    @MainActor
    func testSearchAndFiltersUpdateTheList() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ephemeral"].exists)

        let search = app.textFields["words.search"]
        search.tap()
        search.typeText("miti")
        XCTAssertTrue(app.staticTexts["mitigate"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["ephemeral"].exists)
        app.buttons["Clear search"].tap()

        app.buttons["words.filter.learned"].tap()
        XCTAssertTrue(app.staticTexts["ubiquitous"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["mitigate"].exists)

        app.buttons["words.more"].tap()
        let difficult = app.buttons["Difficult words"]
        XCTAssertTrue(difficult.waitForExistence(timeout: 3))
        difficult.tap()
        XCTAssertTrue(app.staticTexts["No words here"].waitForExistence(timeout: 3))
        app.buttons["Show all"].tap()
        XCTAssertTrue(app.staticTexts["ephemeral"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEditExistingCardPreservesIt() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["ephemeral"].waitForExistence(timeout: 5))
        app.staticTexts["ephemeral"].tap()

        let translation = app.textFields["card.translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 3))
        translation.tap()
        translation.typeText("-edited")
        app.buttons["card.save"].tap()

        let edited = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "-edited")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ephemeral"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewRevealRateEndAndSummary() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()

        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.good"].exists)
        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        app.buttons["review.good"].tap()

        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        app.buttons["review.end"].tap()
        let sheetEnd = app.sheets.buttons["End session"]
        if sheetEnd.waitForExistence(timeout: 3) {
            sheetEnd.tap()
        } else {
            let endButtons = app.buttons.matching(identifier: "End session")
            XCTAssertGreaterThan(endButtons.count, 0)
            endButtons.element(boundBy: endButtons.count - 1).tap()
        }

        XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reviewed"].exists)
        if app.buttons["review.done"].exists {
            app.buttons["review.done"].tap()
        } else {
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWordsScopeOpensStackPicker() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.due"].tap()
        XCTAssertTrue(app.navigationBars["Choose stack"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["words.scope.all"].waitForExistence(timeout: 3))
        app.buttons["words.scope.all"].tap()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTranslationFirstKeepsSourceHiddenUntilReveal() throws {
        let app = launch()
        openSettings(app)
        app.staticTexts["Stack settings"].tap()
        let toggle = app.descendants(matching: .any)["stack.translationFirst"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.tap()
        goBack(app)
        goBack(app)

        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        let reviewCard = app.descendants(matching: .any)["review.card"].firstMatch
        XCTAssertTrue(reviewCard.exists)
        XCTAssertTrue(reviewCard.label.contains("мимолетный"))
        XCTAssertFalse(reviewCard.label.contains("ephemeral"))
        app.buttons["review.reveal"].tap()
        XCTAssertTrue(reviewCard.label.contains("ephemeral"))
    }

    @MainActor
    func testAppearancePersistsAcrossRelaunch() throws {
        let app = launch()
        openSettings(app)
        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        app.terminate()

        let relaunched = launch(demo: false, resetPreferences: false)
        openSettings(relaunched)
        XCTAssertTrue(relaunched.buttons["settings.appearance.dark"].waitForExistence(timeout: 3))
        XCTAssertTrue(relaunched.buttons["settings.appearance.dark"].isSelected)
    }

    @MainActor
    func testWidgetConfigurationScreenAndToggle() throws {
        let app = launch()
        openSettings(app)
        app.staticTexts["Widgets"].tap()
        XCTAssertTrue(app.navigationBars["List widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["widget.preview"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["widget.source"].exists)
        let wordSets = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Word sets")).firstMatch
        XCTAssertTrue(wordSets.exists)
        XCTAssertTrue(app.buttons["widget.newSet"].exists)
    }

    @MainActor
    func testReminderScreenDefaultsAndPermissionPath() throws {
        let app = launch()
        openSettings(app)
        app.staticTexts["Local notifications that respect your review workload."].tap()
        XCTAssertTrue(app.navigationBars["Reminders"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS[c] 'Reminders are local notifications'"))
                .firstMatch.exists
        )

        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Don’t Allow", "Don't Allow", "Allow"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }

        let toggle = app.descendants(matching: .any)["reminders.enabled"]
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        app.tap()

        let blocked = app.staticTexts["Notifications are off in system settings"]
        let allowed = app.staticTexts["Allowed"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5) || allowed.exists)
    }

    @MainActor
    func testSupportScreenShowsCatalogOrHonestUnavailableState() throws {
        let app = launch()
        openSettings(app)
        app.staticTexts["Support Flipabulary"].tap()
        XCTAssertTrue(app.navigationBars["Support"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Support Flipabulary"].exists)

        let coffee = app.buttons["support.amount.3"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 5) || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'available'")).firstMatch.exists)
        if coffee.exists {
            coffee.tap()
            XCTAssertTrue(app.buttons["support.donate"].exists)
            XCTAssertTrue(app.buttons["support.amount.100"].exists)
        }
    }

    @MainActor
    func testStackCreationReachableFromMoreMenu() throws {
        let app = launch()
        app.buttons["words.more"].tap()
        app.buttons["Stacks"].tap()
        XCTAssertTrue(app.navigationBars["Stacks"].waitForExistence(timeout: 3))
        app.buttons["stacks.add"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Spanish B1")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Spanish B1"].waitForExistence(timeout: 3))
    }


    @MainActor
    func testCardFlipsRepeatedlyAndSwipesLeftToAgain() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))

        let initialLabel = app.descendants(matching: .any)["review.card"].firstMatch.label
        XCTAssertFalse(initialLabel.isEmpty)

        app.descendants(matching: .any)["review.card"].firstMatch.tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        XCTAssertNotEqual(app.descendants(matching: .any)["review.card"].firstMatch.label, initialLabel)

        app.descendants(matching: .any)["review.card"].firstMatch.tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["review.good"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["review.card"].firstMatch.label, initialLabel)

        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["review.card"].firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSwipeRightRatesGood() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["review.card"].firstMatch.swipeRight()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReviewSettingsKeepsTheRevealedCard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.due"].waitForExistence(timeout: 5))
        app.buttons["words.review"].tap()
        XCTAssertTrue(app.buttons["review.reveal"].waitForExistence(timeout: 5))
        app.buttons["review.reveal"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))

        app.buttons["review.settings"].tap()
        XCTAssertTrue(app.navigationBars["Session settings"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["review.good"].waitForExistence(timeout: 3))
        let card = app.descendants(matching: .any)["review.card"].firstMatch
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.label.contains("мимолетный") || card.label.contains("ephemeral"))
    }

    @MainActor
    func testDeleteWordRequiresConfirmationAndRemovesRow() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["ephemeral"].waitForExistence(timeout: 5))
        app.staticTexts["ephemeral"].tap()
        XCTAssertTrue(app.buttons["card.delete"].waitForExistence(timeout: 3))
        app.buttons["card.delete"].tap()
        let delete = app.alerts.buttons["Delete word"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ephemeral"].exists)
    }

    @MainActor
    func testRotationPreservesEditorDraft() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["words.add"].waitForExistence(timeout: 5))
        app.buttons["words.add"].tap()
        let word = app.textFields["card.word"]
        XCTAssertTrue(word.waitForExistence(timeout: 3))
        word.tap()
        word.typeText("rotate")

        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))
        XCTAssertEqual((app.textFields["card.word"].value as? String), "rotate")
        XCTAssertTrue(app.buttons["card.save"].exists)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))
        app.buttons["card.close"].tap()
        let discard = app.buttons["Discard draft"]
        if discard.waitForExistence(timeout: 2) { discard.tap() }
    }


    @MainActor
    func testLanguageSwitchingIsLive() throws {
        let app = launch()
        openSettings(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let language = app.descendants(matching: .any)["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 3))
        language.tap()
        XCTAssertTrue(app.buttons["Deutsch"].waitForExistence(timeout: 3))
        app.buttons["Deutsch"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        let germanAppearance = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Darstellung")).firstMatch
        XCTAssertTrue(germanAppearance.waitForExistence(timeout: 5))

        let germanLanguage = app.descendants(matching: .any)["settings.language"]
        XCTAssertTrue(germanLanguage.waitForExistence(timeout: 3))
        germanLanguage.tap()
        XCTAssertTrue(app.buttons["Español"].waitForExistence(timeout: 3))
        app.buttons["Español"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5))
        let spanishAppearance = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Apariencia")).firstMatch
        XCTAssertTrue(spanishAppearance.waitForExistence(timeout: 5))

        app.descendants(matching: .any)["settings.language"].tap()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 3))
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccessibilityAuditOnWords() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped])
    }

    @MainActor
    func testLargestAccessibilityTextKeepsActionsReachable() throws {
        let app = launch(
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        XCTAssertTrue(app.staticTexts["Words"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["words.add"].isHittable)
        XCTAssertTrue(app.buttons["words.review"].isHittable)
        app.buttons["words.add"].tap()
        XCTAssertTrue(app.textFields["card.word"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["card.save"].exists)
    }
}
