import XCTest
@testable import flipabulary

@MainActor
final class PreferencesAndRoutingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "preferences.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testPreferencesRoundTripAndReconcileMissingScopes() {
        let store = PreferencesStore(defaults: defaults)
        let stackID = UUID()
        var prefs = store.preferences
        prefs.appearance = .dark
        prefs.selectedStackID = stackID
        prefs.widgetDefaults.stackID = stackID
        prefs.reminders.stackID = stackID
        prefs.reminders.enabled = true
        prefs.rules.correctThreshold = 9
        prefs.language = .german
        store.preferences = prefs

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.appearance, .dark)
        XCTAssertEqual(reloaded.preferences.selectedStackID, stackID)
        XCTAssertEqual(reloaded.preferences.rules.correctThreshold, 9)
        XCTAssertTrue(reloaded.preferences.reminders.enabled)
        XCTAssertEqual(reloaded.preferences.language, .german)

        reloaded.reconcile(validStackIDs: [])
        XCTAssertNil(reloaded.preferences.selectedStackID)
        XCTAssertNil(reloaded.preferences.widgetDefaults.stackID)
        XCTAssertNil(reloaded.preferences.reminders.stackID)
        XCTAssertEqual(reloaded.preferences.appearance, .dark)
    }

    func testCorruptPreferencesFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: PreferencesStore.storageKey)
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences, .default)
    }

    func testReminderWeekdayAndTimeText() {
        var prefs = ReminderPreferences.default
        prefs.weekdays = [2, 3, 4, 5, 6]
        XCTAssertEqual(prefs.weekdayText, "Mon, Tue, Wed, Thu, Fri")
        prefs.weekdays = Set(1...7)
        XCTAssertEqual(prefs.weekdayText, "Every day")
    }

    func testDeepLinkParsing() {
        let stack = UUID()
        let card = UUID()
        XCTAssertEqual(AppDestination.parse(AppLinks.words(stackID: stack)), .words(stackID: stack))
        XCTAssertEqual(AppDestination.parse(AppLinks.review(stackID: stack)), .review(stackID: stack))
        XCTAssertEqual(AppDestination.parse(AppLinks.card(id: card)), .card(id: card))
        XCTAssertEqual(AppDestination.parse(URL(string: "flipabulary://settings")!), .settings)
        XCTAssertEqual(AppDestination.parse(URL(string: "flipabulary://widgets")!), .widgets)
        XCTAssertEqual(AppDestination.parse(URL(string: "flipabulary://reminders")!), .reminders)
        XCTAssertEqual(AppDestination.parse(URL(string: "flipabulary://card")!), .words(stackID: nil))
        XCTAssertNil(AppDestination.parse(URL(string: "https://example.com/review")!))
        XCTAssertNil(AppDestination.parse(URL(string: "flipabulary://unknown")!))
    }

    func testNotificationInboxConsumesAndMapsPayloads() {
        let inbox = NotificationInbox()
        let stack = UUID()
        inbox.receive(.review(stackID: stack))
        XCTAssertEqual(inbox.consume(), .review(stackID: stack))
        XCTAssertNil(inbox.consume())

        XCTAssertEqual(
            inbox.destination(from: ["route": "review", "stack": stack.uuidString]),
            .review(stackID: stack)
        )
        XCTAssertEqual(inbox.destination(from: ["route": "words", "test": true]), .words(stackID: nil))
        XCTAssertNil(inbox.destination(from: ["route": "other"]))
    }

    func testLayoutPolicyThresholds() {
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 320), .compact)
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 599.9), .compact)
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 600), .duo)
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 759.9), .duo)
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 760), .pad)
        XCTAssertEqual(AppMetrics.LayoutMode.resolve(width: 1_366), .pad)
        XCTAssertEqual(AppMetrics.maxWorkingWidth, 1_180)
        XCTAssertEqual(AppMetrics.LayoutMode.duo.leftWidth, 220)
        XCTAssertEqual(AppMetrics.LayoutMode.pad.leftWidth, 272)
    }
}

