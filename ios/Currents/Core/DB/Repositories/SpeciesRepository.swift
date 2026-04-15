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

    /// Seed species from embedded data (compiled into binary).
    func seedIfEmpty() throws {
        let count = try db.db.read { db in try Species.fetchCount(db) }
        guard count == 0 else { return }

        let speciesList: [Species]
        do {
            speciesList = try JSONDecoder().decode([Species].self, from: SpeciesSeedData.json)
        } catch {
            print("[Currents] Failed to decode species seed data: \(error)")
            return
        }

        try db.db.write { db in
            for var species in speciesList {
                try species.insert(db)
            }
        }
        print("[Currents] Seeded \(speciesList.count) species")

        // Apply bait recommendations
        seedBaits()
    }

    /// Apply bait recommendation data to existing species records.
    func seedBaits() {
        do {
            try db.db.write { db in
                for entry in BaitSeedData.entries {
                    let baitsJSON = try JSONEncoder().encode(entry.baits)
                    let baitsString = String(data: baitsJSON, encoding: .utf8)
                    try db.execute(
                        sql: "UPDATE species SET recommendedBaits = ?, baitNotes = ? WHERE id = ?",
                        arguments: [baitsString, entry.notes, entry.speciesId]
                    )
                }
            }
            print("[Currents] Applied bait data to \(BaitSeedData.entries.count) species")
        } catch {
            print("[Currents] Failed to seed bait data: \(error)")
        }
    }
}
