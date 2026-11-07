import Foundation
import Observation
import StoreKit

enum SupportFrequency: String, CaseIterable, Identifiable, Sendable {
    case oneTime
    case monthly

    var id: String { rawValue }
    var title: String { self == .oneTime ? "One-time" : "Monthly" }
}

struct SupportSlot: Identifiable, Hashable, Sendable {
    var amount: Int
    var title: String
    var subtitle: String
    var oneTimeProductID: String
    var monthlyProductID: String

    var id: Int { amount }

    static let all: [SupportSlot] = [
        SupportSlot(
            amount: 2,
            title: "Coffee",
            subtitle: "A small thank-you",
            oneTimeProductID: "com.mrmaier.flipabulary.support.coffee",
            monthlyProductID: "com.mrmaier.flipabulary.support.coffee.monthly"
        ),
        SupportSlot(
            amount: 5,
            title: "Lunch",
            subtitle: "Keeps the words coming",
            oneTimeProductID: "com.mrmaier.flipabulary.support.lunch",
            monthlyProductID: "com.mrmaier.flipabulary.support.lunch.monthly"
        ),
        SupportSlot(
            amount: 10,
            title: "Big fan",
            subtitle: "A generous boost",
            oneTimeProductID: "com.mrmaier.flipabulary.support.bigfan",
            monthlyProductID: "com.mrmaier.flipabulary.support.bigfan.monthly"
        )
    ]

    func productID(for frequency: SupportFrequency) -> String {
        frequency == .oneTime ? oneTimeProductID : monthlyProductID
    }
}

struct SupportProduct: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var displayPrice: String
    var frequency: SupportFrequency
    var amount: Int
}

enum SupportPurchaseOutcome: Sendable {
    case verified
    case unverified
    case duplicate
    case pending
    case cancelled
}

enum SupportRestoreOutcome: Sendable {
    case restored(Int)
    case nothingToRestore
}

enum SupportPurchaseError: Error, LocalizedError {
    case productUnavailable
    case failed(String)
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "This support option isn't available right now."
        case .failed(let message):
            return message
        case .unverified:
            return "The purchase could not be verified."
        }
    }
}

@MainActor
protocol SupportPurchasing: AnyObject {
    func loadProducts() async throws -> [SupportProduct]
    func purchase(productID: String) async throws -> SupportPurchaseOutcome
    func restore() async throws -> SupportRestoreOutcome
}

@MainActor
final class StoreKitSupportService: SupportPurchasing {
    private var loadedProducts: [String: Product] = [:]
    private let processedKey = "flipabulary.support.processedTransactions.v1"

    private var processedTransactionIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: processedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: processedKey) }
    }

    func loadProducts() async throws -> [SupportProduct] {
        let ids = SupportSlot.all.flatMap { [$0.oneTimeProductID, $0.monthlyProductID] }
        let products = try await Product.products(for: ids)
        loadedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        var result: [SupportProduct] = []
        for slot in SupportSlot.all {
            for frequency in SupportFrequency.allCases {
                let id = slot.productID(for: frequency)
                guard let product = loadedProducts[id] else { continue }
                result.append(
                    SupportProduct(
                        id: id,
                        displayName: slot.title,
                        displayPrice: product.displayPrice,
                        frequency: frequency,
                        amount: slot.amount
                    )
                )
            }
        }
        return result
    }

    func purchase(productID: String) async throws -> SupportPurchaseOutcome {
        guard let product = loadedProducts[productID] else {
            throw SupportPurchaseError.productUnavailable
        }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw SupportPurchaseError.failed(error.localizedDescription)
        }

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let key = String(transaction.id)
                var processed = processedTransactionIDs
                defer { processedTransactionIDs = processed }
                if processed.contains(key) {
                    await transaction.finish()
                    return .duplicate
                }
                processed.insert(key)
                await transaction.finish()
                return .verified
            case .unverified:
                throw SupportPurchaseError.unverified
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw SupportPurchaseError.failed("The App Store returned an unknown result.")
        }
    }

    func restore() async throws -> SupportRestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            throw SupportPurchaseError.failed(error.localizedDescription)
        }
        var restored = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productType == .autoRenewable {
                    restored.insert(transaction.productID)
                }
            }
        }
        return restored.isEmpty ? .nothingToRestore : .restored(restored.count)
    }
}

