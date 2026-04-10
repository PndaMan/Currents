import SwiftUI
import Observation

/// Root app state — owns the database, location manager, ML classifier, and map manager.
@Observable
final class AppState {
    let db: AppDatabase
    let locationManager = LocationManager()
    let fishClassifier = FishClassifier()
    let mapManager = MapManager()

    // Repositories (lazy, share the db)
    lazy var catchRepository = CatchRepository(db: db)
    lazy var spotRepository = SpotRepository(db: db)
    lazy var gearRepository = GearRepository(db: db)
    lazy var speciesRepository = SpeciesRepository(db: db)

    init() {
        do {
            self.db = try AppDatabase.persistent()
        } catch {
            // Fall back to in-memory for debugging
            self.db = try! AppDatabase.empty()
        }

        // Boot async work
        Task {
            await fishClassifier.loadModel()
        }
        Task { @MainActor in
            try? speciesRepository.seedIfEmpty()
        }

        locationManager.requestPermission()
        mapManager.refreshDownloadedRegions()
    }
}
