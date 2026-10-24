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
        CloudSyncEngine.shared.catchChanged(catchRecord.id)
    }

    func delete(_ catchRecord: Catch) throws {
        try db.db.write { db in
            _ = try catchRecord.delete(db)
        }
        CloudSyncEngine.shared.catchDeleted(catchRecord.id)
    }

    /// Catches not yet uploaded to iNaturalist, oldest first so the backlog
    /// posts in the order it was logged.
    func fetchNotUploaded() throws -> [Catch] {
        try db.db.read { db in
            try Catch
                .filter(Column("inatObservationId") == nil)
                .order(Column("caughtAt"))
                .fetchAll(db)
        }
    }

    /// Record the iNaturalist observation id after a successful upload.
    func setINatObservationId(_ observationId: String, for catchId: String) throws {
        try db.db.write { db in
            try db.execute(
                sql: "UPDATE catch SET inatObservationId = ? WHERE id = ?",
                arguments: [observationId, catchId]
            )
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

    /// `fetchAll` read on the database queue instead of the main thread, for
    /// screens that load the whole log as they open (crew stats, the
    /// leaderboard), where the synchronous read stalled the first frames.
    func fetchAllInBackground(limit: Int = 50, offset: Int = 0) async throws -> [CatchDetail] {
        try await db.db.read { db in
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
