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
    /// the species' name/family when unset.
    var rarity: SpeciesRarity {
        if let rank = rarityRank, let r = SpeciesRarity(rawValue: rank) {
            return r
        }
        return Species.derivedRarity(commonName: commonName, family: family, habitat: habitat)
    }

    /// Asset-catalog image name for this species' collection artwork.
    /// Images are bundled as `fish_<id>` (see the CI dataset pipeline).
    var artworkAssetName: String { "fish_\(id)" }

    /// Rarity based on how BIG the fish gets and how HARD it is to catch —
    /// trophy pelagics and apex predators at the top, ubiquitous panfish and
    /// everyday bass at the bottom. Name keywords win over family so specific
    /// species (striped bass vs largemouth, bluefin vs bonito) land correctly.
    static func derivedRarity(commonName: String, family: String?, habitat: Habitat?) -> SpeciesRarity {
        let name = commonName.lowercased()
        func nameHas(_ words: [String]) -> Bool { words.contains { name.contains($0) } }

        // Trophy fish of a lifetime: massive, rare encounters, brutal fights.
        if nameHas([
            "marlin", "sailfish", "swordfish", "spearfish", "sturgeon", "arapaima",
            "muskellunge", "muskie", "tarpon", "bluefin", "goliath", "great white",
            "mako", "hammerhead", "tiger shark", "bull shark", "greenland shark",
            "thresher", "giant trevally", "nile perch", "taimen", "alligator gar",
            "paddlefish", "halibut", "wels", "mekong", "piraiba", "goonch",
        ]) { return .legendary }

        // Big prized gamefish that demand real skill or heavy tackle.
        if nameHas([
            "shark", "tuna", "wahoo", "cobia", "mahi", "dorado", "dolphinfish",
            "roosterfish", "permit", "bonefish", "amberjack", "striped bass",
            "flathead catfish", "blue catfish", "snook", "barramundi",
            "peacock bass", "king mackerel", "kingfish", "northern pike",
            "chinook", "king salmon", "atlantic salmon", "steelhead",
            "lake trout", "sawfish", "stingray", "tigerfish", "yellowtail",
            "queenfish", "milkfish", "giant snakehead",
        ]) { return .epic }

        // Solid targets that take know-how: prized table fish, wary fighters.
        if nameHas([
            "salmon", "walleye", "zander", "brown trout", "rainbow trout",
            "brook trout", "cutthroat", "redfish", "red drum", "snapper",
            "grouper", "flounder", "fluke", "turbot", "sheepshead",
            "triggerfish", "pompano", "spanish mackerel", "cero", "burbot",
            "whitefish", "trevally", "crevalle", "grass carp", "pike",
            "gar", "snakehead", "eel", "sea trout", "weakfish", "corvina",
            "galjoen", "leervis", "kob", "tautog", "lingcod", "black drum",
        ]) { return .rare }

        // Regular catches with some size or fight to them.
        if nameHas([
            "trout", "catfish", "carp", "pickerel", "white bass", "sea bass",
            "drum", "bonito", "mackerel", "ladyfish", "jack", "bluefish",
            "barracuda", "buffalo", "bowfin", "dogfish", "skate", "ray",
            "porgy", "grunter", "bream", "tench", "roach bream",
        ]) { return .uncommon }

        // Ubiquitous, easy to catch, or small: panfish, baitfish, everyday bass.
        if nameHas([
            "bass", "bluegill", "sunfish", "pumpkinseed", "crappie", "perch",
            "bullhead", "shad", "herring", "sardine", "anchovy", "mullet",
            "pinfish", "whiting", "smelt", "minnow", "chub", "dace", "shiner",
            "sucker", "grunt", "croaker", "spot", "tilapia", "warmouth",
            "rock bass", "madtom", "killifish", "goby", "sculpin", "stickleback",
        ]) { return .common }

        // Family fallback for everything the name pass didn't recognise.
        if let f = family {
            let legendaryFamilies: Set<String> = [
                "Istiophoridae", "Xiphiidae", "Acipenseridae", "Arapaimidae",
                "Megalopidae", "Polyodontidae",
            ]
            let epicFamilies: Set<String> = [
                "Carcharhinidae", "Lamnidae", "Sphyrnidae", "Alopiidae",
                "Triakidae", "Squalidae", "Ginglymostomatidae", "Pristidae",
                "Scombridae", "Coryphaenidae", "Rachycentridae", "Latidae",
                "Esocidae", "Lepisosteidae", "Dasyatidae", "Myliobatidae",
            ]
            let rareFamilies: Set<String> = [
                "Salmonidae", "Serranidae", "Epinephelidae", "Lutjanidae",
                "Carangidae", "Sciaenidae", "Percichthyidae", "Paralichthyidae",
                "Pleuronectidae", "Anguillidae", "Channidae", "Alestidae",
                "Characidae", "Siluridae", "Pimelodidae",
            ]
            let uncommonFamilies: Set<String> = [
                "Ictaluridae", "Moronidae", "Sparidae", "Pomatomidae",
                "Sphyraenidae", "Amiidae", "Cyprinidae",
            ]
            let commonFamilies: Set<String> = [
                "Centrarchidae", "Percidae", "Clupeidae", "Mugilidae",
                "Gerreidae", "Haemulidae", "Cichlidae", "Atherinidae",
                "Engraulidae", "Catostomidae", "Osmeridae",
            ]
            if legendaryFamilies.contains(f) { return .legendary }
            if epicFamilies.contains(f) { return .epic }
            if rareFamilies.contains(f) { return .rare }
            if uncommonFamilies.contains(f) { return .uncommon }
            if commonFamilies.contains(f) { return .common }
        }

        // Unknown species: marine fish skew a bit less accessible from shore.
        return habitat == .marine ? .uncommon : .common
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
