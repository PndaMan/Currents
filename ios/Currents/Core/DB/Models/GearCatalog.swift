import Foundation
import GRDB

/// Pre-seeded catalog of popular fishing gear items.
/// Users browse this catalog and add items to their loadouts.
struct GearItem: Codable, Identifiable, Sendable {
    var id: Int64
    var category: GearCategory
    var brand: String
    var model: String
    var type: String? // e.g. "Spinning", "Baitcasting", "Fly", "Soft Plastic"
    var specs: String? // compact spec summary
    var targetSpecies: String? // comma-separated species types
    var priceRange: String? // "$", "$$", "$$$", "$$$$"

    var displayName: String { "\(brand) \(model)" }

    enum GearCategory: String, Codable, Sendable, CaseIterable {
        case rod = "Rod"
        case reel = "Reel"
        case lure = "Lure"
        case bait = "Bait"
        case line = "Line"
        case hook = "Hook"
        case terminal = "Terminal Tackle"
        case accessory = "Accessory"
    }
}

extension GearItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "gearCatalog"
}
