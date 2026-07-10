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
            case .profile: "Profile"
            }
        }

        var icon: String {
            switch self {
            case .map: "map.fill"
            case .catches: "fish.fill"
            case .collection: "square.grid.2x2.fill"
            case .forecast: "cloud.sun.fill"
            case .profile: "person.fill"
            }
        }
    }

    @State private var planPrompt: Trip?

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

    /// On launch, if a planned session is within ~2 hours of now and nothing is
    /// already recording, offer to start it.
    private func checkPlannedSession() {
        guard !appState.tripTracker.isTracking, !ScreenshotSupport.isActive else { return }
        let planned = (try? appState.tripRepository.fetchPlanned()) ?? []
        planPrompt = planned.first { trip in
            guard let d = trip.plannedDate else { return false }
            return abs(d.timeIntervalSinceNow) < 2 * 3600
        }
    }
}
