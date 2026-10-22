import StoreKit
import SwiftUI
import UIKit

/// Asks for an App Store rating with the system prompt, after the first catch
/// ever is saved and once any celebration has been dismissed. There is no
/// pre-prompt of our own: App Review Guideline 5.6.1 disallows custom review
/// prompts. Once asked it stays away for 30 days, then may ask again at the
/// next catch milestone. The system decides whether the prompt actually
/// shows (at most three times a year, never in TestFlight).
@MainActor
enum ReviewPrompt {
    private static let lastShownKey = "ratePromptLastShown"
    private static let cooldown: TimeInterval = 30 * 24 * 3600
    private static let milestones: Set<Int> = [1, 5, 10, 25, 50, 100, 250, 500, 1000]

    /// The App Store page where a review is written, for a permanent Rate
    /// button. Apple's guidance is to link here rather than call the prompt
    /// from a button tap.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6771932525?action=write-review")!

    /// Call after logging a catch with the running total of catches logged.
    static func maybeAsk(afterCatchCount count: Int) {
        guard isDue(count: count) else { return }
        Task { await present() }
    }

    private static func isDue(count: Int) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastShownKey)
        // Never asked: ask at the first save (or the next one, for anglers who
        // logged catches before the prompt existed).
        if last == 0 { return count >= 1 }
        guard Date().timeIntervalSince1970 - last >= cooldown else { return false }
        return milestones.contains(count)
    }

    /// Waits for the composer to close and any celebration to be dismissed,
    /// then asks the system to show its rating prompt.
    private static func present() async {
        try? await Task.sleep(for: .seconds(1.2))
        var sawCelebration = false
        var root: UIViewController?
        var scene: UIWindowScene?
        // Up to about two minutes for the angler to close the celebration and
        // the composer. If something is still in the way, it is due next time.
        for _ in 0..<400 {
            scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            root = scene?.keyWindow?.rootViewController
            let celebrating = CelebrationCenter.shared.current != nil
            if celebrating { sawCelebration = true }
            if !celebrating, let root, root.presentedViewController == nil { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard let scene, let top = root, top.presentedViewController == nil,
              CelebrationCenter.shared.current == nil else { return }
        if sawCelebration { try? await Task.sleep(for: .milliseconds(700)) }
        guard top.presentedViewController == nil else { return }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastShownKey)
        AppStore.requestReview(in: scene)
    }
}
