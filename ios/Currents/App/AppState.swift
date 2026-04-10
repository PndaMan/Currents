import SwiftUI
import Observation

/// Root app state — owns the database, location manager, ML classifier, and map manager.
@MainActor
@Observable
final class AppState {
    let db: AppDatabase
    let locationManager = LocationManager()
    let fishClassifier = FishClassifier()
    let mapManager = MapManager()

    // Repositories (share the db)
    let catchRepository: CatchRepository
    let spotRepository: SpotRepository
    let gearRepository: GearRepository
    let speciesRepository: SpeciesRepository

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

        // Boot async work
        Task {
            await fishClassifier.loadModel()
        }
        try? speciesRepository.seedIfEmpty()

        locationManager.requestPermission()
        mapManager.refreshDownloadedRegions()
    }
}
