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
    }
}
