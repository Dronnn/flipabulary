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
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.patron"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.champion"))
        XCTAssertTrue(ids.contains("com.mrmaier.flipabulary.support.legend"))
        XCTAssertEqual(products.map(\.displayPrice), ["$2.99", "$4.99", "$7.99", "$19.99", "$49.99", "$99.99"])
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

        let repeatPurchase = try await session.buyProduct(identifier: "com.mrmaier.flipabulary.support.coffee")
        XCTAssertEqual(repeatPurchase.productID, "com.mrmaier.flipabulary.support.coffee")
        XCTAssertEqual(repeatPurchase.productType, .consumable)
        await repeatPurchase.finish()

        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let item) = result {
                active.insert(item.productID)
            }
        }
        XCTAssertFalse(active.contains("com.mrmaier.flipabulary.support.coffee"), "Consumables are not restorable entitlements")
    }
}
