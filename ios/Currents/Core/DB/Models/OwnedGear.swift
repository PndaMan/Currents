import Foundation
import GRDB

/// An individual piece of gear the user owns (rod, reel, lure, etc.).
/// Separate from GearLoadout presets — these are mix-and-match items.
struct OwnedGear: Codable, Identifiable, Sendable {
    var id: String // UUID
    var category: Category
    var name: String
    var brand: String?
    var specs: String?
    var createdAt: Date

    enum Category: String, Codable, CaseIterable, Sendable {
        case rod = "Rod"
        case reel = "Reel"
        case lure = "Lure"
        case line = "Line"
        case technique = "Technique"
        case bait = "Bait"
        case hook = "Hook"
        case accessory = "Accessory"

        var icon: String {
            switch self {
            case .rod: "line.diagonal"
            case .reel: "gearshape.fill"
            case .lure: "fish.circle.fill"
            case .line: "line.3.horizontal"
            case .technique: "hand.raised.fill"
            case .bait: "ant.fill"
            case .hook: "arrow.turn.down.right"
            case .accessory: "bag.fill"
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        category: Category,
        name: String,
        brand: String? = nil,
        specs: String? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.brand = brand
        self.specs = specs
        self.createdAt = .now
    }

    var displayName: String {
        if let brand { return "\(brand) \(name)" }
        return name
    }
}

extension OwnedGear: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ownedGear"
}
