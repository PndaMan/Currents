import Foundation
import GRDB

struct WeatherObservation: Codable, Sendable {
    var timestamp: Date
    var geohash: String
    var pressureHpa: Double?
    var tempC: Double?
    var windSpeedMs: Double?
    var windDirDeg: Int?
    var cloudPct: Int?
    var precipMm: Double?
}

extension WeatherObservation: FetchableRecord, PersistableRecord {
    static let databaseTableName = "weatherObservation"
}
