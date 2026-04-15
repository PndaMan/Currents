import Foundation
import CoreLocation

/// Fetches fish observation data from the iNaturalist API.
/// Used to determine which fish species are present near a given water body.
///
/// iNaturalist API is free, no API key required. Rate limit: ~100 req/min.
/// taxon_id 47178 = Actinopterygii (ray-finned fishes)
/// taxon_id 47273 = Chondrichthyes (sharks, rays)
///
/// GBIF is used as a secondary source for broader coverage.
actor INaturalistService {
    static let shared = INaturalistService()

    /// Cache: coordinate cell → species scientific names already fetched.
    private var fetchedCells: Set<String> = []

    private var lastQueryTime: Date = .distantPast
    private let minQueryInterval: TimeInterval = 2

    // MARK: - iNaturalist Query

    /// Fetch fish species observed near a coordinate from iNaturalist.
    /// Returns an array of species observations with scientific names and counts.
    func fetchFishSpecies(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 10
    ) async -> [ObservedSpecies] {
        let cellKey = "\(Int(latitude * 10))_\(Int(longitude * 10))"
        if fetchedCells.contains(cellKey) { return [] }

        // Rate limit
        let elapsed = Date.now.timeIntervalSince(lastQueryTime)
        if elapsed < minQueryInterval {
            try? await Task.sleep(for: .milliseconds(Int(minQueryInterval - elapsed) * 1000))
        }
        lastQueryTime = .now

        var allSpecies: [ObservedSpecies] = []

        // Query iNaturalist species counts endpoint (much more efficient than raw observations)
        let iNatResults = await queryINaturalist(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
        allSpecies.append(contentsOf: iNatResults)

        // Also query GBIF for additional coverage
        let gbifResults = await queryGBIF(latitude: latitude, longitude: longitude, radiusKm: radiusKm)

        // Merge GBIF results (add species not already found via iNat)
        let existingNames = Set(allSpecies.map { $0.scientificName.lowercased() })
        for sp in gbifResults {
            if !existingNames.contains(sp.scientificName.lowercased()) {
                allSpecies.append(sp)
            }
        }

        fetchedCells.insert(cellKey)
        return allSpecies
    }

    /// Mark a cell as fetched (when loaded from cache).
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
        // Use the species_counts endpoint — returns unique species with observation counts
        let urlString = "https://api.inaturalist.org/v1/observations/species_counts"
            + "?lat=\(latitude)&lng=\(longitude)&radius=\(radiusKm)"
            + "&taxon_id=47178"           // Ray-finned fishes
            + "&quality_grade=research"    // Research-grade only
            + "&per_page=100"
            + "&locale=en"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Currents Fishing App (contact: github.com/currents-app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }

            return parseINaturalistResponse(data, source: "iNaturalist")
        } catch {
            print("[Currents] iNaturalist query failed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseINaturalistResponse(_ data: Data, source: String) -> [ObservedSpecies] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }

        var species: [ObservedSpecies] = []

        for result in results {
            let count = result["count"] as? Int ?? 1

            guard let taxon = result["taxon"] as? [String: Any],
                  let rank = taxon["rank"] as? String,
                  rank == "species", // Only species-level IDs
                  let scientificName = taxon["name"] as? String,
                  !scientificName.isEmpty else { continue }

            let commonName = (taxon["preferred_common_name"] as? String)
                ?? (taxon["english_common_name"] as? String)

            let photoUrl: String?
            if let defaultPhoto = taxon["default_photo"] as? [String: Any] {
                photoUrl = defaultPhoto["medium_url"] as? String
                    ?? defaultPhoto["square_url"] as? String
            } else {
                photoUrl = nil
            }

            let taxonId = taxon["id"] as? Int64

            species.append(ObservedSpecies(
                scientificName: scientificName,
                commonName: commonName,
                observationCount: count,
                source: source,
                iNaturalistTaxonId: taxonId,
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
        // GBIF occurrence search — taxonKey 204 = Actinopterygii
        let urlString = "https://api.gbif.org/v1/occurrence/search"
            + "?decimalLatitude=\(latitude - radiusKm/111),\(latitude + radiusKm/111)"
            + "&decimalLongitude=\(longitude - radiusKm/111),\(longitude + radiusKm/111)"
            + "&taxonKey=204"
            + "&limit=300"
            + "&hasCoordinate=true"

        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

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

        // Group by species to get counts
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

/// A fish species observed near a location, from iNaturalist or GBIF.
struct ObservedSpecies: Sendable {
    let scientificName: String
    let commonName: String?
    let observationCount: Int
    let source: String // "iNaturalist" or "GBIF"
    let iNaturalistTaxonId: Int64?
    let photoUrl: String?
}
