import Foundation
import GRDB

struct SpawningZone: Codable, Identifiable, Sendable {
    var id: Int64
    var speciesId: Int64
    var latitude: Double
    var longitude: Double
    var radiusKm: Double
    var months: String? // JSON array e.g. [9,10,11]
    var source: String?

    var activeMonths: [Int] {
        guard let data = months?.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return arr
    }

    func isActive(inMonth month: Int) -> Bool {
        activeMonths.contains(month)
    }
}

extension SpawningZone: FetchableRecord, PersistableRecord {
    static let databaseTableName = "spawningZone"
}
