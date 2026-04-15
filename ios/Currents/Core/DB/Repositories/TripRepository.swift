import Foundation
import GRDB

@MainActor
final class TripRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func save(_ trip: inout Trip) throws {
        try db.db.write { db in
            try trip.save(db)
        }
    }

    func delete(_ trip: Trip) throws {
        try db.db.write { db in
            _ = try trip.delete(db)
        }
    }

    func fetch(_ id: String) throws -> Trip? {
        try db.db.read { db in
            try Trip.fetchOne(db, key: id)
        }
    }

    func fetchAll() throws -> [Trip] {
        try db.db.read { db in
            try Trip.order(Column("startDate").desc).fetchAll(db)
        }
    }

    func fetchActive() throws -> [Trip] {
        try db.db.read { db in
            try Trip
                .filter(Column("endDate") == nil)
                .order(Column("startDate").desc)
                .fetchAll(db)
        }
    }

    func fetchWithDetails() throws -> [TripDetail] {
        try db.db.read { db in
            let request = Trip
                .including(optional: Trip.spot)
                .order(Column("startDate").desc)
            return try TripDetail.fetchAll(db, request)
        }
    }

    func catchCount(tripId: String) throws -> Int {
        try db.db.read { db in
            try Catch
                .filter(Column("tripId") == tripId)
                .fetchCount(db)
        }
    }

    func catches(tripId: String) throws -> [CatchDetail] {
        try db.db.read { db in
            let request = Catch
                .filter(Column("tripId") == tripId)
                .including(optional: Catch.species)
                .including(optional: Catch.spot)
                .including(optional: Catch.gearLoadout)
                .order(Column("caughtAt").desc)
            return try CatchDetail.fetchAll(db, request)
        }
    }
}
