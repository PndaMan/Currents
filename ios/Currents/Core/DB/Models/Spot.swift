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

    init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        waterbodyId: Int64? = nil,
        notes: String? = nil,
        isPrivate: Bool = true,
        createdAt: Date = .now
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
