import Foundation
import CoreLocation
import GRDB

/// Water bodies and public fishing access bundled with the app, extracted
/// from OpenStreetMap (Resources/Data/explore_water_za.json and
/// explore_places_za.json). Explore draws these with no network at all, so the
/// map has pins offline, on a sideloaded build and when the public Overpass
/// servers are too busy to answer. Overpass still tops up anywhere outside
/// the bundled tiles.
enum BundledMapData {
    /// Bump when the bundled water file changes so existing installs import it again.
    static let waterVersion = 1
    private static let waterVersionKey = "bundledWaterVersion"

    // MARK: Coverage

    /// Half-degree tile key, the same scheme BoatRampService caches by.
    static func tileKey(latitude: Double, longitude: Double) -> String {
        "\(Int((latitude / 0.5).rounded(.down)))_\(Int((longitude / 0.5).rounded(.down)))"
    }

    /// True when the bundled extract covers the whole region, so there is
    /// nothing for Overpass to add.
    static func covers(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> Bool {
        let tiles = placesIndex.tiles
        guard !tiles.isEmpty else { return false }
        let points = [
            (minLat, minLon), (minLat, maxLon), (maxLat, minLon), (maxLat, maxLon),
            ((minLat + maxLat) / 2, (minLon + maxLon) / 2),
        ]
        return points.allSatisfy { tiles.contains(tileKey(latitude: $0.0, longitude: $0.1)) }
    }

    // MARK: Fishing access and ramps

    private struct PlacesFile: Decodable {
        let tiles: [String]
        let places: [BoatRamp]
    }

    private struct PlacesIndex {
        var tiles: Set<String> = []
        var byTile: [String: [BoatRamp]] = [:]
    }

    /// Decoded once, on first use.
    private static let placesIndex: PlacesIndex = {
        guard let url = resource("explore_places_za"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PlacesFile.self, from: data) else {
            return PlacesIndex()
        }
        return PlacesIndex(
            tiles: Set(file.tiles),
            byTile: Dictionary(grouping: file.places) { tileKey(latitude: $0.lat, longitude: $0.lon) }
        )
    }()

    /// The bundled places in one tile, or nil when the bundle does not cover it.
    static func places(inTile tile: String) -> [BoatRamp]? {
        guard placesIndex.tiles.contains(tile) else { return nil }
        return placesIndex.byTile[tile] ?? []
    }

    // MARK: Water

    private struct WaterFile: Decodable {
        let water: [Entry]
    }

    private struct Entry: Decodable {
        let osm: Int64
        let name: String
        let type: String
        let lat: Double
        let lon: Double
        let km2: Double
        let `public`: Bool?
        let ele: Double?
    }

    @MainActor private static var importTask: Task<Void, Never>?

    /// Copies the bundled water into the local database once per version,
    /// off the main thread. Safe to call on every load.
    @MainActor
    static func importWaterIfNeeded(into database: AppDatabase) async {
        if UserDefaults.standard.integer(forKey: waterVersionKey) >= waterVersion { return }
        if let running = importTask {
            await running.value
            return
        }
        let task = Task.detached(priority: .userInitiated) {
            do {
                let count = try importWater(into: database)
                UserDefaults.standard.set(waterVersion, forKey: waterVersionKey)
                print("[Currents] Imported \(count) bundled water bodies")
            } catch {
                print("[Currents] Bundled water import failed: \(error)")
            }
        }
        importTask = task
        await task.value
        importTask = nil
    }

    private static func importWater(into database: AppDatabase) throws -> Int {
        guard let url = resource("explore_water_za") else { return 0 }
        let entries = try JSONDecoder().decode(WaterFile.self, from: Data(contentsOf: url)).water

        return try database.db.write { db in
            // Rows already here: Overpass rows share OSM ids; the hand-made
            // seed rows are matched by name and distance.
            var known = Set(try Int64.fetchAll(db, sql: "SELECT osmId FROM waterbody WHERE osmId IS NOT NULL"))
            var byName: [String: [(lat: Double, lon: Double)]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT name, latitude, longitude FROM waterbody") {
                let name: String = row["name"]
                let lat: Double = row["latitude"]
                let lon: Double = row["longitude"]
                byName[name.lowercased(), default: []].append((lat, lon))
            }

            var inserted = 0
            for e in entries {
                if known.contains(e.osm) {
                    // Overpass rows carry no size, which hides them when zoomed out.
                    try db.execute(
                        sql: "UPDATE waterbody SET surfaceAreaKm2 = ? WHERE osmId = ? AND surfaceAreaKm2 IS NULL",
                        arguments: [e.km2, e.osm]
                    )
                    continue
                }
                let reach = max(0.02, e.km2.squareRoot() / 111)
                if let near = byName[e.name.lowercased()],
                   near.contains(where: { abs($0.lat - e.lat) < reach && abs($0.lon - e.lon) < reach }) {
                    continue
                }
                let wb = Waterbody(
                    id: nil,
                    name: e.name,
                    type: Waterbody.WaterbodyType(rawValue: e.type) ?? .lake,
                    latitude: e.lat,
                    longitude: e.lon,
                    geohash: Geohash.encode(latitude: e.lat, longitude: e.lon),
                    maxDepthM: nil,
                    surfaceAreaKm2: e.km2,
                    globathyId: nil,
                    isPublic: e.public ?? true,
                    structureTypes: nil,
                    description: nil,
                    fishSpeciesIds: nil,
                    averageDepthM: nil,
                    elevation: e.ele,
                    osmId: e.osm
                )
                try wb.insert(db)
                known.insert(e.osm)
                inserted += 1
            }
            return inserted
        }
    }

    private static func resource(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Data")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
    }
}