@MainActor
final class SupportViewModelTests: XCTestCase {
    private let displayPrices = ["$2.99", "$4.99", "$7.99", "$19.99", "$49.99", "$99.99"]

    private func products() -> [SupportProduct] {
        zip(SupportSlot.all, displayPrices).map { slot, price in
            SupportProduct(
                id: slot.productID,
                displayName: slot.title,
                displayPrice: price,
                amount: slot.amount
            )
        }
    }

    func testCatalogLoadSuccessAndSelection() async {
        let fake = FakeSupportPurchasing()
        fake.products = products()
        let model = SupportViewModel(purchasing: fake)
        await model.load()
        XCTAssertEqual(model.catalogState, .available)
        XCTAssertEqual(model.products.count, 6)
        XCTAssertEqual(model.slots.count, 6)
        XCTAssertTrue(model.canPurchase)
        XCTAssertEqual(model.selectedAmount, 5)
        XCTAssertEqual(model.selectedProduct?.id, "com.mrmaier.flipabulary.support.lunch")

        model.select(amount: 100)
        XCTAssertEqual(model.selectedAmount, 100)
        XCTAssertEqual(model.selectedProduct?.id, "com.mrmaier.flipabulary.support.legend")
        XCTAssertEqual(model.selectedProduct?.displayPrice, "$99.99")

        model.select(amount: 7)
        XCTAssertEqual(model.selectedAmount, 100)
    }

    func testCatalogUnavailableAndLoadFailure() async {
        let empty = FakeSupportPurchasing()
        let emptyModel = SupportViewModel(purchasing: empty)
        await emptyModel.load()
        if case .unavailable = emptyModel.catalogState {} else { XCTFail("Expected unavailable") }
        XCTAssertFalse(emptyModel.canPurchase)

        let failing = FakeSupportPurchasing()
        failing.loadError = SupportPurchaseError.failed("offline")
        let failingModel = SupportViewModel(purchasing: failing)
        await failingModel.load()
        if case .unavailable(let message) = failingModel.catalogState {
            XCTAssertTrue(message.contains("offline"))
        } else {
            XCTFail("Expected unavailable")
        }
    }

    func testPurchaseOutcomes() async {
        let fake = FakeSupportPurchasing()
        fake.products = products()
        let model = SupportViewModel(purchasing: fake)
        await model.load()

        fake.purchaseOutcome = .verified
        await model.purchase()
        if case .success = model.message {} else { XCTFail("Expected success") }
        XCTAssertEqual(fake.purchaseCalls.count, 1)

        fake.purchaseOutcome = .cancelled
        await model.purchase()
        if case .info(let message) = model.message { XCTAssertTrue(message.contains("cancelled")) } else { XCTFail("Expected info") }

        fake.purchaseOutcome = .pending
        await model.purchase()
        if case .info(let message) = model.message { XCTAssertTrue(message.contains("pending")) } else { XCTFail("Expected info") }

        fake.purchaseOutcome = .duplicate
        await model.purchase()
        if case .info(let message) = model.message { XCTAssertTrue(message.contains("already")) } else { XCTFail("Expected info") }

        fake.purchaseOutcome = .unverified
        await model.purchase()
        if case .failure(let message) = model.message { XCTAssertTrue(message.contains("verified")) } else { XCTFail("Expected failure") }

        fake.purchaseError = SupportPurchaseError.failed("declined")
        await model.purchase()
        if case .failure(let message) = model.message { XCTAssertTrue(message.contains("declined")) } else { XCTFail("Expected failure") }
    }

    func testAllSlotsAreOneTimeAndRepeatable() {
        XCTAssertEqual(SupportSlot.all.map(\.amount), [3, 5, 8, 20, 50, 100])
        XCTAssertEqual(Set(SupportSlot.all.map(\.productID)).count, 6)
        XCTAssertFalse(SupportSlot.all.contains(where: { $0.productID.contains("monthly") }))
    }
}
