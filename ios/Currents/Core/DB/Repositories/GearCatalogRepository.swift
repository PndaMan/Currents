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

        guard let url = Self.findBundleResource("gear_catalog_seed", ext: "json") else {
            print("[Currents] ⚠️ gear_catalog_seed.json not found in bundle")
            return
        }

        let items: [GearItem]
        do {
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([GearItem].self, from: data)
        } catch {
            print("[Currents] ⚠️ Failed to decode gear_catalog_seed.json: \(error)")
            return
        }

        try db.db.write { db in
            for var item in items {
                try item.insert(db)
            }
        }
        print("[Currents] ✅ Seeded \(items.count) gear catalog items")
    }

    private static func findBundleResource(_ name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        for sub in ["Data", "Resources/Data", "Resources"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        if let bundlePath = Bundle.main.resourcePath {
            let fm = FileManager.default
            if let enumerator = fm.enumerator(atPath: bundlePath) {
                let target = "\(name).\(ext)"
                while let path = enumerator.nextObject() as? String {
                    if (path as NSString).lastPathComponent == target {
                        return URL(fileURLWithPath: bundlePath).appendingPathComponent(path)
                    }
                }
            }
        }
        return nil
    }
}
