import SwiftUI

@main
struct CurrentsApp: App {
    @State private var appState = AppState()
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(ThemeOption(rawValue: selectedTheme)?.primary ?? .blue)
        }
        .onChange(of: scenePhase) { _, phase in
            // Daily automatic backup, kicked off when the app is backgrounded.
            if phase == .background {
                AutoBackup.runIfDue(db: appState.db)
                // Refresh look-ahead prime-window alerts for saved spots.
                if UserDefaults.standard.bool(forKey: "primeWindowAlerts") {
                    let spots = (try? appState.spotRepository.fetchAll()) ?? []
                    Task {
                        await NotificationManager.shared.schedulePrimeWindowAlerts(
                            spots: spots, using: WeatherService.shared
                        )
                    }
                }
            }
        }
    }
}
