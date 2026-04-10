import Foundation
import GRDB

/// Data access for catches. All reads are from local SQLite.
@MainActor
final class CatchRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Writes

    func save(_ catchRecord: inout Catch) throws {
        try db.db.write { db in
            try catchRecord.save(db)
        }
    }

    func delete(_ catchRecord: Catch) throws {
        try db.db.write { db in
            _ = try catchRecord.delete(db)
        }
    }

    // MARK: - Reads

    func fetchAll(limit: Int = 50, offset: Int = 0) throws -> [CatchDetail] {
        try db.db.read { db in
            let request = Catch
                .including(optional: Catch.species)
                .including(optional: Catch.spot)
                .including(optional: Catch.gearLoadout)
                .order(Column("caughtAt").desc)
                .limit(limit, offset: offset)
            return try CatchDetail.fetchAll(db, request)
        }
    }

    func fetchForSpot(_ spotId: String) throws -> [CatchDetail] {
        try db.db.read { db in
            let request = Catch
                .filter(Column("spotId") == spotId)
                .including(optional: Catch.species)
                .including(optional: Catch.spot)
                .including(optional: Catch.gearLoadout)
                .order(Column("caughtAt").desc)
            return try CatchDetail.fetchAll(db, request)
        }
    }

    func fetchForSpecies(_ speciesId: Int64) throws -> [CatchDetail] {
        try db.db.read { db in
            let request = Catch
                .filter(Column("speciesId") == speciesId)
                .including(optional: Catch.species)
                .including(optional: Catch.spot)
                .including(optional: Catch.gearLoadout)
                .order(Column("caughtAt").desc)
            return try CatchDetail.fetchAll(db, request)
        }
    }

    func totalCount() throws -> Int {
        try db.db.read { db in
            try Catch.fetchCount(db)
        }
    }

    func speciesCounts() throws -> [(speciesId: Int64, commonName: String, count: Int)] {
        try db.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.speciesId, s.commonName, COUNT(*) as cnt
                FROM "catch" c
                JOIN species s ON s.id = c.speciesId
                WHERE c.speciesId IS NOT NULL
                GROUP BY c.speciesId
                ORDER BY cnt DESC
                """)
            return rows.map { row in
                (
                    speciesId: row["speciesId"] as Int64,
                    commonName: row["commonName"] as String,
                    count: row["cnt"] as Int
                )
            }
        }
    }
}
