import Foundation
import GRDB

struct Spot: Codable, Identifiable, Sendable {
    var id: String // UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var geohash: String?
    var waterbodyId: Int64?
    var notes: String?
    var isPrivate: Bool
    var createdAt: Date
    var spotType: String?

    /// Where the spot is — broad water-body types that work for any angler
    /// (fresh, salt, shore or boat), not technique-specific micro-features.
    enum SpotType: String, Codable, CaseIterable, Sendable {
        case general = "General"
        case lake = "Lake"
        case dam = "Dam / Reservoir"
        case river = "River"
        case creek = "Creek / Stream"
        case pond = "Pond"
        case canal = "Canal"
        case estuary = "Estuary"
        case beach = "Beach / Surf"
        case rocks = "Rocks / Jetty"
        case pier = "Pier / Dock"
        case harbour = "Harbour / Marina"
        case reef = "Reef"
        case offshore = "Offshore / Boat"

        var icon: String {
            switch self {
            case .general: "mappin.and.ellipse"
            case .lake: "water.waves"
            case .dam: "water.waves.and.arrow.down"
            case .river: "arrow.triangle.pull"
            case .creek: "leaf.fill"
            case .pond: "drop.fill"
            case .canal: "equal"
            case .estuary: "arrow.triangle.merge"
            case .beach: "beach.umbrella.fill"
            case .rocks: "mountain.2.fill"
            case .pier, .harbour: "sailboat.fill"
            case .reef: "fish.fill"
            case .offshore: "ferry.fill"
            }
        }
    }

    /// Typed accessor over the raw `spotType` column.
    var type: SpotType {
        get { spotType.flatMap(SpotType.init(rawValue:)) ?? .general }
        set { spotType = newValue == .general ? nil : newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        waterbodyId: Int64? = nil,
        notes: String? = nil,
        isPrivate: Bool = true,
        createdAt: Date = .now,
        spotType: SpotType = .general
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.geohash = Geohash.encode(latitude: latitude, longitude: longitude, precision: 7)
        self.waterbodyId = waterbodyId
        self.notes = notes
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.spotType = spotType == .general ? nil : spotType.rawValue
    }
}

extension Spot: FetchableRecord, PersistableRecord {
    static let databaseTableName = "spot"
}

extension Spot {
    static let catches = hasMany(Catch.self)
    static let waterbody = belongsTo(Waterbody.self)

    var catches: QueryInterfaceRequest<Catch> {
        request(for: Spot.catches)
    }
}