@MainActor
@Observable
final class SupportViewModel {
    enum CatalogState: Equatable {
        case loading
        case available
        case unavailable(String)
    }

    enum Message: Equatable {
        case success(String)
        case info(String)
        case failure(String)
    }

    private let purchasing: SupportPurchasing

    var catalogState: CatalogState = .loading
    var products: [SupportProduct] = []
    var frequency: SupportFrequency = .oneTime
    var selectedAmount = 5
    var customAmountText = ""
    var isPurchasing = false
    var isRestoring = false
    var message: Message?

    init(purchasing: SupportPurchasing) {
        self.purchasing = purchasing
    }

    var slots: [SupportSlot] { SupportSlot.all }

    func slot(amount: Int) -> SupportSlot? {
        slots.first(where: { $0.amount == amount })
    }

    func product(for slot: SupportSlot) -> SupportProduct? {
        products.first(where: { $0.id == slot.productID(for: frequency) })
    }

    var selectedProduct: SupportProduct? {
        guard let slot = slot(amount: selectedAmount) else { return nil }
        return product(for: slot)
    }

    var canPurchase: Bool {
        catalogState == .available && selectedProduct != nil && !isPurchasing
    }

    var monthlyAvailable: Bool {
        products.contains(where: { $0.frequency == .monthly })
    }

    var amountOptions: [Int] { slots.map(\.amount) }

    func displayPrice(for slot: SupportSlot) -> String {
        product(for: slot)?.displayPrice ?? "Unavailable"
    }

    func load() async {
        catalogState = .loading
        do {
            products = try await purchasing.loadProducts()
            catalogState = products.isEmpty
                ? .unavailable("Support options aren't available right now.")
                : .available
        } catch {
            products = []
            catalogState = .unavailable("The App Store catalog couldn't be loaded. \(error.localizedDescription)")
        }
    }

    func select(amount: Int) {
        guard amountOptions.contains(amount) else { return }
        selectedAmount = amount
        customAmountText = ""
        message = nil
    }

    func applyCustomAmount() {
        let digits = customAmountText.filter(\.isNumber)
        guard let amount = Int(digits), amountOptions.contains(amount) else {
            selectedAmount = 0
            message = .info("Choose one of the available support amounts: $2, $5, or $10.")
            return
        }
        selectedAmount = amount
        message = nil
    }

    func purchase() async {
        guard let product = selectedProduct, !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await purchasing.purchase(productID: product.id) {
            case .verified:
                message = .success("Thank you for supporting Flipabulary.")
            case .unverified:
                message = .failure("The purchase couldn't be verified.")
            case .duplicate:
                message = .info("This purchase was already recorded.")
            case .pending:
                message = .info("The purchase is pending approval.")
            case .cancelled:
                message = .info("Purchase cancelled. Nothing was charged.")
            }
        } catch {
            message = .failure(error.localizedDescription)
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }
        do {
            switch try await purchasing.restore() {
            case .restored(let count):
                message = .success(count == 1 ? "Monthly support restored." : "\(count) purchases restored.")
            case .nothingToRestore:
                message = .info("Nothing to restore. One-time tips aren't restorable.")
            }
        } catch {
            message = .failure(error.localizedDescription)
        }
    }
}

@MainActor
final class PreviewSupportService: SupportPurchasing {
    var outcome: SupportPurchaseOutcome = .verified

    func loadProducts() async throws -> [SupportProduct] {
        SupportSlot.all.flatMap { slot in
            SupportFrequency.allCases.map { frequency in
                SupportProduct(
                    id: slot.productID(for: frequency),
                    displayName: slot.title,
                    displayPrice: frequency == .oneTime ? "$\(slot.amount).00" : "$\(slot.amount).00/mo",
                    frequency: frequency,
                    amount: slot.amount
                )
            }
        }
    }

    func purchase(productID: String) async throws -> SupportPurchaseOutcome { outcome }
    func restore() async throws -> SupportRestoreOutcome { .nothingToRestore }
}
