import Foundation

/// Fetches richer field-guide info for a species from the iNaturalist taxa API
/// (conservation status, a plain-language description, how commonly it's
/// observed, and a link out). Results are cached to disk so a species you've
/// opened once keeps its info offline.
actor SpeciesInfoService {
    static let shared = SpeciesInfoService()

    struct Info: Codable, Sendable {
        var taxonId: Int?                 // iNaturalist taxon id (for range map)
        var conservationStatus: String?   // e.g. "least concern", "vulnerable"
        var summary: String?              // wikipedia summary (plain text-ish)
        var observationsCount: Int?
        var wikipediaURL: String?
        var fetchedAt: Date
    }

    private var cache: [String: Info] = [:]
    private var loaded = false

    private static var diskURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("species_info_cache.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.diskURL),
           let decoded = try? JSONDecoder().decode([String: Info].self, from: data) {
            cache = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.diskURL, options: .atomic)
        }
    }

    func info(scientificName: String) async -> Info? {
        loadIfNeeded()
        if let cached = cache[scientificName] { return cached }

        guard let q = scientificName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.inaturalist.org/v1/taxa?q=\(q)&per_page=1") else {
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let taxon = results.first else {
            return nil
        }

        var status: String?
        if let cs = taxon["conservation_status"] as? [String: Any] {
            status = (cs["status_name"] as? String) ?? (cs["status"] as? String)
        }
        let summaryRaw = taxon["wikipedia_summary"] as? String
        let summary = summaryRaw?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let info = Info(
            taxonId: taxon["id"] as? Int,
            conservationStatus: status,
            summary: summary,
            observationsCount: taxon["observations_count"] as? Int,
            wikipediaURL: taxon["wikipedia_url"] as? String,
            fetchedAt: .now
        )
        cache[scientificName] = info
        persist()
        return info
    }
}
