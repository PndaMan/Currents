import Foundation
import GRDB

/// Manages the observed species cache — fetches from iNaturalist/GBIF,
/// cross-references with local species table, and caches for offline use.
@MainActor
final class ObservedSpeciesRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// How long cached data is considered fresh (7 days).
    private let cacheTTL: TimeInterval = 7 * 24 * 3600

    // MARK: - Public API

    /// Represents a fish found near a water body — either matched to our local DB or from iNat/GBIF.
    struct FishResult: Sendable {
        let scientificName: String
        let commonName: String
        let observationCount: Int
        let source: String
        let photoUrl: String?
        let localSpecies: Species?     // Non-nil if matched to our species DB
    }

    /// Get fish species near a coordinate. Checks cache first, then queries iNaturalist + GBIF.
    func fishNear(
        latitude: Double,
        longitude: Double,
        speciesRepository: SpeciesRepository
    ) async -> [FishResult] {
        let cell = Geohash.encode(latitude: latitude, longitude: longitude, precision: 3)

        // Check cache
        let cached = try? fetchCached(geohashCell: cell)
        if let cached, !cached.isEmpty {
            // Check freshness
            if let first = cached.first, Date.now.timeIntervalSince(first.fetchedAt) < cacheTTL {
                await INaturalistService.shared.markFetched(latitude: latitude, longitude: longitude)
                return buildResults(from: cached, speciesRepository: speciesRepository)
            }
        }

        // Fetch from iNaturalist + GBIF
        let observed = await INaturalistService.shared.fetchFishSpecies(
            latitude: latitude,
            longitude: longitude,
            radiusKm: 10
        )

        guard !observed.isEmpty else {
            // Return whatever we have cached even if stale, or empty
            if let cached, !cached.isEmpty {
                return buildResults(from: cached, speciesRepository: speciesRepository)
            }
            return []
        }

        // Match to local species and cache
        let cacheEntries = matchAndCache(observed: observed, geohashCell: cell, speciesRepository: speciesRepository)
        return buildResults(from: cacheEntries, speciesRepository: speciesRepository)
    }

    // MARK: - Cache Operations

    private func fetchCached(geohashCell: String) throws -> [ObservedSpeciesCache] {
        try db.db.read { db in
            try ObservedSpeciesCache
                .filter(Column("geohashCell") == geohashCell)
                .order(Column("observationCount").desc)
                .fetchAll(db)
        }
    }

    private func matchAndCache(
        observed: [ObservedSpecies],
        geohashCell: String,
        speciesRepository: SpeciesRepository
    ) -> [ObservedSpeciesCache] {
        // Load all species for matching
        let allSpecies = (try? speciesRepository.fetchAll()) ?? []
        let speciesByScientific = Dictionary(
            uniqueKeysWithValues: allSpecies.map { ($0.scientificName.lowercased(), $0) }
        )
        // Also build a map by common name for fuzzy matching
        let speciesByCommon = Dictionary(
            uniqueKeysWithValues: allSpecies.compactMap { sp -> (String, Species)? in
                guard !sp.commonName.isEmpty else { return nil }
                return (sp.commonName.lowercased(), sp)
            }
        )

        var entries: [ObservedSpeciesCache] = []

        do {
            try db.db.write { db in
                // Clear old entries for this cell
                try ObservedSpeciesCache
                    .filter(Column("geohashCell") == geohashCell)
                    .deleteAll(db)

                for obs in observed {
                    // Try to match to local species
                    let matched = speciesByScientific[obs.scientificName.lowercased()]
                        ?? obs.commonName.flatMap { speciesByCommon[$0.lowercased()] }

                    var entry = ObservedSpeciesCache(
                        id: nil,
                        geohashCell: geohashCell,
                        scientificName: obs.scientificName,
                        commonName: obs.commonName,
                        observationCount: obs.observationCount,
                        source: obs.source,
                        iNaturalistTaxonId: obs.iNaturalistTaxonId,
                        photoUrl: obs.photoUrl,
                        localSpeciesId: matched?.id,
                        fetchedAt: .now
                    )
                    try entry.insert(db)
                    entries.append(entry)
                }
            }
        } catch {
            print("[Currents] Failed to cache observed species: \(error)")
        }

        return entries
    }

    private func buildResults(
        from cached: [ObservedSpeciesCache],
        speciesRepository: SpeciesRepository
    ) -> [FishResult] {
        cached.map { entry in
            let localSpecies: Species?
            if let speciesId = entry.localSpeciesId {
                localSpecies = try? speciesRepository.fetch(id: speciesId)
            } else {
                localSpecies = nil
            }

            return FishResult(
                scientificName: entry.scientificName,
                commonName: localSpecies?.commonName ?? entry.commonName ?? entry.scientificName,
                observationCount: entry.observationCount,
                source: entry.source,
                photoUrl: entry.photoUrl,
                localSpecies: localSpecies
            )
        }
    }
}
