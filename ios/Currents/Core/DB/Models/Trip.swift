import Foundation
import GRDB

struct Trip: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var startDate: Date
    var endDate: Date?
    var spotId: String?
    var notes: String?
    var weatherConditions: String? // "clear", "cloudy", "rain", etc.
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        startDate: Date = .now,
        endDate: Date? = nil,
        spotId: String? = nil,
        notes: String? = nil,
        weatherConditions: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.spotId = spotId
        self.notes = notes
        self.weatherConditions = weatherConditions
        self.createdAt = .now
    }
}

extension Trip: FetchableRecord, PersistableRecord {
    static let databaseTableName = "trip"
}

extension Trip {
    static let catches = hasMany(Catch.self)
    static let spot = belongsTo(Spot.self)
}

struct TripDetail: Decodable, FetchableRecord, Sendable {
    var trip: Trip
    var spot: Spot?

    enum CodingKeys: String, CodingKey {
        case trip
        case spot
    }
}
