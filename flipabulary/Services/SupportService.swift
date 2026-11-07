import Foundation
import Observation
import StoreKit

struct SupportSlot: Identifiable, Hashable, Sendable {
    var amount: Int
    var title: String
    var subtitle: String
    var productID: String

    var id: Int { amount }

    static let all: [SupportSlot] = [
        SupportSlot(
            amount: 3,
            title: "Coffee",
            subtitle: "A small thank-you",
            productID: "com.mrmaier.flipabulary.support.coffee"
        ),
        SupportSlot(
            amount: 5,
            title: "Lunch",
            subtitle: "Keeps the words coming",
            productID: "com.mrmaier.flipabulary.support.lunch"
        ),
        SupportSlot(
            amount: 8,
            title: "Big fan",
            subtitle: "A generous boost",
            productID: "com.mrmaier.flipabulary.support.bigfan"
        ),
        SupportSlot(
            amount: 20,
            title: "Patron",
            subtitle: "For serious supporters",
            productID: "com.mrmaier.flipabulary.support.patron"
        ),
        SupportSlot(
            amount: 50,
            title: "Champion",
            subtitle: "A major boost",
            productID: "com.mrmaier.flipabulary.support.champion"
        ),
        SupportSlot(
            amount: 100,
            title: "Legend",
            subtitle: "The ultimate thank-you",
            productID: "com.mrmaier.flipabulary.support.legend"
        )
    ]
}

struct SupportProduct: Identifiable, Hashable, Sendable {
    var id: String
    var displayName: String
    var displayPrice: String
    var amount: Int
}

enum SupportPurchaseOutcome: Sendable {
    case verified
    case unverified
    case duplicate
    case pending
    case cancelled
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
        let ids = SupportSlot.all.map(\.productID)
        let products = try await Product.products(for: ids)
        loadedProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        return SupportSlot.all.compactMap { slot in
            guard let product = loadedProducts[slot.productID] else { return nil }
            return SupportProduct(
                id: slot.productID,
                displayName: slot.title,
                displayPrice: product.displayPrice,
                amount: slot.amount
            )
        }
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
    var selectedAmount = 5
    var isPurchasing = false
    var message: Message?

    init(purchasing: SupportPurchasing) {
        self.purchasing = purchasing
    }

    var slots: [SupportSlot] { SupportSlot.all }

    func slot(amount: Int) -> SupportSlot? {
        slots.first(where: { $0.amount == amount })
    }

    func product(for slot: SupportSlot) -> SupportProduct? {
        products.first(where: { $0.id == slot.productID })
    }

    var selectedProduct: SupportProduct? {
        guard let slot = slot(amount: selectedAmount) else { return nil }
        return product(for: slot)
    }

    var canPurchase: Bool {
        catalogState == .available && selectedProduct != nil && !isPurchasing
    }

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
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-DebugSupportAmount"),
               arguments.indices.contains(index + 1),
               let amount = Int(arguments[index + 1]),
               slots.contains(where: { $0.amount == amount }) {
                selectedAmount = amount
            }
            #endif
        } catch {
            products = []
            catalogState = .unavailable("The App Store catalog couldn't be loaded. \(error.localizedDescription)")
        }
    }

    func select(amount: Int) {
        guard slots.contains(where: { $0.amount == amount }) else { return }
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
}

@MainActor
final class PreviewSupportService: SupportPurchasing {
    var outcome: SupportPurchaseOutcome = .verified

    func loadProducts() async throws -> [SupportProduct] {
        SupportSlot.all.map { slot in
            SupportProduct(
                id: slot.productID,
                displayName: slot.title,
                displayPrice: String(format: "$%.2f", Double(slot.amount) - 0.01),
                amount: slot.amount
            )
        }
    }

    func purchase(productID: String) async throws -> SupportPurchaseOutcome { outcome }
}
