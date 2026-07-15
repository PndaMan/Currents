import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    // Opens straight to a requested tab in screenshot mode, else the map.
    @State private var selectedTab: Tab = ScreenshotSupport.initialTab ?? .map

    enum Tab: String, CaseIterable {
        case map
        case catches
        case collection
        case forecast
        case profile

        var title: String {
            switch self {
            case .map: "Explore"
            case .catches: "Catches"
            case .collection: "Collection"
            case .forecast: "Forecast"
            case .profile: "More"
            }
        }

        var icon: String {
            switch self {
            case .map: "map.fill"
            case .catches: "fish.fill"
            case .collection: "books.vertical.fill"
            case .forecast: "cloud.sun.fill"
            case .profile: "square.grid.2x2.fill"
            }
        }
    }

    @State private var planPrompt: Trip?
    @State private var joinGroupCode: JoinCode?
    @State private var pendingFriend: JoinCode?
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    struct JoinCode: Identifiable { let id: String }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(Tab.allCases, id: \.self) { tab in
                SwiftUI.Tab(tab.title, systemImage: tab.icon, value: tab) {
                    switch tab {
                    case .map:
                        MapTab()
                    case .catches:
                        CatchesTab()
                    case .collection:
                        FishCollectionView()
                    case .forecast:
                        ForecastTab()
                    case .profile:
                        ProfileTab()
                    }
                }
            }
        }
        .task { checkPlannedSession() }
        .task {
            // On cold launch (scenePhase .onChange doesn't fire for the initial
            // state), make sure APNs + CloudKit push subscriptions get set up for
            // an already-joined angler. Guarded by the flag so we don't touch
            // CloudKit at launch in the unsigned test build.
            guard UserDefaults.standard.bool(forKey: "communityJoined") else { return }
            await CommunityService.shared.enablePush()
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
        }
        .toastHost()
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
                GroupTripView(tripId: nil, tripName: "Group Trip", initialCode: join.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { joinGroupCode = nil }
                        }
                    }
            }
        }
        .sheet(item: $pendingFriend) { friend in
            NavigationStack {
                AddFriendConfirmView(code: friend.id)
            }
        }
        .onChange(of: appState.siriRequestedLogCatch) { _, requested in
            // Siri "Log a Catch" shortcut — surface the Catches tab so its
            // log sheet (which watches the same flag) can present.
            if requested { selectedTab = .catches }
        }
        .alert("Start planned session?", isPresented: Binding(
            get: { planPrompt != nil }, set: { if !$0 { planPrompt = nil } }
        ), presenting: planPrompt) { trip in
            Button("Start Now") {
                _ = appState.tripTracker.startPlanned(trip)
                planPrompt = nil
                selectedTab = .map
            }
            Button("Not Now", role: .cancel) { planPrompt = nil }
        } message: { trip in
            Text("\(trip.name) is planned for \(trip.plannedDate?.formatted(date: .omitted, time: .shortened) ?? "now").")
        }
    }

    /// Handle deep links from notifications, the Live Activity, widgets and
    /// invite links:
    ///   currents://session       → open the live session (log a catch)
    ///   currents://sessions      → the Sessions list (start a planned trip)
    ///   currents://community     → Community (friend requests / trip invites)
    ///   currents://gear          → Gear (low-stock reorder)
    ///   currents://licenses      → Licence wallet (expiry)
    ///   currents://map           → the Explore map (bite alerts)
    ///   currents://trip/<CODE>   → Join Trip confirmation
    ///   currents://friend/<CODE> → Add Friend confirmation
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "currents" else { return }
        let host = url.host ?? ""

        // Simple screen routes (no code needed).
        switch host {
        case "log":
            // Quick-log from the widget / shortcut: jump to Catches and present
            // the log sheet (CatchesTab watches this flag).
            selectedTab = .catches
            appState.siriRequestedLogCatch = true
            return
        case "session":
            selectedTab = .map
            appState.openLiveSession = true
            return
        case "sessions":
            selectedTab = .profile
            appState.moreDestination = .sessions
            return
        case "community":
            selectedTab = .profile
            appState.moreDestination = .community
            return
        case "gear":
            selectedTab = .profile
            appState.moreDestination = .gear
            return
        case "licenses":
            selectedTab = .profile
            appState.moreDestination = .licenses
            return
        case "map":
            selectedTab = .map
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
        }
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
