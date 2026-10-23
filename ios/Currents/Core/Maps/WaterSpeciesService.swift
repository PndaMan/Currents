import Foundation
import CoreLocation
import GRDB

/// Finds the waters a fish is on record at, around a point, when the bundled
/// list (Resources/Data/water_species_za.json) has nothing there.
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

    /// The number of waters newly found to hold the species: zero when it
    /// was asked recently or nothing new is on record nearby, nil when GBIF
    /// could not be reached.
    func findWaters(for species: Species, near origin: CLLocationCoordinate2D,
                    waters repository: WaterbodyRepository, database: AppDatabase) async -> Int? {
        let area = Geohash.encode(latitude: origin.latitude, longitude: origin.longitude, precision: 3)
        let key = "\(species.id)-\(area)"
        var asked = UserDefaults.standard.dictionary(forKey: askedKey) as? [String: Double] ?? [:]
        if let last = asked[key], Date.now.timeIntervalSince1970 - last < refreshAfter { return 0 }

        let lonReach = reachDegrees / max(0.2, cos(origin.latitude * .pi / 180))
        let box = (minLat: origin.latitude - reachDegrees, maxLat: origin.latitude + reachDegrees,
                   minLon: origin.longitude - lonReach, maxLon: origin.longitude + lonReach)

        guard let records = await records(of: species.scientificName, in: box) else { return nil }
        asked[key] = Date.now.timeIntervalSince1970
        UserDefaults.standard.set(asked, forKey: askedKey)
        guard !records.isEmpty else { return 0 }

        // Waters the map has not loaded yet come from OpenStreetMap first.
        let candidates = (try? await repository.fetchForRegionWithOverpass(
            minLat: box.minLat, maxLat: box.maxLat, minLon: box.minLon, maxLon: box.maxLon,
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

    private struct Record { let lat: Double; let lon: Double }

    private struct Page: Decodable {
        let endOfRecords: Bool?
        let results: [Occurrence]
    }

    private struct Occurrence: Decodable {
        let decimalLatitude: Double?
        let decimalLongitude: Double?
        let coordinateUncertaintyInMeters: Double?
        let basisOfRecord: String?
    }

    /// Nil when the request failed, so the area is asked again next time.
    private func records(of scientificName: String,
                         in box: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) async -> [Record]? {
        var out: [Record] = []
        for page in 0..<3 {
            var parts = URLComponents(string: "https://api.gbif.org/v1/occurrence/search")!
            parts.queryItems = [
                URLQueryItem(name: "scientificName", value: scientificName),
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
                out.append(Record(lat: lat, lon: lon))
            }
            if body.endOfRecords ?? true { break }
        }
        return out
    }

    // MARK: - Matching

    /// The waters with at least one record on or beside them; each record
    /// goes to its nearest water only.
    private func match(_ records: [Record], to waters: [Waterbody]) -> [Waterbody] {
        let cell = 0.25
        var grid: [String: [Waterbody]] = [:]
        for w in waters {
            grid["\(Int((w.latitude / cell).rounded(.down)))_\(Int((w.longitude / cell).rounded(.down)))", default: []].append(w)
        }
        var hit: [Int64: Waterbody] = [:]
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
            if let water = best?.water, let id = water.id { hit[id] = water }
        }
        return Array(hit.values)
    }
}
