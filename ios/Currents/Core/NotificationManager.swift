import UserNotifications
import SwiftUI
import CoreLocation

/// Schedules local notifications when weather conditions produce high bite scores
/// at the user's saved spots. No APNs — works fully offline and sideloaded.
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
