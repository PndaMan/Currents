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

    // MARK: - Cleanup

    /// Remove all pending notification requests.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
