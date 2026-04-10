import Foundation
import GRDB

@MainActor
final class SpeciesRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func fetchAll() throws -> [Species] {
        try db.db.read { db in
            try Species.order(Column("commonName")).fetchAll(db)
        }
    }

    func search(_ query: String) throws -> [Species] {
        try db.db.read { db in
            try Species
                .filter(
                    Column("commonName").like("%\(query)%") ||
                    Column("scientificName").like("%\(query)%")
                )
                .order(Column("commonName"))
                .fetchAll(db)
        }
    }

    func fetch(id: Int64) throws -> Species? {
        try db.db.read { db in
            try Species.fetchOne(db, key: id)
        }
    }

    func fetchByHabitat(_ habitat: Species.Habitat) throws -> [Species] {
        try db.db.read { db in
            try Species
                .filter(Column("habitat") == habitat.rawValue)
                .order(Column("commonName"))
                .fetchAll(db)
        }
    }

    /// Seed species from bundled JSON data.
    func seedIfEmpty() throws {
        let count = try db.db.read { db in try Species.fetchCount(db) }
        guard count == 0 else { return }

        guard let url = Self.findBundleResource("species_seed", ext: "json") else {
            print("[Currents] ⚠️ species_seed.json not found in bundle")
            return
        }

        let speciesList: [Species]
        do {
            let data = try Data(contentsOf: url)
            speciesList = try JSONDecoder().decode([Species].self, from: data)
        } catch {
            print("[Currents] ⚠️ Failed to decode species_seed.json: \(error)")
            return
        }

        try db.db.write { db in
            for var species in speciesList {
                try species.insert(db)
            }
        }
        print("[Currents] ✅ Seeded \(speciesList.count) species")
    }

    /// Search all possible bundle paths for a resource file.
    private static func findBundleResource(_ name: String, ext: String) -> URL? {
        // Direct lookup (file at bundle root)
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Common subdirectories XcodeGen might create
        for sub in ["Data", "Resources/Data", "Resources"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        // Last resort: search the entire bundle
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
