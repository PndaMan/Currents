import Foundation
import CoreLocation

/// Fetches fish observation data from the iNaturalist and GBIF APIs.
/// Results are cached locally — this service only does the network fetching.
///
/// iNaturalist API is free, no API key required. Rate limit: ~100 req/min.
/// taxon_id 47178 = Actinopterygii (ray-finned fishes)
actor INaturalistService {
    static let shared = INaturalistService()

    /// Tracks which geohash cells we've already queried this session.
    private var fetchedCells: Set<String> = []

    private var lastQueryTime: Date = .distantPast
    private let minQueryInterval: TimeInterval = 1.5

    // MARK: - Public API

    enum FetchResult: Sendable {
        case fetched([ObservedSpecies])  // New data from API
        case alreadyCached               // Already fetched this session, check local DB
    }

    /// Fetch fish species observed near a coordinate.
    /// Returns `.alreadyCached` if this area was already queried this session.
    func fetchFishSpecies(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 10
    ) async -> FetchResult {
        let cellKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        if fetchedCells.contains(cellKey) { return .alreadyCached }

        // Rate limit — wait if needed
        let elapsed = Date.now.timeIntervalSince(lastQueryTime)
        if elapsed < minQueryInterval {
            try? await Task.sleep(for: .milliseconds(Int((minQueryInterval - elapsed) * 1000)))
        }
        lastQueryTime = .now

        // Run iNaturalist and GBIF queries in parallel
        async let iNatTask = queryINaturalist(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
        async let gbifTask = queryGBIF(latitude: latitude, longitude: longitude, radiusKm: radiusKm)

        let iNatResults = await iNatTask
        let gbifResults = await gbifTask

        // Merge: start with iNat, add GBIF species not already present
        var allSpecies = iNatResults
        let existingNames = Set(allSpecies.map { $0.scientificName.lowercased() })
        for sp in gbifResults {
            if !existingNames.contains(sp.scientificName.lowercased()) {
                allSpecies.append(sp)
            }
        }

        fetchedCells.insert(cellKey)
        return .fetched(allSpecies)
    }

    /// Mark a cell as already fetched (when loaded from cache).
    func markFetched(latitude: Double, longitude: Double) {
        let cellKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        fetchedCells.insert(cellKey)
    }

    // MARK: - iNaturalist API

    private func queryINaturalist(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async -> [ObservedSpecies] {
        // species_counts endpoint — efficient, returns unique species with counts
        let urlString = "https://api.inaturalist.org/v1/observations/species_counts"
            + "?lat=\(latitude)&lng=\(longitude)&radius=\(radiusKm)"
            + "&taxon_id=47178"           // Ray-finned fishes
            + "&quality_grade=research"    // Research-grade only
            + "&per_page=100"
            + "&locale=en"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Currents Fishing App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            return parseINaturalistResponse(data)
        } catch {
            print("[Currents] iNaturalist query failed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseINaturalistResponse(_ data: Data) -> [ObservedSpecies] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }

        var species: [ObservedSpecies] = []
        for result in results {
            let count = result["count"] as? Int ?? 1
            guard let taxon = result["taxon"] as? [String: Any],
                  let rank = taxon["rank"] as? String, rank == "species",
                  let scientificName = taxon["name"] as? String, !scientificName.isEmpty
            else { continue }

            let commonName = (taxon["preferred_common_name"] as? String)
                ?? (taxon["english_common_name"] as? String)

            let photoUrl: String?
            if let photo = taxon["default_photo"] as? [String: Any] {
                photoUrl = photo["medium_url"] as? String ?? photo["square_url"] as? String
            } else {
                photoUrl = nil
            }

            species.append(ObservedSpecies(
                scientificName: scientificName,
                commonName: commonName,
                observationCount: count,
                source: "iNaturalist",
                iNaturalistTaxonId: taxon["id"] as? Int64,
                photoUrl: photoUrl
            ))
        }
        return species
    }

    // MARK: - GBIF API

    private func queryGBIF(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async -> [ObservedSpecies] {
        // GBIF occurrence search with bounding box
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(latitude * .pi / 180))
        let minLat = latitude - latDelta
        let maxLat = latitude + latDelta
        let minLon = longitude - lonDelta
        let maxLon = longitude + lonDelta

        let urlString = "https://api.gbif.org/v1/occurrence/search"
            + "?decimalLatitude=\(minLat),\(maxLat)"
            + "&decimalLongitude=\(minLon),\(maxLon)"
            + "&taxonKey=204"        // Actinopterygii
            + "&limit=200"
            + "&hasCoordinate=true"
            + "&hasGeospatialIssue=false"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            return parseGBIFResponse(data)
        } catch {
            print("[Currents] GBIF query failed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseGBIFResponse(_ data: Data) -> [ObservedSpecies] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }

        var speciesCounts: [String: (commonName: String?, count: Int)] = [:]
        for result in results {
            guard let name = result["species"] as? String, !name.isEmpty else { continue }
            let vernacular = result["vernacularName"] as? String
            if let existing = speciesCounts[name] {
                speciesCounts[name] = (existing.commonName ?? vernacular, existing.count + 1)
            } else {
                speciesCounts[name] = (vernacular, 1)
            }
        }

        return speciesCounts.map { name, info in
            ObservedSpecies(
                scientificName: name,
                commonName: info.commonName,
                observationCount: info.count,
                source: "GBIF",
                iNaturalistTaxonId: nil,
                photoUrl: nil
            )
        }.sorted { $0.observationCount > $1.observationCount }
    }
}

// MARK: - Data Types

struct ObservedSpecies: Sendable {
    let scientificName: String
    let commonName: String?
    let observationCount: Int
    let source: String
    let iNaturalistTaxonId: Int64?
    let photoUrl: String?
}
