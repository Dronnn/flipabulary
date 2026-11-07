import XCTest
import StoreKit
import StoreKitTest
@testable import flipabulary

@MainActor
final class StoreKitConfigurationTests: XCTestCase {
    func testLocalStoreKitConfigurationLoadsAllSupportProducts() async throws {
        let session = try SKTestSession(configurationFileNamed: "Flipabulary")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let service = StoreKitSupportService()
        let products = try await service.loadProducts()
        XCTAssertEqual(products.count, 6)
        let ids = Set(products.map(\.id))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.coffee"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.lunch"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.bigfan"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.coffee.monthly"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.lunch.monthly"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.bigfan.monthly"))
        XCTAssertEqual(products.filter { $0.frequency == .monthly }.count, 3)
        XCTAssertEqual(products.filter { $0.frequency == .oneTime }.count, 3)
    }

    func testLocalConfigurationCanCreateAndVerifyATransaction() async throws {
        let session = try SKTestSession(configurationFileNamed: "Flipabulary")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let transaction = try await session.buyProduct(identifier: "com.mrmaier.flipabulary.support.coffee")
        XCTAssertEqual(transaction.productID, "com.mrmaier.flipabulary.support.coffee")
        XCTAssertEqual(transaction.productType, .consumable)
        await transaction.finish()

        let subscription = try await session.buyProduct(identifier: "com.mrmaier.flipabulary.support.lunch.monthly")
        XCTAssertEqual(subscription.productID, "com.mrmaier.flipabulary.support.lunch.monthly")
        XCTAssertEqual(subscription.productType, .autoRenewable)
        await subscription.finish()

        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let item) = result {
                active.insert(item.productID)
            }
        }
        XCTAssertTrue(active.contains("com.mrmaier.flipabulary.support.lunch.monthly"))
        XCTAssertFalse(active.contains("com.mrmaier.flipabulary.support.coffee"), "Consumables are not restorable entitlements")
    }
}
