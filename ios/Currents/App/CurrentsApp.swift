import SwiftUI

@main
struct CurrentsApp: App {
    @State private var appState = AppState()
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(ThemeOption(rawValue: selectedTheme)?.primary ?? .blue)
        }
    }
}
