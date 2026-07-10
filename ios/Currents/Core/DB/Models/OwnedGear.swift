import Foundation
import GRDB

/// An individual piece of gear the user owns (rod, reel, lure, etc.).
/// Separate from GearLoadout presets — these are mix-and-match items.
///
/// Consumables (line, lures, bait, hooks) track a `stock` count so the Gear tab
/// works like a tackle box: tap +/- as you use or restock, with a low-stock
/// reminder when you drop to the reorder point.
struct OwnedGear: Codable, Identifiable, Sendable {
    var id: String // UUID
    var category: Category
    var name: String
    var brand: String?
    var specs: String?
    /// Units on hand (consumables only). Nil = not stock-tracked.
    var stock: Int?
    /// Reorder point — a low-stock reminder fires at or below this.
    var lowStockThreshold: Int?
    /// Product barcode (EAN/UPC), for re-ordering. Stored on its own, not in specs.
    var barcode: String?
    var createdAt: Date

    enum Category: String, Codable, CaseIterable, Sendable {
        case rod = "Rod"
        case reel = "Reel"
        case lure = "Lure"
        case line = "Line"
        case bait = "Bait"
        case hook = "Hook"
        case accessory = "Accessory"

        var icon: String {
            switch self {
            case .rod: "figure.fishing"
            case .reel: "record.circle"
            case .lure: "fish.fill"
            case .line: "scribble.variable"
            case .bait: "ant.fill"
            case .hook: "paperclip"
            case .accessory: "backpack.fill"
            }
        }

        /// Consumables get stock tracking; rods/reels/accessories don't.
        var isConsumable: Bool {
            switch self {
            case .line, .lure, .bait, .hook: true
            case .rod, .reel, .accessory: false
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        category: Category,
        name: String,
        brand: String? = nil,
        specs: String? = nil,
        stock: Int? = nil,
        lowStockThreshold: Int? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.brand = brand
        self.specs = specs
        self.stock = stock
        self.lowStockThreshold = lowStockThreshold
        self.barcode = barcode
        self.createdAt = .now
    }

    var displayName: String {
        if let brand { return "\(brand) \(name)" }
        return name
    }

    /// True when this consumable is at or below its reorder point.
    var isLowStock: Bool {
        guard category.isConsumable, let stock else { return false }
        return stock <= (lowStockThreshold ?? 1)
    }
}

extension OwnedGear: FetchableRecord, PersistableRecord {
    static let databaseTableName = "ownedGear"
}

/// Fishing techniques are a catch attribute (not tackle-box inventory). These
/// presets appear in the Log Catch menu; users can also type a custom one.
enum FishingTechniques {
    static let presets = [
        "Drop Shot", "Carolina Rig", "Texas Rig", "Jigging", "Trolling",
        "Topwater", "Crankbait", "Spinnerbait", "Fly Fishing", "Live Bait",
        "Bottom Fishing", "Cast & Retrieve", "Slow Roll", "Finesse",
        "Power Fishing", "Sight Fishing", "Drift Fishing", "Vertical Jigging"
    ]
}
