import Foundation
import GRDB
import CoreLocation

@MainActor
final class WaterbodyRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func fetchAll() throws -> [Waterbody] {
        try db.db.read { db in
            try Waterbody.order(Column("name")).fetchAll(db)
        }
    }

    func fetch(id: Int64) throws -> Waterbody? {
        try db.db.read { db in
            try Waterbody.fetchOne(db, key: id)
        }
    }

    /// Fetch waterbodies within the visible map region.
    func fetchForRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) throws -> [Waterbody] {
        try db.db.read { db in
            try Waterbody
                .filter(Column("latitude") >= minLat && Column("latitude") <= maxLat)
                .filter(Column("longitude") >= minLon && Column("longitude") <= maxLon)
                .limit(200) // Cap results for performance
                .fetchAll(db)
        }
    }

    /// Fetch waterbodies within approximate radius of a coordinate.
    func fetchNearby(latitude: Double, longitude: Double, radiusKm: Double) throws -> [Waterbody] {
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(latitude * .pi / 180))
        return try fetchForRegion(
            minLat: latitude - latDelta,
            maxLat: latitude + latDelta,
            minLon: longitude - lonDelta,
            maxLon: longitude + lonDelta
        )
    }

    func save(_ waterbody: inout Waterbody) throws {
        try db.db.write { db in
            try waterbody.save(db)
        }
    }

    /// Count cached waterbodies.
    func count() throws -> Int {
        try db.db.read { db in try Waterbody.fetchCount(db) }
    }

    // MARK: - Overpass Integration

    /// Insert waterbodies fetched from the Overpass API.
    /// Uses osmId to avoid duplicates (upsert by osmId).
    func insertFromOverpass(_ entries: [OverpassWaterbody]) throws -> Int {
        var inserted = 0
        try db.db.write { db in
            for entry in entries {
                // Check if we already have this OSM feature
                let existing = try Waterbody
                    .filter(Column("osmId") == entry.osmId)
                    .fetchOne(db)

                if existing != nil { continue }

                // Also deduplicate by name + proximity (within ~500m)
                let nearbyDup = try Waterbody
                    .filter(Column("name") == entry.name)
                    .filter(Column("latitude") > entry.latitude - 0.005)
                    .filter(Column("latitude") < entry.latitude + 0.005)
                    .filter(Column("longitude") > entry.longitude - 0.005)
                    .filter(Column("longitude") < entry.longitude + 0.005)
                    .fetchOne(db)

                if nearbyDup != nil { continue }

                let geohash = Geohash.encode(latitude: entry.latitude, longitude: entry.longitude)
                var wb = Waterbody(
                    id: nil,
                    name: entry.name,
                    type: Waterbody.WaterbodyType(rawValue: entry.type) ?? .lake,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    geohash: geohash,
                    maxDepthM: entry.maxDepthM,
                    surfaceAreaKm2: entry.surfaceAreaKm2,
                    globathyId: nil,
                    isPublic: entry.isPublic,
                    structureTypes: entry.structureTypes,
                    description: entry.description,
                    fishSpeciesIds: nil,
                    averageDepthM: entry.averageDepthM,
                    elevation: entry.elevation,
                    osmId: entry.osmId
                )
                try wb.insert(db)
                inserted += 1
            }
        }
        if inserted > 0 {
            print("[Currents] Cached \(inserted) waterbodies from Overpass")
        }
        return inserted
    }

    /// Fetch water bodies for a region, querying Overpass if needed, then return from DB.
    func fetchForRegionWithOverpass(
        minLat: Double, maxLat: Double,
        minLon: Double, maxLon: Double
    ) async throws -> [Waterbody] {
        // First try to get from Overpass (non-blocking, returns nil if already fetched)
        if let overpassResults = await OverpassService.shared.fetchWaterbodies(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon
        ) {
            let _ = try insertFromOverpass(overpassResults)
        }

        // Always return from local DB
        return try fetchForRegion(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    /// Seed waterbodies from embedded data if the table is empty.
    func seedIfEmpty() throws {
        let count = try db.db.read { db in try Waterbody.fetchCount(db) }
        guard count == 0 else { return }

        let list: [Waterbody]
        do {
            list = try JSONDecoder().decode([Waterbody].self, from: WaterbodySeedData.json)
        } catch {
            print("[Currents] Failed to decode waterbody seed data: \(error)")
            return
        }

        try db.db.write { db in
            for var wb in list {
                try wb.insert(db)
            }
        }
        print("[Currents] Seeded \(list.count) waterbodies")
    }
}
