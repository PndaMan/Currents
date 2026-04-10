import Foundation
import GRDB

struct Catch: Codable, Identifiable, Sendable {
    var id: String // UUID
    var speciesId: Int64?
    var spotId: String?
    var caughtAt: Date
    var latitude: Double
    var longitude: Double
    var geohash: String?
    var lengthCm: Double?
    var weightKg: Double?
    var released: Bool
    var photoPath: String?
    var mlConfidence: Double?
    var mlTop3: String? // JSON encoded
    var forecastScoreAtCapture: Int?
    var weatherSnapshot: String? // JSON encoded
    var tideSnapshot: String? // JSON encoded
    var gearLoadoutId: String?
    var notes: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        speciesId: Int64? = nil,
        spotId: String? = nil,
        caughtAt: Date = .now,
        latitude: Double,
        longitude: Double,
        lengthCm: Double? = nil,
        weightKg: Double? = nil,
        released: Bool = true,
        photoPath: String? = nil,
        mlConfidence: Double? = nil,
        mlTop3: String? = nil,
        forecastScoreAtCapture: Int? = nil,
        weatherSnapshot: String? = nil,
        tideSnapshot: String? = nil,
        gearLoadoutId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.speciesId = speciesId
        self.spotId = spotId
        self.caughtAt = caughtAt
        self.latitude = latitude
        self.longitude = longitude
        self.geohash = Geohash.encode(latitude: latitude, longitude: longitude, precision: 7)
        self.lengthCm = lengthCm
        self.weightKg = weightKg
        self.released = released
        self.photoPath = photoPath
        self.mlConfidence = mlConfidence
        self.mlTop3 = mlTop3
        self.forecastScoreAtCapture = forecastScoreAtCapture
        self.weatherSnapshot = weatherSnapshot
        self.tideSnapshot = tideSnapshot
        self.gearLoadoutId = gearLoadoutId
        self.notes = notes
        self.createdAt = .now
    }
}

extension Catch: FetchableRecord, PersistableRecord {
    static let databaseTableName = "catch"
}

extension Catch {
    static let species = belongsTo(Species.self)
    static let spot = belongsTo(Spot.self)
    static let gearLoadout = belongsTo(GearLoadout.self)
}

/// A catch joined with its species and spot for display purposes.
struct CatchDetail: Decodable, FetchableRecord, Sendable {
    var catchRecord: Catch
    var species: Species?
    var spot: Spot?
    var gearLoadout: GearLoadout?

    enum CodingKeys: String, CodingKey {
        case catchRecord = "catch"
        case species
        case spot
        case gearLoadout
    }
}
