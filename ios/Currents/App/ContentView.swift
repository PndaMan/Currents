import SwiftUI

/// Shell-level navigation values every tab's NavigationStack resolves.
/// Feature screens push their own value types too; these are the routes the
/// shell itself needs (the avatar, deep links, the celebration button).
enum AppRoute: Hashable {
    /// Profile and settings, pushed from the avatar in any tab.
    case profile
    case gear
    case licenses
    case sessions
    case fishdex
    /// One planned session, by trip id.
    case plan(String)
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    // Opens straight to a requested tab in screenshot mode, else Today.
    @State private var selectedTab: Tab = ScreenshotSupport.initialTab ?? .today
    /// One navigation path per tab, so deep links can push and a second tap
    /// on the selected tab pops back to its root.
    @State private var paths: [Tab: NavigationPath] = [:]

    /// Four tabs, each its own NavigationStack, with the Add item in the
    /// middle of the bar. Profile and settings push from the avatar at the
    /// left of every tab's large title.
    ///
    /// `create` is the centre item. It is an action, not a page: selecting
    /// it opens the Add menu and the selection never becomes `create` (see
    /// `tabSelection`). It has no stack, no path and no deep link, and
    /// `init?(rawValue:)` never returns it. Not CaseIterable, so no loop over
    /// the tabs can pick it up as a page.
    enum Tab: Hashable {
        case today
        case explore
        case create
        case logbook
        case crew

        /// Also accepts the old tab names (map, catches, fish, community) so
        /// SCREENSHOT_TAB values from before the redesign keep working.
        init?(rawValue: String) {
            switch rawValue {
            case "today": self = .today
            case "explore", "map", "fish": self = .explore
            case "logbook", "catches": self = .logbook
            case "crew", "community": self = .crew
            default: return nil
            }
        }

        var rawValue: String {
            switch self {
            case .today: "today"
            case .explore: "explore"
            case .create: "create"
            case .logbook: "logbook"
            case .crew: "crew"
            }
        }

        var title: String {
            switch self {
            case .today: "Today"
            case .explore: "Explore"
            case .create: "Add"
            case .logbook: "Logbook"
            case .crew: "Crew"
            }
        }

        /// The bar's symbol. The Add item draws the `TabCreate` logo image
        /// instead; its symbol here is only a fallback name.
        var icon: String {
            switch self {
            case .today: "sun.max"
            case .explore: "map"
            case .create: "plus"
            case .logbook: "book.closed"
            case .crew: "person.2"
            }
        }
    }

    @State private var planPrompt: Trip?
    /// The centre item's Add menu, and the sheets its actions open here.
    @State private var showingAddMenu = false
    @State private var showingNewSession = false
    @State private var showingPlanner = false
    /// The tab bar's top edge measured from the bottom of the screen: a
    /// tab's bottom safe area, read from its stack. The Add menu sits just
    /// above it. The default is close to an iPhone with a home indicator,
    /// used until the first tab has laid out.
    @State private var tabBarInset: CGFloat = 83
    @State private var joinGroupCode: JoinCode?
    @State private var pendingFriend: JoinCode?
    @State private var pendingCrew: JoinCode?
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("use24HourTime") private var use24 = true

    struct JoinCode: Identifiable { let id: String }

