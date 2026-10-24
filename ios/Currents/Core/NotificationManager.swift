import UserNotifications
import SwiftUI
import CoreLocation

/// Schedules local notifications when weather conditions produce high bite scores
/// at the user's saved spots. These are on-device local notifications (no server).
/// Community pushes (friend requests, trip invites) are delivered separately via
/// CloudKit subscriptions once you opt in.
final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    /// The ONE place the system permission dialog can come from. Screenshot
    /// mode must never prompt — the dialog covers the capture — so every
    /// authorization request in the app funnels through here.
    private func requestAuth(_ options: UNAuthorizationOptions) async -> Bool {
        guard !ScreenshotSupport.isActive else { return false }
        return (try? await center.requestAuthorization(options: options)) ?? false
    }

    /// Request notification authorization. Returns `true` if granted.
    func requestPermission() async -> Bool {
        await requestAuth([.alert, .sound, .badge])
    }

    /// Check current authorization status without prompting.
    func checkPermissionStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Fire a local test notification a few seconds out so the user can confirm
    /// notifications actually reach this device (used by the diagnostics screen).
    func sendTestNotification() async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Currents"
        content.body = "Test notification — if you see this, notifications are working on this device."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// One of every on-device alert, five seconds apart, worded as the real
    /// ones are, so each can be checked on the phone. Tapping one follows its
    /// real deep link.
    func sendEveryAlertPreview(spotName: String?) async {
        guard await requestPermission() else { return }
        let spot = spotName ?? "your spot"
        let start = Date.now.addingTimeInterval(45 * 60)
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = start.addingTimeInterval(2 * 3600).formatted(date: .omitted, time: .shortened)
        let bite = "Bite score up to 82 from \(from) to \(to)."
        let samples: [(title: String, body: String, link: String)] = [
            ("Bite window at \(spot) in 45 minutes", bite, "currents://map"),
            ("Bite window open at \(spot)", bite, "currents://map"),
            ("Session soon: Dawn session", "Your planned session starts at \(from). Open Currents to start tracking.", "currents://sessions"),
            ("Slow bite?", "No catches in a while — try switching lure, changing depth, or moving spots.", "currents://session"),
            ("Running low: Soft plastics", "2 left — time to restock your lures.", "currents://gear"),
            ("Trip invite from Sam", "Join “Weekend at the dam” on Currents — open the app to accept.", "currents://community"),
            ("New friend request", "Sam wants to connect on Currents — open the app to accept.", "currents://community"),
            ("Fishing licence reminder", "Freshwater licence expires in 1 week.", "currents://licenses"),
        ]
        for (index, sample) in samples.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = sample.title
            content.body = sample.body
            content.sound = .default
            content.userInfo = ["deepLink": sample.link]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(3 + index * 5), repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: "preview-\(index)-\(UUID().uuidString)", content: content, trigger: trigger))
        }
    }

    // MARK: - Bite alerts

    /// How many bite notifications may be pending at once. iOS keeps at most
    /// 64 per app; the rest of the budget is left for licence, session and
    /// stock reminders.
    private static let biteAlertBudget = 40
    private static let headsUpLead: TimeInterval = 45 * 60
    private static let defaultThreshold = 75

    /// Plan the next three days of bite notifications for saved spots and
    /// replace whatever was scheduled before. Windows come from the same hourly
    /// scores Today shows (BiteWindows over the target species' forecast), so
    /// an alert fires when Today says the window opens. Called on launch, on
    /// leaving the app, after a spot or a setting changes, and from background
    /// refresh, so the plan follows the latest weather.
    func rescheduleBiteAlerts(spots: [Spot], alerts: [String: SpotAlert], species: Species?) async {
        let pending = await center.pendingNotificationRequests()
        let old = Set(pending.map(\.identifier).filter { Self.isBiteAlert($0) })

        let defaults = UserDefaults.standard
        let biteOn = defaults.bool(forKey: "alertsEnabled")
        let headsUpOn = defaults.bool(forKey: "primeWindowAlerts")
        guard biteOn || headsUpOn, await isAuthorized() else {
            center.removePendingNotificationRequests(withIdentifiers: Array(old))
            return
        }
        let stored = defaults.integer(forKey: "alertThreshold")
        let fallback = stored > 0 ? stored : Self.defaultThreshold

        let wanted: [WantedSpot] = spots.compactMap { spot in
            let choice = alerts[spot.id] ?? .defaults(for: spot.id)
            let bite = biteOn && choice.biteAlerts
            let headsUp = headsUpOn && choice.headsUp
            guard bite || headsUp else { return nil }
            return WantedSpot(spot: spot, bite: bite, headsUp: headsUp,
                              threshold: choice.threshold ?? fallback)
        }
        let weather = await Self.weather(for: wanted.map(\.spot))

        var planned: [(fire: Date, request: UNNotificationRequest)] = []
        for item in wanted {
            let spot = item.spot
            let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            let reading = weather[spot.id]
            let windows = BiteWindows.upcoming(coordinate: coordinate, current: reading?.current,
                                               outlook: reading?.outlook ?? [], species: species, days: 3)
            for window in windows where window.peakScore >= item.threshold {
                if item.headsUp, let request = headsUpRequest(spot: spot, window: window) {
                    planned.append((window.start.addingTimeInterval(-Self.headsUpLead), request))
                }
                if item.bite, let request = windowOpenRequest(spot: spot, window: window) {
                    planned.append((window.start, request))
                }
            }
        }

        // Soonest first, so a full budget drops the furthest-off alerts. The
        // old plan is only cleared once the new one is ready, and an add with
        // a known identifier replaces it, so being suspended halfway never
        // leaves the spots without alerts.
        let chosen = planned.sorted { $0.fire < $1.fire }.prefix(Self.biteAlertBudget)
        let keep = Set(chosen.map(\.request.identifier))
        center.removePendingNotificationRequests(withIdentifiers: Array(old.subtracting(keep)))
        for item in chosen {
            try? await center.add(item.request)
        }
    }

    private struct WantedSpot {
        let spot: Spot
        let bite: Bool
        let headsUp: Bool
        let threshold: Int
    }

    private struct SpotWeather: Sendable {
        let current: WeatherService.WeatherData?
        let outlook: [WeatherService.WeatherData]
    }

    /// Weather for every spot at once. One spot after another would not fit
    /// in the half minute a background refresh gets once there are many.
    private static func weather(for spots: [Spot]) async -> [String: SpotWeather] {
        await withTaskGroup(of: (String, SpotWeather).self) { group in
            for spot in spots {
                let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                let id = spot.id
                group.addTask {
                    async let current = WeatherService.shared.current(for: coordinate)
                    async let outlook = WeatherService.shared.forecastDays(for: coordinate)
                    return (id, SpotWeather(current: await current, outlook: await outlook))
                }
            }
            var byId: [String: SpotWeather] = [:]
            for await (id, reading) in group { byId[id] = reading }
            return byId
        }
    }

    private static func isBiteAlert(_ identifier: String) -> Bool {
        identifier.hasPrefix("bite_") || identifier.hasPrefix("prime_")
    }

    /// Whether notifications may be shown, without ever prompting. Background
    /// work must not raise the permission dialog.
    private func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    private func windowOpenRequest(spot: Spot, window: BiteWindows.Upcoming) -> UNNotificationRequest? {
        guard window.start > .now else { return nil }
        let content = biteContent(spot: spot, window: window)
        content.title = "Bite window open at \(spot.name)"
        return request(id: "bite_\(spot.id)_\(Self.stamp(window.start))", content: content, at: window.start)
    }

    private func headsUpRequest(spot: Spot, window: BiteWindows.Upcoming) -> UNNotificationRequest? {
        let fire = window.start.addingTimeInterval(-Self.headsUpLead)
        guard fire > .now else { return nil }
        let content = biteContent(spot: spot, window: window)
        content.title = "Bite window at \(spot.name) in 45 minutes"
        return request(id: "prime_\(spot.id)_\(Self.stamp(window.start))", content: content, at: fire)
    }

    private func biteContent(spot: Spot, window: BiteWindows.Upcoming) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let from = window.start.formatted(date: .omitted, time: .shortened)
        let to = window.end.formatted(date: .omitted, time: .shortened)
        content.body = "Bite score up to \(window.peakScore) from \(from) to \(to)."
        content.sound = .default
        content.threadIdentifier = "spot-\(spot.id)"
        content.relevanceScore = Double(window.peakScore) / 100
        content.userInfo = ["deepLink": "currents://map/spot/\(spot.id)"]
        return content
    }

    private func request(id: String, content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func stamp(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970 / 60))
    }

    // MARK: - Cleanup

    /// Remove all pending notification requests.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Planned Session Reminder

    /// Remind the angler ~30 minutes before a planned session so they can open
    /// the app and start it.
    func schedulePlannedSessionAlert(trip: Trip) async {
        center.removePendingNotificationRequests(withIdentifiers: ["session-plan-\(trip.id)"])
        guard let planned = trip.plannedDate else { return }
        let fire = planned.addingTimeInterval(-30 * 60)
        guard fire > .now else { return }
        guard await requestAuth([.alert, .sound]) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session soon: \(trip.name)"
        content.body = "Your planned session starts at \(planned.formatted(date: .omitted, time: .shortened)). Open Currents to start tracking."
        content.sound = .default
        content.userInfo = ["deepLink": "currents://plan/\(trip.id)"]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "session-plan-\(trip.id)", content: content, trigger: trigger))
    }

    /// Drop a planned session's reminder, for a plan that was deleted,
    /// started or moved into the past.
    func cancelPlannedSessionAlert(tripId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["session-plan-\(tripId)"])
    }

    // MARK: - Cold-streak nudge (during a session)

    /// Nudge the angler if no catch is logged for a while during an active
    /// session. Rescheduled on each catch, cancelled when the session ends.
    /// Opt-out via the "coldStreakNudges" setting (default on).
    func scheduleColdStreakNudge(minutes: Int = 45) async {
        center.removePendingNotificationRequests(withIdentifiers: ["cold-streak"])
        if UserDefaults.standard.object(forKey: "coldStreakNudges") != nil,
           !UserDefaults.standard.bool(forKey: "coldStreakNudges") { return }
        guard await requestAuth([.alert, .sound]) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Slow bite?"
        content.body = "No catches in a while — try switching lure, changing depth, or moving spots."
        content.sound = .default
        content.userInfo = ["deepLink": "currents://session"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "cold-streak", content: content, trigger: trigger))
    }

    func cancelColdStreakNudge() {
        center.removePendingNotificationRequests(withIdentifiers: ["cold-streak"])
    }

    // MARK: - Low Stock Reminders

    /// Fire a reorder reminder when a consumable drops to its low-stock point.
    /// Opt-out via the "lowStockAlerts" setting (on by default).
    func scheduleLowStockAlert(item: OwnedGear) async {
        let id = "lowstock-\(item.id)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        if UserDefaults.standard.object(forKey: "lowStockAlerts") != nil,
           !UserDefaults.standard.bool(forKey: "lowStockAlerts") { return }
        guard await requestAuth([.alert, .sound]) else { return }
        let content = UNMutableNotificationContent()
        let remaining = item.stock ?? 0
        content.title = remaining <= 0 ? "Out of stock: \(item.displayName)" : "Running low: \(item.displayName)"
        content.body = remaining <= 0
            ? "None left — restock your \(item.category.rawValue.lowercased()) before your next trip."
            : "\(remaining) left — time to restock your \(item.category.rawValue.lowercased())."
        content.sound = .default
        content.userInfo = ["deepLink": "currents://gear"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancelLowStockAlert(itemId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["lowstock-\(itemId)"])
    }

    // MARK: - Group Trip Invites

    /// Local alert when a friend invites you to a group trip (surfaced when the
    /// app next checks for invites; see CommunityService.refreshTripInvites).
    func scheduleTripInviteAlert(fromName: String, tripName: String) async {
        guard await requestAuth([.alert, .sound]) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Trip invite from \(fromName)"
        content.body = "Join “\(tripName)” on Currents — open the app to accept."
        content.sound = .default
        content.userInfo = ["deepLink": "currents://community"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "tripinvite-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// Local alert when someone sends you a friend request.
    func scheduleFriendRequestAlert(fromName: String) async {
        guard await requestAuth([.alert, .sound]) else { return }
        let content = UNMutableNotificationContent()
        content.title = "New friend request"
        content.body = "\(fromName) wants to connect on Currents — open the app to accept."
        content.sound = .default
        content.userInfo = ["deepLink": "currents://community"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "friendreq-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: - Licence Expiry Reminders

    /// Schedule expiry reminders for each licence at 1 month, 2 weeks, 1 week,
    /// 3 days before, and on the expiry day. Reschedules cleanly each call.
    func scheduleLicenseExpiryAlerts(licenses: [FishingLicense]) async {
        // Clear previously-scheduled licence reminders.
        let existing = await center.pendingNotificationRequests()
        let ids = existing.map(\.identifier).filter { $0.hasPrefix("license-") }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard await requestAuth([.alert, .sound]) else { return }

        let calendar = Calendar.current
        let offsets: [(days: Int, label: String)] = [
            (30, "expires in 1 month"),
            (14, "expires in 2 weeks"),
            (7, "expires in 1 week"),
            (3, "expires in 3 days"),
            (0, "expires today"),
        ]

        for license in licenses {
            guard let expiry = license.expiryDate else { continue }
            for offset in offsets {
                guard let fireDate = calendar.date(byAdding: .day, value: -offset.days, to: expiry) else { continue }
                // 9am local on the reminder day, and only if it's in the future.
                var comps = calendar.dateComponents([.year, .month, .day], from: fireDate)
                comps.hour = 9
                guard let stamped = calendar.date(from: comps), stamped > .now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Fishing licence reminder"
                content.body = "\(license.title) \(offset.label)."
                content.sound = .default
                content.userInfo = ["deepLink": "currents://licenses"]

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour], from: stamped),
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: "license-\(license.id)-\(offset.days)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }
}
