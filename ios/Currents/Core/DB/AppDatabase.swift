import Foundation
import GRDB

/// Central database manager. Owns the GRDB DatabaseQueue and runs migrations.
final class AppDatabase: Sendable {
    let db: DatabaseQueue

    init(_ db: DatabaseQueue) throws {
        self.db = db
        try migrator.migrate(db)
    }

    /// In-memory database for previews and tests.
    static func empty() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// On-disk database in the app's Application Support directory.
    static func persistent() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("currents.sqlite")

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable WAL for concurrent reads during sync
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let db = try DatabaseQueue(path: url.path, configuration: config)
        return try AppDatabase(db)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial") { db in
            // Species (seeded from FishBase)
            try db.create(table: "species") { t in
                t.primaryKey("id", .integer)
                t.column("scientificName", .text).notNull().unique()
                t.column("commonName", .text).notNull()
                t.column("family", .text)
                t.column("habitat", .text) // freshwater, marine, brackish
                t.column("minTempC", .double)
                t.column("maxTempC", .double)
                t.column("optimalTempC", .double)
                t.column("fishbaseId", .integer)
                t.column("imageUrl", .text)
            }

            // Waterbodies
            try db.create(table: "waterbody") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull() // dam, river, estuary, coast
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("geohash", .text)
                t.column("maxDepthM", .double)
                t.column("surfaceAreaKm2", .double)
                t.column("globathyId", .text)
            }
            try db.create(indexOn: "waterbody", columns: ["geohash"])

            // Spawning zones
            try db.create(table: "spawningZone") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("speciesId", .integer).notNull()
                    .references("species", onDelete: .cascade)
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("radiusKm", .double).notNull()
                t.column("months", .text) // JSON array e.g. [9,10,11]
                t.column("source", .text)
            }

            // Spots (user fishing locations)
            try db.create(table: "spot") { t in
                t.primaryKey("id", .text) // UUID
                t.column("name", .text).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("geohash", .text)
                t.column("waterbodyId", .integer)
                    .references("waterbody")
                t.column("notes", .text)
                t.column("isPrivate", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(indexOn: "spot", columns: ["geohash"])

            // Gear loadouts
            try db.create(table: "gearLoadout") { t in
                t.primaryKey("id", .text) // UUID
                t.column("name", .text).notNull()
                t.column("rod", .text)
                t.column("reel", .text)
                t.column("lineLb", .double)
                t.column("leaderLb", .double)
                t.column("lure", .text)
                t.column("lureColor", .text)
                t.column("lureWeightG", .double)
                t.column("technique", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Catches
            try db.create(table: "catch") { t in
                t.primaryKey("id", .text) // UUID
                t.column("speciesId", .integer)
                    .references("species")
                t.column("spotId", .text)
                    .references("spot")
                t.column("caughtAt", .datetime).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("geohash", .text)
                t.column("lengthCm", .double)
                t.column("weightKg", .double)
                t.column("released", .boolean).notNull().defaults(to: true)
                t.column("photoPath", .text) // local file path
                t.column("mlConfidence", .double)
                t.column("mlTop3", .text) // JSON
                t.column("forecastScoreAtCapture", .integer)
                t.column("weatherSnapshot", .text) // JSON
                t.column("tideSnapshot", .text) // JSON
                t.column("gearLoadoutId", .text)
                    .references("gearLoadout")
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(indexOn: "catch", columns: ["caughtAt"])
            try db.create(indexOn: "catch", columns: ["speciesId"])
            try db.create(indexOn: "catch", columns: ["geohash"])

            // Weather observations (local cache)
            try db.create(table: "weatherObservation") { t in
                t.column("timestamp", .datetime).notNull()
                t.column("geohash", .text).notNull() // precision 5
                t.column("pressureHpa", .double)
                t.column("tempC", .double)
                t.column("windSpeedMs", .double)
                t.column("windDirDeg", .integer)
                t.column("cloudPct", .integer)
                t.column("precipMm", .double)
                t.primaryKey(["timestamp", "geohash"])
            }

            // Forecasts (locally computed)
            try db.create(table: "forecast") { t in
                t.column("geohash", .text).notNull()
                t.column("speciesId", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("score", .integer).notNull() // 0-100
                t.column("reasons", .text) // JSON array of strings
                t.primaryKey(["geohash", "speciesId", "timestamp"])
            }
        }

        migrator.registerMigration("v2_trips") { db in
            try db.create(table: "trip") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime)
                t.column("spotId", .text).references("spot")
                t.column("notes", .text)
                t.column("weatherConditions", .text)
                t.column("createdAt", .datetime).notNull()
            }

            // Add tripId to catches
            try db.alter(table: "catch") { t in
                t.add(column: "tripId", .text).references("trip")
            }
        }

        return migrator
    }
}
