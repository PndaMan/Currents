import Foundation
import GRDB

@MainActor
final class SpotRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func save(_ spot: inout Spot) throws {
        try db.db.write { db in
            try spot.save(db)
        }
    }

    func delete(_ spot: Spot) throws {
        try db.db.write { db in
            _ = try spot.delete(db)
        }
    }

    func fetchAll() throws -> [Spot] {
        try db.db.read { db in
            try Spot.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func fetchNearby(latitude: Double, longitude: Double, radiusKm: Double = 50) throws -> [Spot] {
        // Use geohash prefix for coarse filter, then Haversine for precise
        let geohash = Geohash.encode(latitude: latitude, longitude: longitude, precision: 4)
        let neighbors = Geohash.neighbors(of: geohash) + [geohash]
        let placeholders = neighbors.map { _ in "?" }.joined(separator: ", ")

        return try db.db.read { db in
            let sql = """
                SELECT * FROM spot
                WHERE substr(geohash, 1, 4) IN (\(placeholders))
                ORDER BY createdAt DESC
                """
            return try Spot.fetchAll(db, sql: sql, arguments: .init(neighbors))
        }
    }
}
