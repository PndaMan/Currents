import SwiftUI

/// First-launch welcome and permission primers. Shown once (gated by
/// `hasOnboarded`) so the location and notification system prompts are asked
/// with context, not cold on launch. Each page shows the real feature it is
/// about: species art, the bite ring, alert banners. The last page picks the
/// target species, the same `targetSpeciesId` the forecast pickers write.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("use24HourTime") private var use24 = true
    @State private var page = 0
    @State private var posters: [Species] = []
    @State private var picks: [Species] = []
    /// True while the location prompt is up, so the page moves on only once
    /// the angler has answered it.
    @State private var awaitingLocation = false

    private let pageCount = 4
    /// Species shown on the welcome posters, in poster order.
    private static let posterSpeciesIDs: [Int64] = [1, 120, 17, 46, 130, 18]
    /// Species offered on the last page: the common targets in fresh and
    /// salt water. Any other species can be picked later in the forecast.
    private static let pickSpeciesIDs: [Int64] = [1, 2, 17, 18, 34, 46, 240, 11, 120, 130, 72, 86]

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // A swipe ticks; the buttons below bring their own press.
            TabView(selection: $page.haptic()) {
                welcomePage.tag(0)
                locationPage.tag(1)
                alertsPage.tag(2)
                speciesPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: page)

            VStack(spacing: DS.Space.s2) {
                Button(action: advance) {
                    Text(cta)
                }
                .buttonStyle(.dsPrimary)

                switch page {
                case 0:
                    Text("No account needed. Everything stays on this phone.")
                        .font(.footnote)
                        .foregroundStyle(.dsText3)
                        .padding(.top, DS.Space.s2)
                case 1, 2:
                    Button("Not now") { Haptics.softPress(); next() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                default:
                    EmptyView()
                }
            }
            .frame(minHeight: 110, alignment: .top)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
        }
        .dsScreenBackground()
        .onChange(of: appState.locationManager.authorizationStatus) { _, status in
            guard awaitingLocation, status != .notDetermined else { return }
            awaitingLocation = false
            if page == 1 { next() }
        }
        .task {
            posters = Self.posterSpeciesIDs.compactMap { (try? appState.speciesRepository.fetch(id: $0)) ?? nil }
            picks = Self.pickSpeciesIDs.compactMap { (try? appState.speciesRepository.fetch(id: $0)) ?? nil }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                Haptics.softPress()
                withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { page = max(0, page - 1) }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .opacity(page == 0 ? 0 : 1)
            .disabled(page == 0)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.dsText : Color.dsFill2)
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.spring, value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            Spacer()

            Button("Skip") { finish() }
                .opacity(page == pageCount - 1 ? 0 : 1)
                .disabled(page == pageCount - 1)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.dsText)
        .frame(height: 44)
        .padding(.horizontal, DS.Space.s3)
    }

    private var cta: String {
        switch page {
        case 0: "Get started"
        case 1: "Allow location"
        case 2: "Turn on notifications"
        default: "Start fishing"
        }
    }

    // MARK: Page 0, welcome

    /// At accessibility sizes the posters would sit on the title, so the
    /// page drops them and scrolls instead.
    @ViewBuilder private var welcomePage: some View {
        if typeSize.isAccessibilitySize {
            ScrollView {
                welcomeText
                    .padding(.vertical, DS.Space.s6)
            }
            .scrollIndicators(.hidden)
        } else {
            VStack(spacing: DS.Space.s5) {
                posterWall
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                welcomeText
            }
        }
    }

    private var welcomeText: some View {
        VStack(spacing: DS.Space.s3) {
            HStack(spacing: 8) {
                LogoView(style: .symbol, size: 28)
                Text("Currents")
                    .font(.headline)
                    .foregroundStyle(.dsText)
            }
            Text("Read the bite before you leave home")
                .font(.largeTitle.bold())
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.center)
            Text("A forecast for your water, a catch log and your tackle box. All of it works with no signal.")
                .font(.callout)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DS.gutter)
    }

    /// Species art on tilted cards, scattered like posters on a wall.
    private var posterWall: some View {
        GeometryReader { geo in
            let layout: [(rotation: Double, x: CGFloat, y: CGFloat)] = [
                (-9, 0.06, 0.04), (7, 0.62, 0.00), (-3, 0.34, 0.20),
                (11, 0.70, 0.44), (-12, 0.02, 0.46), (5, 0.38, 0.58),
            ]
            let width = geo.size.width * 0.3
            ZStack(alignment: .topLeading) {
                ForEach(Array(posters.prefix(layout.count).enumerated()), id: \.offset) { index, species in
                    let spot = layout[index]
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.thumb - 4, style: .continuous)
                            .fill(species.artTint.opacity(0.35))
                        SpeciesArtworkView(species: species, caught: true, size: width * 0.78)
                    }
                    .padding(5)
                    .frame(width: width, height: width * 1.25)
                    .background(Color.dsElevated, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                            .strokeBorder(Color.dsSeparator, lineWidth: 1)
                    }
                    .rotationEffect(.degrees(spot.rotation))
                    .offset(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .padding(.horizontal, DS.Space.s3)
        .accessibilityHidden(true)
    }

    // MARK: Page 1, location primer

    private var locationPage: some View {
        primerPage(
            title: "Find the bite near you",
            body: "Your location picks the nearest water for the forecast and pins your catches. It stays on this phone unless you share it."
        ) {
            VStack(spacing: DS.Space.s5) {
                ScoreRing(score: 81, size: typeSize.isAccessibilitySize ? 96 : 150, caption: "of 100")
                Label("Your nearest water", systemImage: "mappin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.dsFill, in: Capsule())
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Page 2, notification primer

    private var alertsPage: some View {
        primerPage(
            title: "Never miss a bite window",
            body: "Bite windows at your spots, low tackle and licence reminders. Only the ones you choose."
        ) {
            VStack(spacing: 10) {
                // Worded as the real notifications are (NotificationManager).
                banner(title: "Bite window open at your spot",
                       detail: "Bite score up to 82 from \(sampleTime(hour: 6)) to \(sampleTime(hour: 8)).")
                banner(title: "Fishing licence reminder",
                       detail: "Freshwater licence expires in 2 weeks.")
                    .opacity(0.75)
                    .scaleEffect(0.95)
            }
            .padding(.horizontal, DS.gutter)
            .accessibilityHidden(true)
        }
    }

    /// A sample banner time today, in the 24-hour setting.
    private func sampleTime(hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 10, second: 0, of: .now) ?? .now
        return ForecastFormat.time(date, use24: use24)
    }

    private func banner(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AppIconPreview(tint: ThemeOption.current.primary, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.dsText)
                Text(detail).font(.subheadline).foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    // MARK: Page 3, target species

    private var speciesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("What do you fish for?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.dsText)
                    Text("Pick the one you target most. The forecast and lure picks tune to it.")
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                }
                .padding(.horizontal, DS.gutter)

                if picks.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s6)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3, alignment: .top),
                                             count: typeSize.isAccessibilitySize ? 2 : 3),
                              spacing: DS.Space.s4) {
                        ForEach(picks) { species in
                            speciesTile(species)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }
            }
            .padding(.top, DS.Space.s4)
            .padding(.bottom, DS.Space.s5)
            .pageWidth()
        }
        .scrollIndicators(.hidden)
    }

    private func speciesTile(_ species: Species) -> some View {
        let selected = targetSpeciesId == Int(species.id)
        return Button {
            withAnimation(reduceMotion ? nil : DS.Motion.spring) {
                targetSpeciesId = selected ? 0 : Int(species.id)
            }
        } label: {
            VStack(spacing: DS.Space.s2) {
                ThumbView(species: species, size: 76)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                            .strokeBorder(selected ? Color.dsText : Color.clear, lineWidth: 2.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.dsOnPrimary, Color.dsPrimaryButton)
                                .offset(x: 6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(species.commonName)
                    .font(.footnote.weight(selected ? .semibold : .medium))
                    .foregroundStyle(.dsText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityLabel(species.commonName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Scaffold

    /// The art fills the space above the title. At accessibility sizes the
    /// page scrolls instead, so the text never runs under the buttons.
    private func primerPage<Content: View>(title: String, body: String,
                                           @ViewBuilder art: () -> Content) -> some View {
        let artView = art()
        let titleText = Text(title)
            .font(.largeTitle.bold())
            .foregroundStyle(.dsText)
            .padding(.horizontal, DS.gutter)
        let bodyText = Text(body)
            .font(.callout)
            .foregroundStyle(.dsText2)
            .padding(.horizontal, DS.gutter)
        return Group {
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        artView
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s4)
                        titleText
                            .fixedSize(horizontal: false, vertical: true)
                        bodyText
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, DS.Space.s4)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    artView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    titleText
                    bodyText
                }
            }
        }
    }

    // MARK: Actions

    /// Each permission page moves on once its system prompt is answered, so
    /// the prompt never sits over the next page.
    private func advance() {
        switch page {
        case 1:
            guard appState.locationManager.authorizationStatus == .notDetermined else { next(); return }
            awaitingLocation = true
            appState.locationManager.requestPermission()
        case 2:
            Task {
                _ = await NotificationManager.shared.requestPermission()
                if page == 2 { next() }
            }
        default:
            next()
        }
    }

    private func next() {
        if page < pageCount - 1 {
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        Haptics.success()
        hasOnboarded = true
    }
}
