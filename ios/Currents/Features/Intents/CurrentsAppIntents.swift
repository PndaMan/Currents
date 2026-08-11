import AppIntents
import CoreLocation

/// Siri Shortcuts / App Intents for Currents. These run inside the app's
/// process; `AppState.shared` is created lazily on first access so a Siri-only
/// launch (app never shown) still works.
///
/// Exposed phrases are declared in `CurrentsShortcuts` below.

// MARK: - Shared access

@MainActor
private func liveAppState() -> AppState {
    AppState.shared ?? AppState()   // AppState.init sets AppState.shared
}

private let fallbackCoordinate = CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)

// MARK: - Start a fishing session

struct StartFishingSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Fishing Session"
    static var description = IntentDescription("Begin recording a live fishing session with GPS tracking.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = liveAppState()
        guard !app.tripTracker.isTracking else {
            return .result(dialog: "You already have a fishing session running.")
        }
        let trip = app.tripTracker.start(name: SessionFormat.defaultName(), spotId: nil)
        return .result(dialog: "Started \(trip.name). Tight lines!")
    }
}

// MARK: - End a fishing session

struct EndFishingSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "End Fishing Session"
    static var description = IntentDescription("Stop the current fishing session and save it.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = liveAppState()
        guard let trip = app.tripTracker.end() else {
            return .result(dialog: "You don't have a session running.")
        }
        let mins = Int(trip.durationSeconds / 60)
        let km = trip.trackDistanceMeters / 1000
        if mins > 0 {
            return .result(dialog: "Session saved — \(mins) min, \(String(format: "%.1f", km)) km covered.")
        }
        return .result(dialog: "Session saved.")
    }
}

// MARK: - Check the bite score

struct CheckBiteScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Bite Score"
    static var description = IntentDescription("Get the current fishing bite forecast for your location.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = liveAppState()
        let coord = app.locationManager.currentLocation?.coordinate ?? fallbackCoordinate
        let weather = await WeatherService.shared.current(for: coord)
        let result = ForecastEngine.forecast(
            coordinate: coord,
            currentPressureHpa: weather?.pressureHpa,
            pressureChange6h: weather?.pressureChange6h,
            waterTempC: weather?.waterTempC,
            windSpeedKmh: weather?.windSpeedKmh,
            windDirection: weather?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        let verdict: String
        switch result.score {
        case 80...: verdict = "Conditions are excellent right now."
        case 60..<80: verdict = "Conditions are good."
        case 40..<60: verdict = "Conditions are fair."
        default: verdict = "Conditions are slow at the moment."
        }
        let reason = result.reasons.first.map { " \($0)." } ?? ""
        return .result(dialog: "The bite score is \(result.score) out of 100. \(verdict)\(reason)")
    }
}

// MARK: - Log a catch (opens the app)

struct LogCatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Catch"
    static var description = IntentDescription("Open Currents to log a new catch.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        liveAppState().siriRequestedLogCatch = true
        return .result()
    }
}

// MARK: - Quick-log a catch (headless)

/// Records a minimal catch at the last known location — auto-added to the
/// active session — without opening the app. Species/size are filled in later
/// on the phone. Ideal hands-free while fishing.
struct QuickLogCatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Log Catch"
    static var description = IntentDescription("Log a catch at your current spot without opening the app.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = liveAppState()
        let coord = app.locationManager.currentLocation?.coordinate
            ?? app.tripTracker.currentLocation?.coordinate
            ?? fallbackCoordinate
        var record = Catch(
            speciesId: nil,
            spotId: nil,
            caughtAt: .now,
            latitude: coord.latitude,
            longitude: coord.longitude,
            tripId: app.tripTracker.activeTrip?.id,
            notes: "Quick-logged via Siri"
        )
        try? app.catchRepository.save(&record)
        let published = record
        Task { await CommunityService.shared.publishLoggedCatch(published, speciesName: nil) }
        if app.tripTracker.isTracking {
            await NotificationManager.shared.scheduleColdStreakNudge()
            return .result(dialog: "Logged a catch on your session. Fill in the details later. Tight lines!")
        }
        return .result(dialog: "Catch logged. Open Currents to add the species and size.")
    }
}

// MARK: - Log a named species (hands-free, headless)

/// "Log a largemouth bass in Currents" — records a catch of the named species
/// at your current location, without opening the app. Resolves the spoken name
/// against the species catalog; logs it unmatched (with a note) if it can't.
struct LogSpeciesCatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Fish"
    static var description = IntentDescription("Log a catch of a named species without opening the app.")
    static var openAppWhenRun = false

    @Parameter(title: "Species", requestValueDialog: "What did you catch?")
    var species: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = liveAppState()
        let coord = app.locationManager.currentLocation?.coordinate
            ?? app.tripTracker.currentLocation?.coordinate
            ?? fallbackCoordinate
        let match = app.speciesRepository.resolve(spokenName: species)
        var record = Catch(
            speciesId: match?.id, spotId: nil, caughtAt: .now,
            latitude: coord.latitude, longitude: coord.longitude,
            tripId: app.tripTracker.activeTrip?.id,
            notes: match == nil ? "Siri: \"\(species)\"" : "Logged via Siri")
        try? app.catchRepository.save(&record)
        let published = record
        let publishedName = match?.commonName
        Task { await CommunityService.shared.publishLoggedCatch(published, speciesName: publishedName) }
        if app.tripTracker.isTracking { await NotificationManager.shared.scheduleColdStreakNudge() }
        if let match {
            return .result(dialog: "Logged a \(match.commonName). Tight lines!")
        }
        return .result(dialog: "Logged your catch. I couldn't match “\(species)” — open Currents to set the species.")
    }
}

// MARK: - Shortcut phrases

struct CurrentsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckBiteScoreIntent(),
            phrases: [
                "What's the bite score in \(.applicationName)",
                "Check the bite score with \(.applicationName)",
                "Are the fish biting in \(.applicationName)",
            ],
            shortTitle: "Bite Score",
            systemImageName: "cloud.sun.fill"
        )
        AppShortcut(
            intent: StartFishingSessionIntent(),
            phrases: [
                "Start a fishing session in \(.applicationName)",
                "Start fishing with \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "figure.fishing"
        )
        AppShortcut(
            intent: EndFishingSessionIntent(),
            phrases: [
                "End my fishing session in \(.applicationName)",
                "Stop fishing with \(.applicationName)",
            ],
            shortTitle: "End Session",
            systemImageName: "stop.circle.fill"
        )
        AppShortcut(
            intent: LogCatchIntent(),
            phrases: [
                "Log a catch in \(.applicationName)",
                "Record a catch with \(.applicationName)",
            ],
            shortTitle: "Log Catch",
            systemImageName: "fish.fill"
        )
        AppShortcut(
            intent: QuickLogCatchIntent(),
            phrases: [
                "Quick log a catch in \(.applicationName)",
                "I caught one in \(.applicationName)",
                "Fish on in \(.applicationName)",
            ],
            shortTitle: "Quick Catch",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: LogSpeciesCatchIntent(),
            phrases: [
                // A raw String parameter can't be interpolated into a spoken
                // phrase (App Intents only allows AppEntity/AppEnum there), so
                // Siri prompts "What did you catch?" and the angler says the
                // species — resolved against the catalog.
                "Log a fish in \(.applicationName)",
                "Log the species I caught in \(.applicationName)",
            ],
            shortTitle: "Log a Fish",
            systemImageName: "fish.fill"
        )
    }
}
