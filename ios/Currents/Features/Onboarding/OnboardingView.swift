import SwiftUI

/// First-launch welcome + permission primers, v2: every page shows a living
/// mock of the real feature (bite ring, catch card, crew feed) instead of a
/// lone symbol, so the app sells itself before asking for anything. Shown once
/// (gated by `hasOnboarded`) so location and notification system prompts are
/// asked *with context*, not cold on launch.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            LinearGradient(colors: [CurrentsTheme.accent.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    forecastPage.tag(1)
                    alertsPage.tag(2)
                    crewsPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? CurrentsTheme.accent : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .padding(.bottom, 18)

                Button(action: advance) {
                    Text(cta).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
                .controlSize(.large)
                .padding(.horizontal, 28)

                Button("Skip") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12).padding(.bottom, 8)
                    .opacity(page == pageCount - 1 ? 0 : 1)
            }
            .padding(.bottom, 12)
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var cta: String {
        switch page {
        case 0: "Get Started"
        case 1: "Enable Location"
        case 2: "Enable Notifications"
        default: "Start Fishing"
        }
    }

    // MARK: Page 0 — welcome

    private var welcomePage: some View {
        pageScaffold(
            title: "Welcome to Currents",
            body: "Your offline-first fishing companion — log every catch, read the bite, and find your next spot."
        ) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(CurrentsTheme.accent.opacity(0.15)).frame(width: 132, height: 132)
                    CurrentsMark()
                        .stroke(CurrentsTheme.accent,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .frame(width: 76, height: 76)
                }
                VStack(spacing: 8) {
                    featureRow("gauge.medium", "Bite forecasts for your exact water")
                    featureRow("fish.fill", "A catch log that learns what works")
                    featureRow("person.3.fill", "Crews, tournaments and live trips")
                }
            }
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(CurrentsTheme.accent)
                .frame(width: 26)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 40)
    }

    // MARK: Page 1 — forecast (location primer)

    private var forecastPage: some View {
        pageScaffold(
            title: "Find the bite near you",
            body: "Your location powers the local forecast, spot tagging and session tracking. It never leaves your device unless you choose to share."
        ) {
            MockBiteRing()
        }
    }

    // MARK: Page 2 — alerts (notification primer)

    private var alertsPage: some View {
        pageScaffold(
            title: "Never miss prime time",
            body: "A heads-up before the best feeding windows at your spots, plus session and licence reminders. Fine-tune any of it later."
        ) {
            VStack(spacing: 10) {
                mockNotification(icon: "sunrise.fill",
                                 title: "Prime window at Willow Point",
                                 detail: "Bite score 86 from 6–8 AM — conditions lining up.")
                mockNotification(icon: "trophy.fill",
                                 title: "Dawn Patrol took the lead",
                                 detail: "Your team trails by 12 points with an hour left.")
                    .opacity(0.75)
                    .scaleEffect(0.94)
            }
        }
    }

    private func mockNotification(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CurrentsTheme.accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(CurrentsTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.bold())
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 36)
    }

    // MARK: Page 3 — community

    private var crewsPage: some View {
        pageScaffold(
            title: "Fish with friends",
            body: "Share catches, run crew tournaments, chase weekly challenges — all optional, and off until you opt in."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    mockAvatar("🌊")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dawn Patrol").font(.footnote.bold())
                        Text("4 anglers · tournament live").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Divider()
                HStack(spacing: 10) {
                    mockAvatar("🎣")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sam landed a Largemouth Bass").font(.caption.bold())
                        Text("1.8 kg · 5 min ago").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text("🔥").font(.caption)
                        Text("3").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.gray.opacity(0.12), in: Capsule())
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .padding(.horizontal, 36)
        }
    }

    private func mockAvatar(_ emoji: String) -> some View {
        ZStack {
            Circle().fill(CurrentsTheme.accent.opacity(0.15)).frame(width: 34, height: 34)
            Text(emoji).font(.subheadline)
        }
    }

    // MARK: Scaffold

    private func pageScaffold<Content: View>(title: String, body: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 22) {
            Spacer()
            content()
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(body)
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
        if page < pageCount - 1 {
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        Haptics.success()
        hasOnboarded = true
    }
}

/// The animated mock bite-score ring on the location page — fills to 86 the
/// moment the page appears, exactly like the real Today ring.
private struct MockBiteRing: View {
    @State private var animated = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(CurrentsTheme.accent.opacity(0.15), lineWidth: 14)
                .frame(width: 150, height: 150)
            Circle()
                .trim(from: 0, to: animated ? 0.86 : 0.02)
                .stroke(AngularGradient(colors: [CurrentsTheme.accent, .teal, .green],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 1.1), value: animated)
            VStack(spacing: 2) {
                Text(animated ? "86" : "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(CurrentsTheme.accent)
                Text("Bite Score")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { animated = true }
    }
}
