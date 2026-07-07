import Foundation

/// Size & bag limits for species, so an angler can check whether a fish is
/// legal to keep. Data is keyed by scientific name (matching the species
/// dataset). A small curated set ships embedded; more can be published to
/// `data/fishing_regulations.json` and synced like the gear catalog.
///
/// IMPORTANT: regulations change and vary by exact location/permit. This is a
/// convenience reference only — always confirm current local rules.
struct FishingRegulation: Codable, Sendable, Identifiable {
    var scientificName: String
    var commonName: String
    var region: String
    var minSizeCm: Double?      // minimum legal keep size (total length unless noted)
    var maxSizeCm: Double?      // slot maximum, if any
    var bagLimit: Int?         // per person per day
    var closedSeason: String?  // free-text, e.g. "Oct–Nov spawning closure"
    var notes: String?

    var id: String { scientificName + region }
}

/// A verdict for a specific catch.
enum KeepVerdict {
    case legal
    case tooSmall(minCm: Double)
    case tooBig(maxCm: Double)
    case unknownSize          // regulation exists but catch has no length
    case noRegulation         // nothing on file for this species/region

    var isBlocking: Bool {
        switch self { case .tooSmall, .tooBig: return true; default: return false }
    }
}

@MainActor
final class RegulationsService {
    static let shared = RegulationsService()

    private(set) var all: [FishingRegulation] = []
    private var byScientific: [String: FishingRegulation] = [:]
    private var loaded = false

    static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/PndaMan/Currents/master/data/fishing_regulations.json")!

    func load() {
        guard !loaded else { return }
        loaded = true
        // Prefer a synced copy on disk, else the embedded seed.
        if let disk = try? Data(contentsOf: Self.diskURL),
           let decoded = try? JSONDecoder().decode([FishingRegulation].self, from: disk), !decoded.isEmpty {
            apply(decoded)
        } else {
            apply(Self.embedded)
        }
    }

    private func apply(_ regs: [FishingRegulation]) {
        all = regs.sorted { $0.commonName < $1.commonName }
        byScientific = Dictionary(regs.map { ($0.scientificName.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    func regulation(for species: Species) -> FishingRegulation? {
        byScientific[species.scientificName.lowercased()]
    }

    /// Check a catch's length against the regulation for its species.
    func verdict(species: Species?, lengthCm: Double?) -> (verdict: KeepVerdict, reg: FishingRegulation?) {
        guard let species, let reg = regulation(for: species) else { return (.noRegulation, nil) }
        guard let len = lengthCm, len > 0 else { return (.unknownSize, reg) }
        if let mn = reg.minSizeCm, len < mn { return (.tooSmall(minCm: mn), reg) }
        if let mx = reg.maxSizeCm, len > mx { return (.tooBig(maxCm: mx), reg) }
        return (.legal, reg)
    }

    // MARK: - Sync (optional, like the gear catalog)

    private static var diskURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("fishing_regulations.json")
    }

    private static let lastSyncKey = "regulationsLastSync"

    func syncIfDue(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        guard force || Date().timeIntervalSince1970 - last >= 7 * 24 * 3600 else { return }
        do {
            var req = URLRequest(url: Self.remoteURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode([FishingRegulation].self, from: data),
                  !decoded.isEmpty else { return }
            try? data.write(to: Self.diskURL, options: .atomic)
            apply(decoded)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
        } catch {
            // offline — keep the embedded/disk copy
        }
    }

    // MARK: - Embedded seed (South Africa marine, recreational)

    private static let embedded: [FishingRegulation] = [
        .init(scientificName: "Argyrosomus japonicus", commonName: "Dusky Kob", region: "South Africa",
              minSizeCm: 60, maxSizeCm: nil, bagLimit: 1, closedSeason: nil,
              notes: "One per person per day, minimum 60 cm."),
        .init(scientificName: "Lichia amia", commonName: "Garrick / Leervis", region: "South Africa",
              minSizeCm: 70, maxSizeCm: nil, bagLimit: 2, closedSeason: nil,
              notes: "Minimum 70 cm, bag limit 2."),
        .init(scientificName: "Pomatomus saltatrix", commonName: "Elf / Shad", region: "South Africa",
              minSizeCm: 30, maxSizeCm: nil, bagLimit: 4, closedSeason: "Closed 1 Oct – 30 Nov",
              notes: "Minimum 30 cm, bag 4, seasonal closure."),
        .init(scientificName: "Rhabdosargus holubi", commonName: "Cape Stumpnose", region: "South Africa",
              minSizeCm: 25, maxSizeCm: nil, bagLimit: 10, closedSeason: nil, notes: "Minimum 25 cm."),
        .init(scientificName: "Diplodus capensis", commonName: "Blacktail / Dassie", region: "South Africa",
              minSizeCm: 20, maxSizeCm: nil, bagLimit: 5, closedSeason: nil, notes: nil),
        .init(scientificName: "Sarpa salpa", commonName: "Strepie", region: "South Africa",
              minSizeCm: 15, maxSizeCm: nil, bagLimit: 10, closedSeason: nil, notes: nil),
        .init(scientificName: "Chrysoblephus laticeps", commonName: "Roman", region: "South Africa",
              minSizeCm: 30, maxSizeCm: nil, bagLimit: 2, closedSeason: nil,
              notes: "Endemic reef fish — slow growing; handle with care."),
        .init(scientificName: "Cymatoceps nasutus", commonName: "Black Musselcracker (Poenskop)", region: "South Africa",
              minSizeCm: 50, maxSizeCm: nil, bagLimit: 1, closedSeason: nil, notes: "One per day, minimum 50 cm."),
        .init(scientificName: "Sparodon durbanensis", commonName: "White Musselcracker", region: "South Africa",
              minSizeCm: 60, maxSizeCm: nil, bagLimit: 1, closedSeason: nil, notes: nil),
        .init(scientificName: "Thunnus albacares", commonName: "Yellowfin Tuna", region: "South Africa",
              minSizeCm: 3.2, maxSizeCm: nil, bagLimit: 10, closedSeason: nil,
              notes: "Recreational bag limit 10 (all tuna/bonito combined)."),
        .init(scientificName: "Seriola lalandi", commonName: "Yellowtail", region: "South Africa",
              minSizeCm: nil, maxSizeCm: nil, bagLimit: 10, closedSeason: nil, notes: "Bag limit 10."),
        .init(scientificName: "Argyrozona argyrozona", commonName: "Carpenter / Silverfish", region: "South Africa",
              minSizeCm: 35, maxSizeCm: nil, bagLimit: 4, closedSeason: nil, notes: nil),
    ]
}
