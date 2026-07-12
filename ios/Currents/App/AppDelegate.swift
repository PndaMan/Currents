import UIKit
import UserNotifications

/// Handles remote (APNs) notifications and foreground presentation. Community
/// events — friend requests, trip invites, request-accepted — are delivered as
/// real push via CloudKit subscriptions, so they arrive instantly even when the
/// app is closed. A push also refreshes the in-app lists so Accept/Decline is
/// up to date.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Become the notification-center delegate so notifications also show
        // while the app is in the FOREGROUND (iOS suppresses them otherwise).
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - APNs registration (status recorded for the in-app diagnostics)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit manages delivery via subscriptions; no token handling needed.
        // Reaching here proves the build has the aps-environment entitlement and
        // a valid APNs registration — surface that on the Notifications screen.
        UserDefaults.standard.set(true, forKey: "apnsRegistered")
        UserDefaults.standard.removeObject(forKey: "apnsRegisterError")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(false, forKey: "apnsRegistered")
        UserDefaults.standard.set(error.localizedDescription, forKey: "apnsRegisterError")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications as a banner + sound even when the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
        Task { @MainActor in
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
        }
    }

    /// Refresh community lists when the user taps a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
            completionHandler()
        }
    }
}