    /// Selecting the tab that is already selected pops it to its root. Only a
    /// tap on the tab bar ticks; deep links switch tabs quietly. The Add item
    /// opens its menu and leaves the selection where it was, so it is never
    /// the selected tab; the menu opening redraws the bar on the old tab.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .create {
                    openAddMenu()
                    return
                }
                if tab == selectedTab { paths[tab] = NavigationPath() } else { Haptics.selection() }
                selectedTab = tab
            }
        )
    }

    private func path(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: { paths[tab] ?? NavigationPath() },
            set: { paths[tab] = $0 }
        )
    }

    /// Switch to `tab` and show `routes` on top of its root.
    private func navigate(_ tab: Tab, _ routes: AppRoute...) {
        selectedTab = tab
        var path = NavigationPath()
        for route in routes { path.append(route) }
        paths[tab] = path
    }

    @ViewBuilder
    private func root(for tab: Tab) -> some View {
        switch tab {
        case .today: TodayTab()
        case .explore: MapTab()
        // The Add item has no page; the bar never shows it (`tabSelection`).
        case .create: EmptyView()
        case .logbook: CatchesTab()
        case .crew: CommunityView()
        }
    }

    /// A page tab's stack. It also reports the tab bar's height for the Add
    /// menu: the stack's bottom safe area is the bar plus the home indicator.
    private func stack(for tab: Tab) -> some View {
        NavigationStack(path: path(for: tab)) {
            root(for: tab)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
            if inset > 0 { tabBarInset = inset }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .profile: SettingsView()
        case .gear: GearTab()
        case .licenses: LicenseWalletView()
        case .sessions: SessionsView()
        case .fishdex: FishCollectionView(embedded: true)
        case .plan(let id): PlanDetailView(tripId: id)
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            SwiftUI.Tab(Tab.today.title, systemImage: Tab.today.icon, value: Tab.today) {
                stack(for: .today)
            }
            SwiftUI.Tab(Tab.explore.title, systemImage: Tab.explore.icon, value: Tab.explore) {
                stack(for: .explore)
            }
            // The centre item: the logo, drawn larger than the symbols beside
            // it. An action rather than a page, so its content is never shown.
            SwiftUI.Tab("Add", image: "TabCreate", value: Tab.create) {
                Color.clear
            }
            .accessibilityHint(Text("Log a catch, add a spot or plan a session"))
            SwiftUI.Tab(Tab.logbook.title, systemImage: Tab.logbook.icon, value: Tab.logbook) {
                stack(for: .logbook)
            }
            SwiftUI.Tab(Tab.crew.title, systemImage: Tab.crew.icon, value: Tab.crew) {
                stack(for: .crew)
            }
        }
        // Over the whole screen, tab bar included, and under the toasts and
        // the celebration card.
        .addMenuOverlay(isPresented: $showingAddMenu,
                        sessionIsLive: appState.tripTracker.isTracking,
                        bottomInset: tabBarInset,
                        onSelect: runAddAction)
        .task(id: appState.launchFinished) {
            // Once the launch animation has gone (CurrentsApp), so the
            // planned-session alert never appears behind it.
            guard appState.launchFinished else { return }
            checkPlannedSession()
        }
        .task {
            // Screenshot mode: push the screen CI asked for once the tabs exist.
            guard let tab = ScreenshotSupport.initialTab else { return }
            let path = ScreenshotSupport.initialPath
            let link = ScreenshotSupport.launchURL
            guard path != nil || link != nil else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if let path { paths[tab] = path }
            if let link { appState.pendingDeepLink = link }
        }
        .task {
            // On cold launch (scenePhase .onChange doesn't fire for the initial
            // state), make sure APNs + CloudKit push subscriptions get set up for
            // an already-joined angler. Guarded by the flag so we don't touch
            // CloudKit at launch in the unsigned test build — and never in
            // screenshot mode, where the permission dialog would cover a capture.
            guard UserDefaults.standard.bool(forKey: "communityJoined"),
                  !ScreenshotSupport.isActive, CrewCloud.buildHasCloudKit else { return }
            await CommunityService.shared.enablePush()
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
        }
        .toastHost()
        .celebrationHost()
        .fullScreenCover(isPresented: Binding(get: { !hasOnboarded && !ScreenshotSupport.isActive },
                                              set: { if $0 == false { hasOnboarded = true } })) {
            OnboardingView()
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: appState.pendingDeepLink) { _, url in
            if let url { handleDeepLink(url); appState.pendingDeepLink = nil }
        }
        .task {
            // Cold launch from a notification tap: the link may already be set
            // before onChange starts observing.
            if let url = appState.pendingDeepLink { handleDeepLink(url); appState.pendingDeepLink = nil }
        }
        .sheet(item: $joinGroupCode) { join in
            NavigationStack {
                GroupTripView(tripId: nil, tripName: "Group trip", initialCode: join.id)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                    }
            }
            .dsSheet([.large])
        }
        .sheet(item: $pendingFriend) { friend in
            NavigationStack {
                AddFriendConfirmView(code: friend.id)
            }
        }
        .sheet(item: $pendingCrew) { crew in
            NavigationStack {
                JoinCrewConfirmView(code: crew.id)
            }
        }
        // The Add menu's Start session and Plan a session: the same sheets
        // Sessions and the Logbook open.
        .sheet(isPresented: $showingNewSession) { NewSessionSheet() }
        .sheet(isPresented: $showingPlanner) { PlanSessionSheet() }
        .onChange(of: appState.siriRequestedLogCatch) { _, requested in
            // Siri "Log a Catch" shortcut — surface Logbook so its log
            // sheet (which watches the same flag) can present.
            if requested { selectedTab = .logbook }
        }
        .alert("Start planned session?", isPresented: Binding(
            get: { planPrompt != nil }, set: { if !$0 { planPrompt = nil } }
        ), presenting: planPrompt) { trip in
            Button("Start session") {
                _ = appState.tripTracker.startPlanned(trip)
                Haptics.success()
                planPrompt = nil
                selectedTab = .explore
            }
            Button("Not now", role: .cancel) { planPrompt = nil }
        } message: { trip in
            Text("\(trip.name) is planned for \(trip.plannedDate.map { ForecastFormat.time($0, use24: use24) } ?? "now").")
        }
    }

    /// Handle deep links from notifications, the Live Activity, widgets,
    /// invite links and the celebration card:
    ///   currents://log           → Logbook, log sheet open
    ///   currents://session       → the live session (Explore presents it)
    ///   currents://sessions      → Logbook (its Sessions pane lists them)
    ///   currents://plan          → Logbook (its Plans pane lists them)
    ///   currents://plan/<id>     → Logbook > that plan (its reminder)
    ///   currents://community     → Crew (friend requests / trip invites)
    ///   currents://crewfeed/<C>  → Crew, straight into that crew
    ///   currents://tournament    → Crew (the live tournament lives in its crew)
    ///   currents://gear          → Profile > Gear (low-stock reorder)
    ///   currents://licenses      → Profile > Licences (expiry)
    ///   currents://map           → Explore (bite alerts)
    ///   currents://map/<place>   → Explore, centred on a spot, water, ramp
    ///                              or point with its sheet open
    ///   currents://fishdex       → Logbook > Fishdex
    ///   currents://trip/<CODE>   → Join Trip confirmation
    ///   currents://friend/<CODE> → Add Friend confirmation
    ///   currents://crew/<CODE>   → Join Crew confirmation
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "currents" else { return }
        let host = url.host ?? ""
        // A link from a notification or widget lands on its screen, not
        // under the Add menu.
        showingAddMenu = false

        // Simple screen routes (no code needed).
        switch host {
        case "log":
            // Quick-log from the widget / shortcut / a place page: Logbook
            // presents the log sheet (CatchesTab watches this flag). Its stack
            // is kept, so logging from a page pushed there returns to it.
            selectedTab = .logbook
            appState.siriRequestedLogCatch = true
            return
        case "session":
            openLiveSession()
            return
        case "sessions":
            navigate(.logbook)
            return
        case "plan":
            let id = url.lastPathComponent
            if id.isEmpty || id == "/" || id == host {
                navigate(.logbook)
            } else {
                navigate(.logbook, .plan(id))
            }
            return
        case "community", "tournament":
            navigate(.crew)
            return
        case "crewfeed":
            // A crew push tap: straight into that crew, not the Crew root.
            navigate(.crew)
            let code = url.lastPathComponent.uppercased()
            if code.count == 6 { appState.openCrewCode = code }
            return
        case "gear":
            navigate(selectedTab, .profile, .gear)
            return
        case "licenses":
            navigate(selectedTab, .profile, .licenses)
            return
        case "map":
            // A place link (spot, water, ramp or point, see ExploreFocus)
            // opens that place's sheet on the Explore map. Sheets shown from
            // here close first, since the group trip one can link to a place.
            ExploreFocus.shared.open(url)
            joinGroupCode = nil
            pendingFriend = nil
            pendingCrew = nil
            navigate(.explore)
            return
        case "fishdex":
            navigate(.logbook, .fishdex)
            return
        default:
            break
        }

        var code = url.lastPathComponent
        if code.isEmpty || code == "join" || code == host,
           let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value {
            code = q
        }
        code = code.uppercased()
        guard code.count == 6 else { return }

        if host == "trip" || url.pathComponents.contains("trip") {
            joinGroupCode = JoinCode(id: code)
        } else if host == "friend" || url.pathComponents.contains("friend") {
            pendingFriend = JoinCode(id: code)
        } else if host == "crew" || url.pathComponents.contains("crew") {
            pendingCrew = JoinCode(id: code)
        }
    }

    // MARK: - Add menu

    private func openAddMenu() {
        guard !showingAddMenu else { return }
        Haptics.softPress()
        showingAddMenu = true
    }

    /// Runs a tile of the Add menu (which has already closed) through the
    /// flow the rest of the app uses for it.
    private func runAddAction(_ action: AddMenuAction) {
        switch action {
        case .logCatch:
            // Today's Log catch: Logbook opens the log flow off this flag.
            appState.siriRequestedLogCatch = true
        case .addSpot:
            // Explore's own Add spot: place the pin, then the New spot form.
            navigate(.explore)
            appState.openAddSpot = true
        case .startSession:
            // As on Explore: the live session when one is recording, else
            // the New session sheet.
            if appState.tripTracker.isTracking {
                openLiveSession()
            } else {
                showingNewSession = true
            }
        case .planSession:
            showingPlanner = true
        }
    }

    /// The live session sheet, which the Explore root presents.
    private func openLiveSession() {
        navigate(.explore)
        appState.openLiveSession = true
    }

    /// On launch, if a planned session is within ~2 hours of now and nothing is
    /// already recording, offer to start it.
    private func checkPlannedSession() {
        guard !ScreenshotSupport.isActive else { return }
        let planned = (try? appState.tripRepository.fetchPlanned()) ?? []
        // Keep the "Next Session" widget in sync with the soonest upcoming plan.
        let upcoming = planned
            .filter { ($0.plannedDate ?? .distantPast) > .now }
            .min { ($0.plannedDate ?? .distantFuture) < ($1.plannedDate ?? .distantFuture) }
        WidgetSnapshotWriter.writeNextSession(name: upcoming?.name, date: upcoming?.plannedDate)

        guard !appState.tripTracker.isTracking else { return }
        planPrompt = planned.first { trip in
            guard let d = trip.plannedDate else { return false }
            return abs(d.timeIntervalSinceNow) < 2 * 3600
        }
    }
}
