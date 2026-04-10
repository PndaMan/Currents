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

    /// Personal bests per species.
    func personalBests() throws -> [PersonalBest] {
        try db.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    s.id as speciesId,
                    s.commonName,
                    s.scientificName,
                    MAX(c.weightKg) as heaviestKg,
                    MAX(c.lengthCm) as longestCm,
                    COUNT(c.id) as totalCatches,
                    MIN(c.caughtAt) as firstCaught,
                    MAX(c.caughtAt) as lastCaught
                FROM "catch" c
                JOIN species s ON s.id = c.speciesId
                WHERE c.speciesId IS NOT NULL
                GROUP BY c.speciesId
                ORDER BY totalCatches DESC
                """)
            return rows.map { row in
                PersonalBest(
                    speciesId: row["speciesId"],
                    commonName: row["commonName"],
                    scientificName: row["scientificName"],
                    heaviestKg: row["heaviestKg"],
                    longestCm: row["longestCm"],
                    heaviestCatchId: nil,
                    longestCatchId: nil,
                    totalCatches: row["totalCatches"],
                    firstCaught: row["firstCaught"],
                    lastCaught: row["lastCaught"]
                )
            }
        }
    }

    /// Monthly catch counts for trend charts.
    func monthlyCounts(months: Int = 12) throws -> [(month: String, count: Int)] {
        try db.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT strftime('%Y-%m', caughtAt) as month, COUNT(*) as cnt
                FROM "catch"
                WHERE caughtAt >= date('now', '-\(months) months')
                GROUP BY month
                ORDER BY month
                """)
            return rows.map { (month: $0["month"] as String, count: $0["cnt"] as Int) }
        }
    }

    /// Catches grouped by hour of day (for "best time to fish" analysis).
    func catchesByHour() throws -> [(hour: Int, count: Int)] {
        try db.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT CAST(strftime('%H', caughtAt) AS INTEGER) as hour, COUNT(*) as cnt
                FROM "catch"
                GROUP BY hour
                ORDER BY hour
                """)
            return rows.map { (hour: $0["hour"] as Int, count: $0["cnt"] as Int) }
        }
    }

    /// Average forecast score at catch time (validates our forecast model).
    func averageForecastScore() throws -> Double? {
        try db.db.read { db in
            try Double.fetchOne(db, sql: """
                SELECT AVG(forecastScoreAtCapture) FROM "catch"
                WHERE forecastScoreAtCapture IS NOT NULL
                """)
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
