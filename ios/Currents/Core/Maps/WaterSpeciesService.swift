import Foundation
import CoreLocation
import GRDB

/// Finds the waters fish are on record at around the user, beyond the bundled
/// list (Resources/Data/water_species_za.json): every app species around
/// where they are, once a month per area, and one species on demand when the
/// map is filtered by it.
///
/// Asks GBIF for georeferenced records of the species within about 110 km
/// (museum specimens, surveys and research-grade iNaturalist observations;
/// free, no key), attaches each record to the water it lies on or beside,
/// and saves the species to those waters, so the result works offline from
/// then on. Each species and area is asked once a month.
actor WaterSpeciesService {
    static let shared = WaterSpeciesService()

    /// Half the side of the searched box, in degrees of latitude.
    private let reachDegrees = 1.0
    /// A record counts for a water within its radius plus this margin.
    private let marginM: Double = 600
    private let maxUncertaintyM: Double = 2000
    private let refreshAfter: TimeInterval = 30 * 24 * 3600
    private let askedKey = "waterSpeciesLookups"
    /// App species per GBIF request; keeps the URL short.
    private let keysPerRequest = 100
    private let pagesPerRequest = 4
    private var areaInFlight: Set<String> = []
    /// When an area last failed, so location updates without signal do not
    /// ask again every few seconds.
    private var areaFailed: [String: Date] = [:]

    /// Every app species on record around the user, attached to the waters
    /// they were recorded at, so filtering by a fish works offline here.
    /// Asked once a month per geohash-3 area. Returns the number of waters
    /// that gained a species, or nil when GBIF could not be reached.
    @discardableResult
    func downloadArea(around origin: CLLocationCoordinate2D,
                      waters repository: WaterbodyRepository, database: AppDatabase) async -> Int? {
        let area = Geohash.encode(latitude: origin.latitude, longitude: origin.longitude, precision: 3)
        let key = "area-\(area)"
        guard !areaInFlight.contains(key) else { return 0 }
        if let failed = areaFailed[key], Date.now.timeIntervalSince(failed) < 600 { return nil }
        var asked = UserDefaults.standard.dictionary(forKey: askedKey) as? [String: Double] ?? [:]
        if let last = asked[key], Date.now.timeIntervalSince1970 - last < refreshAfter { return 0 }
        guard let keys = Self.gbifKeys, !keys.isEmpty else { return 0 }
        areaInFlight.insert(key)
        defer { areaInFlight.remove(key) }

        let bounds = box(around: origin)
        var records: [Record] = []
        let all = Array(keys)
        for start in stride(from: 0, to: all.count, by: keysPerRequest) {
            let chunk = all[start..<min(start + keysPerRequest, all.count)]
            let items = chunk.map { URLQueryItem(name: "taxonKey", value: "\($0.key)") }
            guard let found = await self.records(matching: items, in: bounds, pages: pagesPerRequest) else {
                areaFailed[key] = .now
                return nil
            }
            records += found
        }
        asked[key] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(asked, forKey: askedKey)
        guard !records.isEmpty else { return 0 }

        let candidates = (try? await repository.fetchForRegionWithOverpass(
            minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon,
            limit: 5000)) ?? []
        var added: [Int64: (water: Waterbody, ids: [Int64])] = [:]
        for (water, gbifKeys) in assign(records, to: candidates) {
            guard let id = water.id else { continue }
            let have = Set(water.decodedFishSpeciesIds)
            let new = Set(gbifKeys.compactMap { keys[$0] }).subtracting(have)
            if !new.isEmpty { added[id] = (water: water, ids: water.decodedFishSpeciesIds + new.sorted()) }
        }
        guard !added.isEmpty else { return 0 }
        do {
            try await database.db.write { db in
                for (id, entry) in added {
                    let json = String(data: try JSONEncoder().encode(entry.ids), encoding: .utf8)
                    try db.execute(sql: "UPDATE waterbody SET fishSpeciesIds = ? WHERE id = ?",
                                   arguments: [json, id])
                }
            }
        } catch {
            return 0
        }
        return added.count
    }

    /// GBIF species key to app species id, from Resources/Data/gbif_species_keys.json.
    private static let gbifKeys: [Int: Int64]? = {
        guard let url = Bundle.main.url(forResource: "gbif_species_keys", withExtension: "json", subdirectory: "Data")
                ?? Bundle.main.url(forResource: "gbif_species_keys", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
        var out: [Int: Int64] = [:]
        for (species, key) in raw { if let id = Int64(species) { out[key] = id } }
        return out
    }()

    private func box(around origin: CLLocationCoordinate2D)
        -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let lonReach = reachDegrees / max(0.2, cos(origin.latitude * .pi / 180))
        return (origin.latitude - reachDegrees, origin.latitude + reachDegrees,
                origin.longitude - lonReach, origin.longitude + lonReach)
    }

    /// The number of waters newly found to hold the species: zero when it
    /// was asked recently or nothing new is on record nearby, nil when GBIF
    /// could not be reached.
    func findWaters(for species: Species, near origin: CLLocationCoordinate2D,
                    waters repository: WaterbodyRepository, database: AppDatabase) async -> Int? {
        let area = Geohash.encode(latitude: origin.latitude, longitude: origin.longitude, precision: 3)
        let key = "\(species.id)-\(area)"
        var asked = UserDefaults.standard.dictionary(forKey: askedKey) as? [String: Double] ?? [:]
        if let last = asked[key], Date.now.timeIntervalSince1970 - last < refreshAfter { return 0 }

        let bounds = box(around: origin)
        let name = [URLQueryItem(name: "scientificName", value: species.scientificName)]
        guard let records = await self.records(matching: name, in: bounds, pages: 3) else { return nil }
        asked[key] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(asked, forKey: askedKey)
        guard !records.isEmpty else { return 0 }

        // Waters the map has not loaded yet come from OpenStreetMap first.
        let candidates = (try? await repository.fetchForRegionWithOverpass(
            minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon,
            limit: 5000)) ?? []
        let holding = match(records, to: candidates)
        let fresh = holding.filter { !$0.decodedFishSpeciesIds.contains(species.id) }
        guard !fresh.isEmpty else { return 0 }

        do {
            try await database.db.write { db in
                for water in fresh {
                    guard let id = water.id else { continue }
                    let ids = water.decodedFishSpeciesIds + [species.id]
                    let json = String(data: try JSONEncoder().encode(ids), encoding: .utf8)
                    try db.execute(sql: "UPDATE waterbody SET fishSpeciesIds = ? WHERE id = ?",
                                   arguments: [json, id])
                }
            }
        } catch {
            return 0
        }
        return fresh.count
    }

    // MARK: - GBIF

    private struct Record { let lat: Double; let lon: Double; let speciesKey: Int? }

    private struct Page: Decodable {
        let endOfRecords: Bool?
        let results: [Occurrence]
    }

    private struct Occurrence: Decodable {
        let decimalLatitude: Double?
        let decimalLongitude: Double?
        let coordinateUncertaintyInMeters: Double?
        let basisOfRecord: String?
        let speciesKey: Int?
    }

    /// Nil when the request failed, so the area is asked again next time.
    private func records(matching taxon: [URLQueryItem],
                         in box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
                         pages: Int) async -> [Record]? {
        var out: [Record] = []
        for page in 0..<pages {
            var parts = URLComponents(string: "https://api.gbif.org/v1/occurrence/search")!
            parts.queryItems = taxon + [
                URLQueryItem(name: "decimalLatitude", value: "\(box.minLat),\(box.maxLat)"),
                URLQueryItem(name: "decimalLongitude", value: "\(box.minLon),\(box.maxLon)"),
                URLQueryItem(name: "hasCoordinate", value: "true"),
                URLQueryItem(name: "hasGeospatialIssue", value: "false"),
                URLQueryItem(name: "occurrenceStatus", value: "PRESENT"),
                URLQueryItem(name: "limit", value: "300"),
                URLQueryItem(name: "offset", value: "\(page * 300)"),
            ]
            guard let url = parts.url else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try? JSONDecoder().decode(Page.self, from: data) else { return nil }
            for o in body.results {
                guard let lat = o.decimalLatitude, let lon = o.decimalLongitude,
                      o.basisOfRecord != "FOSSIL_SPECIMEN", o.basisOfRecord != "LIVING_SPECIMEN",
                      (o.coordinateUncertaintyInMeters ?? 0) <= maxUncertaintyM else { continue }
                out.append(Record(lat: lat, lon: lon, speciesKey: o.speciesKey))
            }
            if body.endOfRecords ?? true { break }
        }
        return out
    }

    // MARK: - Matching

    /// The waters with at least one record on or beside them; each record
    /// goes to its nearest water only.
    private func match(_ records: [Record], to waters: [Waterbody]) -> [Waterbody] {
        assign(records, to: waters).map(\.water)
    }

    /// Each water with records on or beside it, and the GBIF species keys
    /// recorded there.
    private func assign(_ records: [Record], to waters: [Waterbody]) -> [(water: Waterbody, keys: Set<Int>)] {
        let cell = 0.25
        var grid: [String: [Waterbody]] = [:]
        for w in waters {
            grid["\(Int((w.latitude / cell).rounded(.down)))_\(Int((w.longitude / cell).rounded(.down)))", default: []].append(w)
        }
        var hit: [Int64: (water: Waterbody, keys: Set<Int>)] = [:]
        for r in records {
            let here = CLLocation(latitude: r.lat, longitude: r.lon)
            let gy = Int((r.lat / cell).rounded(.down)), gx = Int((r.lon / cell).rounded(.down))
            var best: (distance: Double, water: Waterbody)?
            for dy in -1...1 {
                for dx in -1...1 {
                    for w in grid["\(gy + dy)_\(gx + dx)"] ?? [] {
                        let d = here.distance(from: CLLocation(latitude: w.latitude, longitude: w.longitude))
                        guard d <= w.approximateRadiusM + marginM else { continue }
                        if best == nil || d < best!.distance { best = (d, w) }
                    }
                }
            }
            guard let water = best?.water, let id = water.id else { continue }
            var entry = hit[id] ?? (water: water, keys: [])
            if let key = r.speciesKey { entry.keys.insert(key) }
            hit[id] = entry
        }
        return Array(hit.values)
    }
}
