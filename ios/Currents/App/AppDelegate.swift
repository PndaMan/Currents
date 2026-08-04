import UIKit
import UserNotifications
import CloudKit

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
            // Crew/trip event pushes carry content-available, so this also runs
            // in the background — pre-warm the crew feed the event landed in,
            // so opening the app (or the notification) shows it instantly.
            if let crewCode = Self.queryFields(userInfo)?["crewCode"] as? String {
                _ = await CommunityService.shared.crewFeed(code: crewCode)
            }
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
            completionHandler(.newData)
        }
    }

    // MARK: - CloudKit event payload helpers

    /// The record fields a CloudKit query push carried (its `desiredKeys`),
    /// or nil for pushes without any (friend requests, invites).
    private static func queryFields(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
        guard let dict = userInfo as? [String: NSObject],
              let note = CKNotification(fromRemoteNotificationDictionary: dict) as? CKQueryNotification
        else { return nil }
        return note.recordFields
    }

    /// True when the push describes something this user did themself. CloudKit
    /// subscription predicates can't express "author != me", so your own
    /// subscription fires when you post, react, host a trip or land a catch —
    /// each event sub includes the author-ish field in its desiredKeys, and
    /// the banner is dropped here instead.
    private static func isSelfEvent(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let fields = queryFields(userInfo),
              let me = UserDefaults.standard.string(forKey: "communityFriendCode")
        else { return false }
        for key in ["authorCode", "reactorCode", "hostCode", "friendCode"] {
            if let code = fields[key] as? String { return code == me }
        }
        return false
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications as a banner + sound even when the app is open —
    /// except your own crew/trip events echoing back (you just posted; you
    /// don't need a banner telling you so).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        completionHandler(Self.isSelfEvent(userInfo) ? [] : [.banner, .list, .sound, .badge])
        Task { @MainActor in
            if let crewCode = Self.queryFields(userInfo)?["crewCode"] as? String {
                _ = await CommunityService.shared.crewFeed(code: crewCode)
            }
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
        }
    }

    /// Route to the relevant screen (and refresh community lists) when the user
    /// taps a notification. Local notifications carry a `deepLink` in userInfo;
    /// CloudKit community pushes (friend request / trip invite) route to
    /// Community.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let link = userInfo["deepLink"] as? String, let url = URL(string: link) {
                AppState.shared?.pendingDeepLink = url
            } else if userInfo["ck"] != nil || userInfo["aps"] != nil {
                // A CloudKit community push (friend request / trip invite).
                AppState.shared?.pendingDeepLink = URL(string: "currents://community")
            }
            await CommunityService.shared.refreshTripInvites()
            await CommunityService.shared.refreshFriendRequests()
            completionHandler()
        }
    }
}
