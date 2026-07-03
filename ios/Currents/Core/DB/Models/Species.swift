import Foundation
import GRDB

struct Species: Codable, Identifiable, Hashable, Sendable {
    var id: Int64
    var scientificName: String
    var commonName: String
    var family: String?
    var habitat: Habitat?
    var minTempC: Double?
    var maxTempC: Double?
    var optimalTempC: Double?
    var fishbaseId: Int64?
    var imageUrl: String?
    var recommendedBaits: String? // JSON array of strings
    var baitNotes: String?
    /// Collection rarity rank (0 common … 4 legendary). Optional in the DB so
    /// older rows decode; `rarity` falls back to a derived value when absent.
    var rarityRank: Int?

    /// Decoded bait recommendations from JSON string.
    var parsedBaits: [String] {
        guard let data = recommendedBaits?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Collection rarity — uses the stored rank, or derives a stable tier from
    /// the species' family/habitat/temperature range when unset.
    var rarity: SpeciesRarity {
        if let rank = rarityRank, let r = SpeciesRarity(rawValue: rank) {
            return r
        }
        return Species.derivedRarity(family: family, habitat: habitat, optimalTempC: optimalTempC, id: id)
    }

    /// Asset-catalog image name for this species' collection artwork.
    /// Images are bundled as `fish_<id>` (see the CI dataset pipeline).
    var artworkAssetName: String { "fish_\(id)" }

    /// Deterministic rarity heuristic used until the curated dataset ships one.
    /// Prized apex/gamefish families skew rarer; panfish/cyprinids common.
    static func derivedRarity(family: String?, habitat: Habitat?, optimalTempC: Double?, id: Int64) -> SpeciesRarity {
        let legendaryFamilies: Set<String> = ["Arapaimidae", "Latidae", "Istiophoridae", "Xiphiidae"]
        let epicFamilies: Set<String> = ["Salmonidae", "Esocidae", "Lepisosteidae", "Sciaenidae", "Rachycentridae", "Scombridae"]
        let rareFamilies: Set<String> = ["Percichthyidae", "Cichlidae", "Serranidae", "Lutjanidae", "Carangidae", "Characidae", "Alestidae", "Siluridae"]
        let commonFamilies: Set<String> = ["Cyprinidae", "Centrarchidae", "Percidae", "Ictaluridae"]

        if let f = family {
            if legendaryFamilies.contains(f) { return .legendary }
            if epicFamilies.contains(f) { return .epic }
            if rareFamilies.contains(f) { return .rare }
            if commonFamilies.contains(f) { return .uncommon }
        }
        // Deterministic spread for everything else so the grid isn't monotone.
        switch Int(id) % 5 {
        case 0: return .rare
        case 1, 2: return .uncommon
        default: return .common
        }
    }

    enum Habitat: String, Codable, Sendable, CaseIterable {
        case freshwater
        case marine
        case brackish
    }
}

extension Species: FetchableRecord, PersistableRecord {
    static let databaseTableName = "species"
}

extension Species {
    static let catches = hasMany(Catch.self)

    var catches: QueryInterfaceRequest<Catch> {
        request(for: Species.catches)
    }
}
