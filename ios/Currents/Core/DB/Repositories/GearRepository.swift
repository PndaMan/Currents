import Foundation
import GRDB

@MainActor
final class GearRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func save(_ loadout: inout GearLoadout) throws {
        try db.db.write { db in
            try loadout.save(db)
        }
    }

    func delete(_ loadout: GearLoadout) throws {
        try db.db.write { db in
            _ = try loadout.delete(db)
        }
    }

    func fetchAll() throws -> [GearLoadout] {
        try db.db.read { db in
            try GearLoadout.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Returns gear effectiveness: which loadouts have the most catches, optionally filtered by species.
    func effectiveness(speciesId: Int64? = nil) throws -> [(loadout: GearLoadout, catchCount: Int)] {
        try db.db.read { db in
            var sql = """
                SELECT g.*, COUNT(c.id) as catchCount
                FROM gearLoadout g
                LEFT JOIN "catch" c ON c.gearLoadoutId = g.id
                """
            var arguments: [DatabaseValueConvertible] = []
            if let speciesId {
                sql += " WHERE c.speciesId = ?"
                arguments.append(speciesId)
            }
            sql += " GROUP BY g.id ORDER BY catchCount DESC"

            let rows = try Row.fetchAll(db, sql: sql, arguments: .init(arguments))
            return try rows.map { row in
                let loadout = try GearLoadout(row: row)
                let count: Int = row["catchCount"]
                return (loadout: loadout, catchCount: count)
            }
        }
    }
}
