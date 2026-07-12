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

    /// Request notification authorization. Returns `true` if granted.
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
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
        content.body = "Test notification — if you see this, notifications are working on this device. 🎣"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    // MARK: - Spot Alerts

    /// Evaluate each spot's current forecast and schedule a local notification
    /// for any spot whose bite score meets or exceeds the stored threshold.
    func scheduleSpotAlerts(spots: [Spot], using weatherService: WeatherService) async {
        let threshold = UserDefaults.standard.integer(forKey: "alertThreshold")
        let minScore = threshold > 0 ? threshold : 75

        for spot in spots {
            let coordinate = CLLocationCoordinate2D(
                latitude: spot.latitude,
                longitude: spot.longitude
            )

            guard let weather = await weatherService.current(for: coordinate) else {
                continue
            }

            let result = ForecastEngine.forecast(
                date: .now,
                coordinate: coordinate,
                currentPressureHpa: weather.pressureHpa,
                pressureChange6h: weather.pressureChange6h,
                waterTempC: weather.waterTempC,
                windSpeedKmh: weather.windSpeedKmh,
                windDirection: weather.windDirectionDeg,
                species: nil,
                isInSpawningZone: false
            )

            guard result.score >= minScore else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Great bite at \(spot.name)!"
            content.body = "Score: \(result.score)/100 \u{2014} Conditions are excellent right now"
            content.sound = .default

            // Fire 30 seconds from now (immediate alert after background check)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 30,
                repeats: false
            )

            // Use spot.id as identifier to prevent duplicate notifications
            let request = UNNotificationRequest(
                identifier: spot.id,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    // MARK: - Prime-window (look-ahead) alerts

    /// Schedule a heads-up notification before the best feeding window over the
    /// next day at each saved spot, so anglers can plan. Opt-in via the
    /// "primeWindowAlerts" setting. Unlike `scheduleSpotAlerts` (which fires
    /// when conditions are good *now*), this looks ahead using the solunar +
    /// forecast engine and fires ~45 min before the window.
    func schedulePrimeWindowAlerts(spots: [Spot], using weatherService: WeatherService) async {
        guard UserDefaults.standard.bool(forKey: "primeWindowAlerts") else { return }
        // Clear previous look-ahead alerts so we don't stack duplicates.
        let existing = await center.pendingNotificationRequests()
        let staleIDs = existing.map(\.identifier).filter { $0.hasPrefix("prime_") }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        let threshold = UserDefaults.standard.integer(forKey: "alertThreshold")
        let minScore = threshold > 0 ? threshold : 70
        let now = Date()

        // Look at the best window across today (remaining) and tomorrow.
        for spot in spots.prefix(10) {
            let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
            let weather = await weatherService.current(for: coordinate)

            var best: (window: SolunarEngine.FeedingWindow, score: Int)?
            for dayOffset in 0...1 {
                guard let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let result = ForecastEngine.forecast(
                    date: date,
                    coordinate: coordinate,
                    currentPressureHpa: weather?.pressureHpa,
                    pressureChange6h: weather?.pressureChange6h,
                    waterTempC: weather?.waterTempC,
                    windSpeedKmh: weather?.windSpeedKmh,
                    windDirection: weather?.windDirectionDeg,
                    species: nil,
                    isInSpawningZone: false
                )
                for window in result.feedingWindows where window.start > now.addingTimeInterval(3600) {
                    // Score at the window's peak hour.
                    let peakHour = Calendar.current.component(.hour, from: window.peak)
                    let score = result.hourlyScores.first(where: { $0.hour == peakHour })?.score ?? result.score
                    if score >= minScore, best == nil || score > best!.score {
                        best = (window, score)
                    }
                }
            }

            guard let best else { continue }
            let fireDate = best.window.start.addingTimeInterval(-45 * 60)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Prime bite window at \(spot.name)"
            let timeStr = best.window.start.formatted(date: .omitted, time: .shortened)
            content.body = "\(best.window.kind.rawValue) — score \(best.score)/100 around \(timeStr). Get ready!"
            content.sound = .default

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "prime_\(spot.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
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
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let content = UNMutableNotificationContent()
        content.title = "Session soon: \(trip.name)"
        content.body = "Your planned session starts at \(planned.formatted(date: .omitted, time: .shortened)). Open Currents to start tracking."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "session-plan-\(trip.id)", content: content, trigger: trigger))
    }

    // MARK: - Cold-streak nudge (during a session)

    /// Nudge the angler if no catch is logged for a while during an active
    /// session. Rescheduled on each catch, cancelled when the session ends.
    /// Opt-out via the "coldStreakNudges" setting (default on).
    func scheduleColdStreakNudge(minutes: Int = 45) async {
        center.removePendingNotificationRequests(withIdentifiers: ["cold-streak"])
        if UserDefaults.standard.object(forKey: "coldStreakNudges") != nil,
           !UserDefaults.standard.bool(forKey: "coldStreakNudges") { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Slow bite?"
        content.body = "No catches in a while — try switching lure, changing depth, or moving spots."
        content.sound = .default
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
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        let remaining = item.stock ?? 0
        content.title = remaining <= 0 ? "Out of stock: \(item.displayName)" : "Running low: \(item.displayName)"
        content.body = remaining <= 0
            ? "None left — restock your \(item.category.rawValue.lowercased()) before your next trip."
            : "\(remaining) left — time to restock your \(item.category.rawValue.lowercased())."
        content.sound = .default
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
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Trip invite from \(fromName)"
        content.body = "Join “\(tripName)” on Currents — open the app to accept."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try? await center.add(UNNotificationRequest(
            identifier: "tripinvite-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// Local alert when someone sends you a friend request.
    func scheduleFriendRequestAlert(fromName: String) async {
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "New friend request"
        content.body = "\(fromName) wants to connect on Currents — open the app to accept."
        content.sound = .default
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

        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

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
