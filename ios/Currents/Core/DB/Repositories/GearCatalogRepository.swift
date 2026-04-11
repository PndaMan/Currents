import Foundation
import GRDB

@MainActor
final class GearCatalogRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func fetchAll() throws -> [GearItem] {
        try db.db.read { db in
            try GearItem.order(Column("brand"), Column("model")).fetchAll(db)
        }
    }

    func fetchByCategory(_ category: GearItem.GearCategory) throws -> [GearItem] {
        try db.db.read { db in
            try GearItem
                .filter(Column("category") == category.rawValue)
                .order(Column("brand"), Column("model"))
                .fetchAll(db)
        }
    }

    func search(_ query: String) throws -> [GearItem] {
        try db.db.read { db in
            try GearItem
                .filter(
                    Column("brand").like("%\(query)%") ||
                    Column("model").like("%\(query)%") ||
                    Column("type").like("%\(query)%") ||
                    Column("targetSpecies").like("%\(query)%")
                )
                .order(Column("brand"), Column("model"))
                .fetchAll(db)
        }
    }

    /// Seed gear catalog from embedded data (compiled into binary).
    func seedIfEmpty() throws {
        let count = try db.db.read { db in try GearItem.fetchCount(db) }
        guard count == 0 else { return }

        let items: [GearItem]
        do {
            items = try JSONDecoder().decode([GearItem].self, from: GearCatalogSeedData.json)
        } catch {
            print("[Currents] Failed to decode gear catalog seed data: \(error)")
            return
        }

        try db.db.write { db in
            for var item in items {
                try item.insert(db)
            }
        }
        print("[Currents] Seeded \(items.count) gear catalog items")
    }
}
