import StoreKit
import SwiftUI
import UIKit

/// The rate or support prompt. After the first catch ever is saved, and only
/// once any celebration has been dismissed, a half sheet asks for a rating or
/// a coffee. Once shown it stays away for 30 days, then may come back at the
/// next catch milestone.
@MainActor
enum ReviewPrompt {
    private static let lastShownKey = "ratePromptLastShown"
    private static let cooldown: TimeInterval = 30 * 24 * 3600
    private static let milestones: Set<Int> = [1, 5, 10, 25, 50, 100, 250, 500, 1000]
    static let supportURL = URL(string: "https://ko-fi.com/aidanmcconnon")!

    /// Call after logging a catch with the running total of catches logged.
    static func maybeAsk(afterCatchCount count: Int) {
        guard isDue(count: count) else { return }
        Task { await present(count: count) }
    }

    private static func isDue(count: Int) -> Bool {
        let last = UserDefaults.standard.double(forKey: lastShownKey)
        // Never shown: ask at the first save (or the next one, for anglers who
        // logged catches before the prompt existed).
        if last == 0 { return count >= 1 }
        guard Date().timeIntervalSince1970 - last >= cooldown else { return false }
        return milestones.contains(count)
    }

    /// Waits for the composer to close and any celebration to be dismissed,
    /// then shows the half sheet over whatever screen is on top.
    private static func present(count: Int) async {
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
        weak var host: UIHostingController<RatePromptSheet>?
        let sheet = RatePromptSheet(count: count) { action in
            host?.dismiss(animated: true) {
                switch action {
                case .rate:
                    AppStore.requestReview(in: scene)
                case .coffee:
                    UIApplication.shared.open(supportURL)
                case .later:
                    ToastCenter.shared.show("We won't ask again for a month", style: .info, icon: "clock")
                }
            }
        }
        let controller = UIHostingController(rootView: sheet)
        host = controller
        if let presentation = controller.sheetPresentationController {
            // Medium fits the sheet at default text sizes; large text can
            // pull it up instead of clipping the buttons.
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
            presentation.preferredCornerRadius = DS.Radius.sheet
        }
        top.present(controller, animated: true)
    }
}

/// The half sheet itself.
struct RatePromptSheet: View {
    enum Action { case rate, coffee, later }
    let count: Int
    var onAction: (Action) -> Void

    private var title: String {
        count <= 1 ? "First one in the book" : "\(count) catches in the book"
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dsBackground.ignoresSafeArea())
        .tint(DS.accent)
    }

    private var content: some View {
        VStack(spacing: DS.Space.s2) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.bottom, DS.Space.s2)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.dsText)
            Text("Currents has no ads and no account. If it helped today, a rating or a coffee keeps it that way.")
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.Space.s3)

            Button { onAction(.rate) } label: {
                Label("Rate Currents", systemImage: "star.fill")
            }
            .buttonStyle(.dsPrimary)
            Button { onAction(.coffee) } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer")
            }
            .buttonStyle(.dsTonal)
            Button("Not now") { onAction(.later) }
                .font(.headline)
                .foregroundStyle(Color.dsText2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.dim)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
