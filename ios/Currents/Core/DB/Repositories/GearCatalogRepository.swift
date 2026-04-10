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

    func seedIfEmpty() throws {
        let count = try db.db.read { db in try GearItem.fetchCount(db) }
        guard count == 0 else { return }

        guard let url = Bundle.main.url(forResource: "gear_catalog_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([GearItem].self, from: data) else {
            return
        }

        try db.db.write { db in
            for var item in items {
                try item.insert(db)
            }
        }
    }
}
