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
    static let waterVersion = 2
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

    // MARK: Water names

    /// A named water from the bundled extract, for naming the ramps on it.
    private struct NamedWater {
        let name: String
        let lat: Double
        let lon: Double
        /// Metres, as if the water were round.
        let radius: Double
        let isRiver: Bool
    }

    /// The bundled water by half-degree tile. Decoded once, on first use.
    private static let watersByTile: [String: [NamedWater]] = {
        guard let url = resource("explore_water_za"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(WaterFile.self, from: data) else {
            return [:]
        }
        let waters = file.water
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { NamedWater(name: $0.name, lat: $0.lat, lon: $0.lon, radius: ($0.km2 / .pi).squareRoot() * 1000,
                              isRiver: $0.type == "river") }
        return Dictionary(grouping: waters) { tileKey(latitude: $0.lat, longitude: $0.lon) }
    }()

    /// How far past a water's edge a ramp may lie and still be named after
    /// it. Wider than this and a harbour slipway takes the name of a dam
    /// behind the mountain.
    static let waterMarginMetres = 250.0

    /// The bundled water a point is on or beside: the water whose edge is
    /// nearest, counting each water as a circle of its area, when that edge
    /// is within 250 m. A long river is stored as one point, so a ramp far
    /// along it finds nothing and keeps its plain name. Nil outside the
    /// bundled region.
    static func waterName(near coordinate: CLLocationCoordinate2D) -> String? {
        water(near: coordinate)?.name
    }

    /// The bundled water a point is on or beside, as `waterName(near:)`
    /// finds it, and the side of the water the point is on, measured from
    /// the water's centre: "North shore". A river is stored as one point,
    /// so a ramp on it is on the "East side", not on a bank.
    static func water(near coordinate: CLLocationCoordinate2D) -> (name: String, side: String)? {
        let latIndex = Int((coordinate.latitude / 0.5).rounded(.down))
        let lonIndex = Int((coordinate.longitude / 0.5).rounded(.down))
        var best: (water: NamedWater, gap: Double)?
        for dLat in -1...1 {
            for dLon in -1...1 {
                for water in watersByTile["\(latIndex + dLat)_\(lonIndex + dLon)"] ?? [] {
                    let gap = metres(coordinate.latitude, coordinate.longitude, water.lat, water.lon) - water.radius
                    if gap <= waterMarginMetres, gap < (best?.gap ?? .infinity) {
                        best = (water, gap)
                    }
                }
            }
        }
        guard let water = best?.water else { return nil }
        return (water.name, side(of: coordinate, from: water))
    }

    /// The eight-point side of a water a point is on, from the water's centre.
    private static func side(of coordinate: CLLocationCoordinate2D, from water: NamedWater) -> String {
        let east = (coordinate.longitude - water.lon) * cos(water.lat * .pi / 180)
        let north = coordinate.latitude - water.lat
        let degrees = (atan2(east, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let names = ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
        let index = Int((degrees + 22.5) / 45) % 8
        return names[index] + (water.isRiver ? " side" : " shore")
    }

    /// Distance in metres, flat-earth, which is plenty at these ranges.
    static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let x = (lon2 - lon1) * .pi / 180 * cos((lat1 + lat2) / 2 * .pi / 180)
        let y = (lat2 - lat1) * .pi / 180
        return (x * x + y * y).squareRoot() * 6_371_000
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
                let linked = try importWaterSpecies(into: database)
                UserDefaults.standard.set(waterVersion, forKey: waterVersionKey)
                print("[Currents] Imported \(count) bundled water bodies, fish on record at \(linked)")
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

    /// The fish on record at each bundled water (Resources/Data/
    /// water_species_za.json, built from GBIF by
    /// scripts/build_water_species.py), merged into each water's species
    /// list so the species filter finds them offline. Returns the number of
    /// waters that gained a fish.
    private static func importWaterSpecies(into database: AppDatabase) throws -> Int {
        guard let url = resource("water_species_za") else { return 0 }
        struct File: Decodable { let water: [String: [[Int?]]] }  // [speciesId, records, latestYear or null]
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))

        return try database.db.write { db in
            var changed = 0
            for (osm, entries) in file.water {
                guard let osmId = Int64(osm),
                      let row = try Row.fetchOne(db, sql: "SELECT id, fishSpeciesIds FROM waterbody WHERE osmId = ?",
                                                 arguments: [osmId]) else { continue }
                let current: String? = row["fishSpeciesIds"]
                let have = current.flatMap { try? JSONDecoder().decode([Int64].self, from: Data($0.utf8)) } ?? []
                let add = entries.compactMap { $0.first.flatMap { $0 }.map(Int64.init) }.filter { !have.contains($0) }
                guard !add.isEmpty else { continue }
                let json = String(data: try JSONEncoder().encode(have + add), encoding: .utf8)
                let id: Int64 = row["id"]
                try db.execute(sql: "UPDATE waterbody SET fishSpeciesIds = ? WHERE id = ?", arguments: [json, id])
                changed += 1
            }
            return changed
        }
    }

    private static func resource(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Data")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
    }
}
