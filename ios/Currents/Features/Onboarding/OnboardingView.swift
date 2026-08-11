import SwiftUI

/// First-launch welcome + permission primers. Shown once (gated by the
/// `hasOnboarded` flag) so location and notification system prompts are asked
/// *with context*, not cold on launch.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
        let cta: String
    }

    private let pages: [Page] = [
        .init(icon: "figure.fishing",
              title: "Welcome to Currents",
              body: "Your offline-first fishing companion — log every catch, read the bite, and find your next spot.",
              cta: "Get Started"),
        .init(icon: "location.fill",
              title: "Find the bite near you",
              body: "Currents uses your location to show the local forecast, tag catches to a spot, and track your sessions. It never leaves your device unless you choose to share.",
              cta: "Enable Location"),
        .init(icon: "bell.badge.fill",
              title: "Never miss prime time",
              body: "Get a heads-up before the best feeding windows at your spots, plus session and licence reminders. You can fine-tune these any time.",
              cta: "Enable Notifications"),
        .init(icon: "person.3.fill",
              title: "Fish with friends",
              body: "Share catches, compare on a friends-only leaderboard, and run live group trips — all optional, and off until you opt in.",
              cta: "Start Fishing"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [CurrentsTheme.accent.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, p in
                        pageView(p, index: i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                // Dots
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? CurrentsTheme.accent : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .padding(.bottom, 18)

                Button(action: advance) {
                    Text(pages[page].cta).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .controlSize(.large)
                .padding(.horizontal, 28)

                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.bottom, 8)
                    .opacity(page == pages.count - 1 ? 0 : 1)
            }
            .padding(.bottom, 12)
        }
    }

    private func pageView(_ p: Page, index: Int) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(CurrentsTheme.accent.opacity(0.15)).frame(width: 160, height: 160)
                if index == 0 {
                    // Lead with the actual app logo — the theme-tinted current
                    // mark — so the very first screen is unmistakably Currents.
                    CurrentsMark()
                        .stroke(CurrentsTheme.accent,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        .frame(width: 92, height: 92)
                } else {
                    Image(systemName: p.icon)
                        .font(.system(size: 68))
                        .foregroundStyle(CurrentsTheme.accent)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            Text(p.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(p.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func advance() {
        Haptics.tap()
        switch page {
        case 1: appState.locationManager.requestPermission()
        case 2: Task { _ = await NotificationManager.shared.requestPermission() }
        default: break
        }
        if page < pages.count - 1 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        hasOnboarded = true
    }
}
