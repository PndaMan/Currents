import SwiftUI

@main
struct CurrentsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(CurrentsTheme.accent)
        }
    }
}
