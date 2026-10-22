import StoreKit
import SwiftUI

/// Tips to the developer through Apple In-App Purchase, the only way App
/// Store guideline 3.1.1 allows them: three consumables that unlock nothing.
/// Prices come from the App Store, never from here.
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    static let productIds = [
        "com.aidanmcconnon.currents.tip.small",
        "com.aidanmcconnon.currents.tip.medium",
        "com.aidanmcconnon.currents.tip.large",
    ]

    enum LoadState { case idle, loading, loaded, unavailable }

    /// The tips on sale, cheapest first. Empty until the App Store answers,
    /// and when it has none (not set up yet, offline, a sideloaded build).
    private(set) var products: [Product] = []
    private(set) var state: LoadState = .idle
    /// The tip being bought, for its row's spinner.
    private(set) var purchasing: Product.ID?
    /// Set when Ask to Buy is waiting for a parent's approval.
    private(set) var awaitingApproval = false
    /// Tips that went through on this phone.
    private(set) var tipCount = UserDefaults.standard.integer(forKey: TipJar.countKey)

    @ObservationIgnored private var updates: Task<Void, Never>?

    private static let countKey = "tipJarCount"
    /// Transactions already counted, so one that comes back is not counted twice.
    private static let countedKey = "tipJarCountedTransactions"

    var isAvailable: Bool { !products.isEmpty }

    /// Whether this phone allows purchases (Screen Time or a management
    /// profile can turn them off).
    var canPay: Bool { AppStore.canMakePayments }

    // MARK: Loading

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let found = try await Product.products(for: Self.productIds)
            products = found.filter { $0.type == .consumable }.sorted { $0.price < $1.price }
            state = products.isEmpty ? .unavailable : .loaded
        } catch {
            state = products.isEmpty ? .unavailable : .loaded
        }
    }

    /// Starts listening for transactions made outside the purchase sheet
    /// (an approved Ask to Buy, a purchase interrupted by a crash) and
    /// finishes them. Call once, at launch; unfinished transactions arrive
    /// straight away.
    func startListening() {
        guard updates == nil else { return }
        updates = Task {
            for await result in StoreKit.Transaction.updates {
                if await self.settle(result) {
                    self.awaitingApproval = false
                    Haptics.success()
                    ToastCenter.shared.show("Thank you for the tip", icon: "heart.fill")
                }
            }
        }
    }

    // MARK: Buying

    /// Buys a tip with the SwiftUI purchase action, which shows Apple's
    /// confirmation sheet over the right scene.
    func buy(_ product: Product, with purchase: PurchaseAction) async {
        guard purchasing == nil else { return }
        purchasing = product.id
        defer { purchasing = nil }
        do {
            switch try await purchase(product) {
            case .success(let verification):
                if await settle(verification) {
                    Haptics.success()
                    ToastCenter.shared.show("Thank you for the tip", icon: "heart.fill")
                } else {
                    ToastCenter.shared.show("The App Store could not confirm this tip.", style: .error)
                }
            case .pending:
                awaitingApproval = true
                ToastCenter.shared.show("Waiting for approval. The tip goes through once it is approved.",
                                        style: .info)
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            if let message = Self.message(for: error) {
                ToastCenter.shared.show(message, style: .error)
            }
        }
    }

    /// Finishes a transaction and counts it when it is a verified tip.
    /// Unverified ones are finished too, so they stop coming back, but not
    /// counted.
    private func settle(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        switch result {
        case .verified(let transaction):
            let isTip = Self.productIds.contains(transaction.productID) && transaction.revocationDate == nil
            let counted = isTip && record(transaction.id)
            await transaction.finish()
            return counted
        case .unverified(let transaction, _):
            await transaction.finish()
            return false
        }
    }

    /// Adds one to the count unless this transaction was counted before.
    private func record(_ id: UInt64) -> Bool {
        let defaults = UserDefaults.standard
        var counted = defaults.stringArray(forKey: Self.countedKey) ?? []
        let key = String(id)
        guard !counted.contains(key) else { return false }
        counted.append(key)
        defaults.set(Array(counted.suffix(100)), forKey: Self.countedKey)
        tipCount += 1
        defaults.set(tipCount, forKey: Self.countKey)
        return true
    }

    /// Plain words for a failed purchase, or nil when the person cancelled.
    private static func message(for error: Error) -> String? {
        if let error = error as? StoreKitError {
            switch error {
            case .userCancelled:
                return nil
            case .networkError:
                return "Could not reach the App Store. Try again when you have signal."
            case .notAvailableInStorefront:
                return "Tips are not available in your App Store country."
            default:
                break
            }
        }
        if case Product.PurchaseError.purchaseNotAllowed = error {
            return "Purchases are turned off on this phone."
        }
        return "The tip did not go through. Please try again later."
    }
}
