import Foundation
import GRDB

struct Forecast: Codable, Sendable {
    var geohash: String
    var speciesId: Int64
    var timestamp: Date
    var score: Int // 0-100
    var reasons: String? // JSON array of reason strings

    var decodedReasons: [String] {
        guard let data = reasons?.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }
}

extension Forecast: FetchableRecord, PersistableRecord {
    static let databaseTableName = "forecast"
}
