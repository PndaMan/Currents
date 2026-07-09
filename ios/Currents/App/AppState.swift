import SwiftUI
import Observation

/// Root app state — owns the database, location manager, ML classifier, and map manager.
@MainActor
@Observable
final class AppState {
    let db: AppDatabase
    let locationManager = LocationManager()
    let fishModelDownloader = FishModelDownloader()
    let embeddingIdentifier = EmbeddingSpeciesIdentifier()
    let mapManager = MapManager()
    let inaturalist = INaturalistPublisher()

    // Repositories (share the db)
    let catchRepository: CatchRepository
    let spotRepository: SpotRepository
    let gearRepository: GearRepository
    let speciesRepository: SpeciesRepository
    let tripRepository: TripRepository
    let gearCatalogRepository: GearCatalogRepository
    let ownedGearRepository: OwnedGearRepository
    let waterbodyRepository: WaterbodyRepository
    let observedSpeciesRepository: ObservedSpeciesRepository
    let licenseRepository: LicenseRepository

    init() {
        do {
            self.db = try AppDatabase.persistent()
        } catch {
            // Fall back to in-memory for debugging
            self.db = try! AppDatabase.empty()
        }

        self.catchRepository = CatchRepository(db: db)
        self.spotRepository = SpotRepository(db: db)
        self.gearRepository = GearRepository(db: db)
        self.speciesRepository = SpeciesRepository(db: db)
        self.tripRepository = TripRepository(db: db)
        self.gearCatalogRepository = GearCatalogRepository(db: db)
        self.ownedGearRepository = OwnedGearRepository(db: db)
        self.waterbodyRepository = WaterbodyRepository(db: db)
        self.observedSpeciesRepository = ObservedSpeciesRepository(db: db)
        self.licenseRepository = LicenseRepository(db: db)

        // Boot async work — fetch the fish-ID model in the background.
        Task {
            await fishModelDownloader.ensureModelDownloaded()
        }
        try? speciesRepository.seedIfNeeded()
        try? gearCatalogRepository.seedIfEmpty()
        try? waterbodyRepository.seedIfEmpty()

        // Pull any newly published catalog gear (stored locally, so the
        // whole catalog keeps working offline once synced).
        Task { [db] in
            await GearCatalogSync.syncIfDue(db: db)
        }

        // Start logging on-device barometric pressure so the bite forecast has
        // a real local pressure trend even with no signal.
        BarometerService.shared.start()

        // Load size/bag-limit regulations (embedded now, refreshed weekly).
        RegulationsService.shared.load()
        Task { await RegulationsService.shared.syncIfDue() }

        // Skip the location prompt in screenshot mode so no system dialog ever
        // covers a capture (the map uses a fixed camera instead).
        if !ScreenshotSupport.isActive {
            locationManager.requestPermission()
        }
        mapManager.refreshDownloadedRegions()

        // Refresh licence-expiry reminders from stored licences.
        if let licenses = try? licenseRepository.fetchAll(), !licenses.isEmpty {
            Task { await NotificationManager.shared.scheduleLicenseExpiryAlerts(licenses: licenses) }
        }

        // App Store screenshot capture (CI only — gated on SCREENSHOT_MODE env).
        ScreenshotSupport.seedDemoDataIfNeeded(self)
    }
}
