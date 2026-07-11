import UIKit

/// Handles remote (APNs) notifications. Community events — friend requests, trip
/// invites, request-accepted — are delivered as real push via CloudKit
/// subscriptions, so they arrive instantly even when the app is closed. When a
/// push lands we also refresh the in-app lists so Accept/Decline is up to date.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit manages delivery via subscriptions; no token handling needed.
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
            completionHandler(.newData)
        }
    }
}
