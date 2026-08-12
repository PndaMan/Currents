import SwiftUI

@main
struct CurrentsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            // Check for group-trip invites on foreground; fires a local
            // notification for any new ones and surfaces them in Community.
            // Only when the user has actually joined — reading the flag from
            // UserDefaults avoids touching CloudKit (and the singleton) at
            // launch, which crashes the unsigned simulator test build.
            // Never in screenshot mode: the demo seed marks the account as
            // joined, but the unsigned simulator build has no iCloud
            // entitlement — any CloudKit op is an uncatchable crash.
            if phase == .active, UserDefaults.standard.bool(forKey: "communityJoined"),
               !ScreenshotSupport.isActive {
                Task {
                    // Ensure APNs registration + CloudKit push subscriptions are
                    // in place, then reconcile the in-app lists.
                    await CommunityService.shared.enablePush()
                    await CommunityService.shared.refreshTripInvites()
                    await CommunityService.shared.refreshFriendRequests()
                }
            }
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
