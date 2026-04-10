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

        guard let url = Bundle.main.url(forResource: "species_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let speciesList = try? JSONDecoder().decode([Species].self, from: data) else {
            return
        }

        try db.db.write { db in
            for var species in speciesList {
                try species.insert(db)
            }
        }
    }
}
