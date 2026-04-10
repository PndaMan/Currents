import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .map

    enum Tab: String, CaseIterable {
        case map
        case catches
        case forecast
        case gear
        case profile

        var title: String {
            switch self {
            case .map: "Explore"
            case .catches: "Catches"
            case .forecast: "Forecast"
            case .gear: "Gear"
            case .profile: "Profile"
            }
        }

        var icon: String {
            switch self {
            case .map: "map.fill"
            case .catches: "fish.fill"
            case .forecast: "cloud.sun.fill"
            case .gear: "wrench.and.screwdriver.fill"
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
                    case .forecast:
                        ForecastTab()
                    case .gear:
                        GearTab()
                    case .profile:
                        ProfileTab()
                    }
                }
            }
        }
    }
}
