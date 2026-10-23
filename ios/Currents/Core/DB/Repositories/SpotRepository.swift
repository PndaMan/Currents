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
        CloudSyncEngine.shared.spotChanged(spot.id)
    }

    func delete(_ spot: Spot) throws {
        try db.db.write { db in
            _ = try spot.delete(db)
        }
        CloudSyncEngine.shared.spotDeleted(spot.id)
    }

    func fetchAll() throws -> [Spot] {
        try db.db.read { db in
            try Spot.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    // MARK: - Notification choices

    /// Every stored per-spot choice, keyed by spot id. Spots missing from the
    /// result follow the defaults.
    func alerts() throws -> [String: SpotAlert] {
        let rows = try db.db.read { db in try SpotAlert.fetchAll(db) }
        return Dictionary(rows.map { ($0.spotId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func alert(for spotId: String) throws -> SpotAlert {
        try db.db.read { db in try SpotAlert.fetchOne(db, key: spotId) } ?? .defaults(for: spotId)
    }

    /// Stores the choice, or removes the row when it is back to the defaults.
    func saveAlert(_ alert: SpotAlert) throws {
        try db.db.write { db in
            if alert.isDefault {
                _ = try SpotAlert.deleteOne(db, key: alert.spotId)
            } else {
                try alert.save(db)
            }
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
