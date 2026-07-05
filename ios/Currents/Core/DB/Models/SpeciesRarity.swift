import SwiftUI

/// Collection rarity tier for a species. Drives sort order and the colour
/// accent shown in the fish collection ("Cooler") and species guide.
///
/// Rarity is a deterministic property of the species (stored in the DB as an
/// Int `rarityRank`), not a per-user stat — so two anglers see the same
/// species at the same rarity, Pokédex-style.
enum SpeciesRarity: Int, CaseIterable, Codable, Sendable, Comparable {
    case common = 0
    case uncommon = 1
    case rare = 2
    case epic = 3
    case legendary = 4
    /// Once-in-a-lifetime monsters that are, realistically, impossible to
    /// catch on rod and line — great whites, whale sharks, oarfish. Only
    /// assigned explicitly via `rarityRank`, never derived.
    case mythical = 5

    static func < (lhs: SpeciesRarity, rhs: SpeciesRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        case .mythical: "Mythical"
        }
    }

    /// Rarity accent — kept distinct from the app theme so tiers always read
    /// the same, like loot rarities in a game.
    var color: Color {
        switch self {
        case .common: Color(red: 0.62, green: 0.66, blue: 0.70)      // steel grey
        case .uncommon: Color(red: 0.30, green: 0.72, blue: 0.40)    // green
        case .rare: Color(red: 0.25, green: 0.55, blue: 0.95)        // blue
        case .epic: Color(red: 0.62, green: 0.35, blue: 0.90)        // purple
        case .legendary: Color(red: 0.95, green: 0.68, blue: 0.15)   // gold
        case .mythical: Color(red: 0.90, green: 0.20, blue: 0.30)    // crimson
        }
    }

    var symbol: String {
        switch self {
        case .common: "circle.fill"
        case .uncommon: "diamond.fill"
        case .rare: "seal.fill"
        case .epic: "hexagon.fill"
        case .legendary: "crown.fill"
        case .mythical: "flame.fill"
        }
    }
}
