import Foundation
import GRDB

@MainActor
final class OwnedGearRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func save(_ gear: inout OwnedGear) throws {
        try db.db.write { db in
            try gear.save(db)
        }
    }

    func delete(_ gear: OwnedGear) throws {
        try db.db.write { db in
            _ = try gear.delete(db)
        }
    }

    func fetchAll() throws -> [OwnedGear] {
        try db.db.read { db in
            try OwnedGear.order(Column("category"), Column("name")).fetchAll(db)
        }
    }

    func fetch(category: OwnedGear.Category) throws -> [OwnedGear] {
        try db.db.read { db in
            try OwnedGear
                .filter(Column("category") == category.rawValue)
                .order(Column("name"))
                .fetchAll(db)
        }
    }
}
