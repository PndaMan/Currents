import Foundation
import BackgroundTasks
import CoreLocation

/// Keeps what changes with the clock fresh while Currents is closed: the bite
/// alerts planned for saved spots and the widget's bite score. Runs when the
/// app opens or goes to the background, after a spot or alert setting
/// changes, and from a background app refresh the system runs when it sees
/// fit (roughly every hour or two for an app in regular use).
@MainActor
enum BackgroundRefresh {
    /// Listed under BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "com.aidanmcconnon.currents.refresh"

    /// Ask for the next background run. The system picks the actual time.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The background task: fresh weather in, widget and alerts out.
    static func run() async {
        schedule()
        guard let appState = AppState.shared, !ScreenshotSupport.isActive else { return }
        await refreshWidget(appState: appState)
        await rescheduleAlerts(appState: appState)
    }

    /// Re-plan the bite alerts for every saved spot.
    static func rescheduleAlerts(appState: AppState) async {
        let spots = (try? appState.spotRepository.fetchAll()) ?? []
        let alerts = (try? appState.spotRepository.alerts()) ?? [:]
        await NotificationManager.shared.rescheduleBiteAlerts(
            spots: spots, alerts: alerts, species: targetSpecies(appState))
    }

    /// Recompute the widget's score for the place Today last showed.
    static func refreshWidget(appState: AppState) async {
        guard let snap = SharedStore.load(), let lat = snap.latitude, let lon = snap.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let current = await WeatherService.shared.current(for: coordinate)
        let outlook = await WeatherService.shared.forecastDays(for: coordinate)
        let species = targetSpecies(appState)
        let today = ForecastEngine.day(0, coordinate: coordinate, current: current,
                                       outlook: outlook, species: species).result
        let tomorrow = ForecastEngine.day(1, coordinate: coordinate, current: current,
                                          outlook: outlook, species: species).result
        let hourly = WidgetSnapshotWriter.hourlyEntries(today: today.hourlyScores,
                                                        tomorrow: tomorrow.hourlyScores)
        WidgetSnapshotWriter.writeBite(score: today.score, location: snap.locationName,
                                       latitude: lat, longitude: lon, hourly: hourly)
    }

    private static func targetSpecies(_ appState: AppState) -> Species? {
        let id = UserDefaults.standard.integer(forKey: "targetSpeciesId")
        guard id > 0 else { return nil }
        return try? appState.speciesRepository.fetch(id: Int64(id))
    }
}
