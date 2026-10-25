import SwiftUI

@main
struct CurrentsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    /// System, light or dark, chosen in Settings > Appearance.
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.dark.rawValue
    @Environment(\.scenePhase) private var scenePhase
    /// The opening animation plays once per launch, never in screenshot mode.
    @State private var showsLaunch = !ScreenshotSupport.isActive

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    if showsLaunch {
                        LaunchAnimation(onReveal: { _ in }, onFinish: {
                            showsLaunch = false
                            appState.launchFinished = true
                        })
                    }
                }
                .environment(appState)
                .preferredColorScheme((AppearanceMode(rawValue: appearanceMode) ?? .dark).colorScheme)
                .tint(ThemeOption(rawValue: selectedTheme)?.primary ?? .blue)
                // Finishes tips left unfinished (an approved Ask to Buy, a
                // purchase cut off by a crash). StoreKit wants this at launch.
                .task { TipJar.shared.startListening() }
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
               !ScreenshotSupport.isActive, CrewCloud.buildHasCloudKit {
                Task {
                    // Ensure APNs registration + CloudKit push subscriptions are
                    // in place, then reconcile the in-app lists.
                    await CommunityService.shared.enablePush()
                    await CommunityService.shared.refreshTripInvites()
                    await CommunityService.shared.refreshFriendRequests()
                }
            }
            // Bite alerts follow the latest weather each time the app opens.
            if phase == .active, !ScreenshotSupport.isActive {
                Task { await BackgroundRefresh.rescheduleAlerts(appState: appState) }
            }
            // Daily automatic backup, kicked off when the app is backgrounded.
            if phase == .background {
                AutoBackup.runIfDue(db: appState.db)
                BackgroundRefresh.schedule()
                // Re-plan the bite alerts on the way out. Asking for extra
                // time keeps the app awake until the plan is saved.
                let app = UIApplication.shared
                var token = UIBackgroundTaskIdentifier.invalid
                token = app.beginBackgroundTask(withName: "Bite alerts") { app.endBackgroundTask(token) }
                let started = token
                Task {
                    await BackgroundRefresh.rescheduleAlerts(appState: appState)
                    app.endBackgroundTask(started)
                }
            }
        }
        // Background app refresh: fresh weather for the widget and the alerts
        // while the app is closed.
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
        }
    }
}
