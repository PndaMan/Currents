import XCTest
import GRDB
@testable import Currents

final class DatabaseTests: XCTestCase {

    var db: AppDatabase!

    override func setUp() async throws {
        db = try AppDatabase.empty()
    }

    func testMigrationsRun() throws {
        // If we got here, migrations succeeded on the empty DB
        let count = try db.db.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM sqlite_master WHERE type='table'")
        }
        // Should have our 8 tables + sqlite internal tables
        XCTAssertGreaterThanOrEqual(count ?? 0, 8)
    }

    func testInsertAndFetchSpot() throws {
        var spot = Spot(name: "Test Spot", latitude: -33.9, longitude: 18.4)
        try db.db.write { db in
            try spot.save(db)
        }

        let fetched = try db.db.read { db in
            try Spot.fetchOne(db, key: spot.id)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test Spot")
        XCTAssertNotNil(fetched?.geohash, "Geohash should be computed")
    }

    func testInsertAndFetchCatch() throws {
        var catchRecord = Catch(
            latitude: -33.9,
            longitude: 18.4,
            lengthCm: 45.0,
            weightKg: 2.5,
            released: true
        )
        try db.db.write { db in
            try catchRecord.save(db)
        }

        let fetched = try db.db.read { db in
            try Catch.fetchOne(db, key: catchRecord.id)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.lengthCm, 45.0)
        XCTAssertEqual(fetched?.weightKg, 2.5)
        XCTAssertTrue(fetched?.released ?? false)
    }

    func testInsertAndFetchGearLoadout() throws {
        var gear = GearLoadout(
            name: "Bass Setup",
            rod: "Shimano Curado",
            lure: "Senko",
            lureColor: "Green Pumpkin",
            technique: "Drop shot"
        )
        try db.db.write { db in
            try gear.save(db)
        }

        let fetched = try db.db.read { db in
            try GearLoadout.fetchOne(db, key: gear.id)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Bass Setup")
        XCTAssertEqual(fetched?.technique, "Drop shot")
    }

    func testCatchSpotForeignKey() throws {
        var spot = Spot(name: "Pier", latitude: -34.0, longitude: 18.5)
        try db.db.write { db in try spot.save(db) }

        var catchRecord = Catch(
            spotId: spot.id,
            latitude: -34.0,
            longitude: 18.5
        )
        try db.db.write { db in try catchRecord.save(db) }

        let fetched = try db.db.read { db in
            try Catch.filter(Column("spotId") == spot.id).fetchOne(db)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.spotId, spot.id)
    }

    func testSpeciesSeed() throws {
        // Insert a species manually
        try db.db.write { db in
            var species = Species(
                id: 1,
                scientificName: "Micropterus salmoides",
                commonName: "Largemouth Bass",
                family: "Centrarchidae",
                habitat: .freshwater,
                optimalTempC: 21.0
            )
            try species.insert(db)
        }

        let fetched = try db.db.read { db in
            try Species.fetchOne(db, key: 1)
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.commonName, "Largemouth Bass")
        XCTAssertEqual(fetched?.habitat, .freshwater)
    }

    func testSpawningZoneActiveMonth() {
        let zone = SpawningZone(
            id: 1,
            speciesId: 1,
            latitude: -33.0,
            longitude: 18.0,
            radiusKm: 10.0,
            months: "[9,10,11]"
        )
        XCTAssertTrue(zone.isActive(inMonth: 9))
        XCTAssertTrue(zone.isActive(inMonth: 10))
        XCTAssertFalse(zone.isActive(inMonth: 3))
    }

    func testDeleteCatch() throws {
        var catchRecord = Catch(latitude: 0, longitude: 0)
        try db.db.write { db in try catchRecord.save(db) }

        let countBefore = try db.db.read { db in try Catch.fetchCount(db) }
        XCTAssertEqual(countBefore, 1)

        try db.db.write { db in _ = try catchRecord.delete(db) }

        let countAfter = try db.db.read { db in try Catch.fetchCount(db) }
        XCTAssertEqual(countAfter, 0)
    }
}
