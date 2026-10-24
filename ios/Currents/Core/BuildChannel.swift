import Foundation
import StoreKit

/// Where this copy of the app came from, for tools that only testers should see.
enum BuildChannel {
    /// True for TestFlight and Xcode builds, false for the App Store. Reads the
    /// signed app transaction; when that can't be fetched (offline on first
    /// launch, or StoreKit still waking up), falls back to the receipt file,
    /// which TestFlight names "sandboxReceipt".
    static func isTesting() async -> Bool {
        #if DEBUG
        return true
        #else
        if let result = try? await AppTransaction.shared {
            switch result {
            case .verified(let transaction), .unverified(let transaction, _):
                return transaction.environment != .production
            }
        }
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
