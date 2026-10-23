import StoreKit

/// Where this copy of the app came from, for tools that only testers should see.
enum BuildChannel {
    /// True for TestFlight and Xcode builds, false for the App Store. Reads the
    /// signed app transaction, so it cannot be faked by changing settings.
    static func isTesting() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment != .production
        }
    }
}
