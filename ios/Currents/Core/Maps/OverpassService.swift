import Foundation
import CoreLocation

/// Fetches water body data from the OpenStreetMap Overpass API.
/// Results are cached locally in SQLite via WaterbodyRepository.
///
/// Overpass API is free, no API key required.
/// Fair-use: one query per map region change (debounced), small bounding boxes.
actor OverpassService {
    static let shared = OverpassService()

    /// Tracks which geohash-3 cells we've already fetched to avoid re-querying.
    private var fetchedCells: Set<String> = []

    /// Minimum seconds between queries to be polite to the public Overpass server.
    private var lastQueryTime: Date = .distantPast
    private let minQueryInterval: TimeInterval = 5

    /// Fetch water bodies in a map region from Overpass, parse them, and return.
    /// Returns nil if the region was already fetched or if offline.
    func fetchWaterbodies(
        minLat: Double, maxLat: Double,
        minLon: Double, maxLon: Double
    ) async -> [OverpassWaterbody]? {
        // Compute the geohash-3 cell key for this region center to avoid re-fetching
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let cellKey = "\(Int(centerLat * 10))_\(Int(centerLon * 10))"

        if fetchedCells.contains(cellKey) { return nil }

        // Rate limit
        let elapsed = Date.now.timeIntervalSince(lastQueryTime)
        if elapsed < minQueryInterval { return nil }

        // Limit query area to avoid overloading the API (max ~0.5° span)
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        guard latSpan < 3.0 && lonSpan < 3.0 else { return nil } // Don't query when zoomed too far out

        lastQueryTime = .now

        // Overpass QL query: fetch lakes, reservoirs, dams, rivers, ponds, and water features
        // We get the center point (out center), name, and other tags
        let bbox = "\(minLat),\(minLon),\(maxLat),\(maxLon)"
        let query = """
        [out:json][timeout:15];
        (
          way["natural"="water"]["name"~"."](\(bbox));
          relation["natural"="water"]["name"~"."](\(bbox));
          way["water"~"lake|reservoir|pond|river|canal|basin"][\
        "name"~"."](\(bbox));
          relation["water"~"lake|reservoir|pond|river|canal|basin"]\
        ["name"~"."](\(bbox));
          way["waterway"="riverbank"]["name"~"."](\(bbox));
          way["landuse"="reservoir"]["name"~"."](\(bbox));
          relation["landuse"="reservoir"]["name"~"."](\(bbox));
        );
        out center tags 300;
        """

        let urlString = "https://overpass-api.de/api/interpreter"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?.data(using: .utf8)
        request.setValue("Currents Fishing App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let parsed = try parseOverpassResponse(data)
            fetchedCells.insert(cellKey)
            return parsed
        } catch {
            print("[Currents] Overpass fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Mark a cell as already fetched (e.g. when loaded from DB cache).
    func markCellFetched(lat: Double, lon: Double) {
        let cellKey = "\(Int(lat * 10))_\(Int(lon * 10))"
        fetchedCells.insert(cellKey)
    }

    // MARK: - Parsing

    private func parseOverpassResponse(_ data: Data) throws -> [OverpassWaterbody] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else {
            return []
        }

        var results: [OverpassWaterbody] = []
        var seenNames: Set<String> = [] // Deduplicate by name + approximate location

        for element in elements {
            guard let tags = element["tags"] as? [String: String],
                  let name = tags["name"], !name.isEmpty else { continue }

            // Get center coordinates
            var lat: Double?
            var lon: Double?

            if let center = element["center"] as? [String: Double] {
                lat = center["lat"]
                lon = center["lon"]
            } else {
                lat = element["lat"] as? Double
                lon = element["lon"] as? Double
            }

            guard let latitude = lat, let longitude = lon else { continue }

            // Deduplicate
            let dedupKey = "\(name)_\(Int(latitude * 100))_\(Int(longitude * 100))"
            guard !seenNames.contains(dedupKey) else { continue }
            seenNames.insert(dedupKey)

            // Determine type
            let waterTag = tags["water"] ?? ""
            let naturalTag = tags["natural"] ?? ""
            let landuseTag = tags["landuse"] ?? ""
            let waterwayTag = tags["waterway"] ?? ""

            let wbType: String
            if waterTag == "river" || waterwayTag == "riverbank" || waterwayTag == "river" {
                wbType = "river"
            } else if waterTag == "reservoir" || landuseTag == "reservoir" || name.lowercased().contains("dam") || name.lowercased().contains("reservoir") {
                wbType = "dam"
            } else if waterTag == "canal" || waterwayTag == "canal" {
                wbType = "river" // Treat canals as rivers
            } else if tags["place"] == "sea" || name.lowercased().contains("bay") || name.lowercased().contains("estuary") {
                wbType = "estuary"
            } else {
                wbType = "lake"
            }

            // Extract any available metadata
            let isPublic: Bool
            if let access = tags["access"] {
                isPublic = access != "private" && access != "no"
            } else {
                isPublic = true // Default: assume public unless marked otherwise
            }

            let description = tags["description"]
            let osmId = element["id"] as? Int64

            // Try to get surface area from way_area (not always available)
            let areaTag = tags["way_area"] // OSM sometimes has this in m²

            results.append(OverpassWaterbody(
                osmId: osmId ?? 0,
                name: name,
                type: wbType,
                latitude: latitude,
                longitude: longitude,
                isPublic: isPublic,
                description: description,
                surfaceAreaKm2: areaTag.flatMap { Double($0) }.map { $0 / 1_000_000 },
                maxDepthM: nil,
                averageDepthM: nil,
                elevation: tags["ele"].flatMap { Double($0) },
                structureTypes: nil
            ))
        }

        return results
    }
}

/// Intermediate struct from Overpass parsing before inserting into DB.
struct OverpassWaterbody: Sendable {
    let osmId: Int64
    let name: String
    let type: String // "lake", "dam", "river", "estuary", "coast"
    let latitude: Double
    let longitude: Double
    let isPublic: Bool
    let description: String?
    let surfaceAreaKm2: Double?
    let maxDepthM: Double?
    let averageDepthM: Double?
    let elevation: Double?
    let structureTypes: String? // JSON
}
