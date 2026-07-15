import StoreKit
import UIKit

/// Asks for an App Store review at a positive moment (a catch milestone), at
/// most once per milestone. Apple still rate-limits the actual prompt, so this
/// is a hint, not a guarantee.
@MainActor
enum ReviewPrompt {
    private static let milestones: Set<Int> = [5, 25, 100]

    /// Call after logging a catch with the running total of catches logged.
    static func maybeAsk(afterCatchCount count: Int) {
        guard milestones.contains(count) else { return }
        let key = "reviewAsked-\(count)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        // Small delay so it doesn't collide with the save toast/dismiss.
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            AppStore.requestReview(in: scene)
        }
    }
}
