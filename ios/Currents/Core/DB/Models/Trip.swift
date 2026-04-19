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
    var photoPaths: String? // JSON array of photo filenames stored via PhotoManager
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        startDate: Date = .now,
        endDate: Date? = nil,
        spotId: String? = nil,
        notes: String? = nil,
        weatherConditions: String? = nil,
        photoPaths: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.spotId = spotId
        self.notes = notes
        self.weatherConditions = weatherConditions
        self.photoPaths = photoPaths
        self.createdAt = .now
    }

    /// Decoded photo filenames.
    var allPhotoPaths: [String] {
        guard let photoPaths, let data = photoPaths.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Encode filenames to JSON for storage.
    static func encodePhotoPaths(_ paths: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(paths),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
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
