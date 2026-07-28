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

    /// Case-insensitive exact match on the common name — a single indexed row
    /// fetch instead of loading the whole 1500+ species table to `.first { }`.
    func fetchByCommonName(_ name: String) throws -> Species? {
        try db.db.read { db in
            try Species
                .filter(Column("commonName").collating(.nocase) == name)
                .fetchOne(db)
        }
    }

    /// Best-effort match for a spoken / typed species name ("a largemouth bass"
    /// → Largemouth Bass). Strips lead-in words, then tries an exact match, a
    /// contains-match, and finally word-overlap. Returns nil if nothing fits.
    func resolve(spokenName raw: String) -> Species? {
        var q = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in ["log a ", "log ", "logged a ", "logged ", "caught a ", "caught ",
                     "a ", "an ", "the ", "one "] where q.hasPrefix(lead) {
            q = String(q.dropFirst(lead.count)); break
        }
        q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return nil }
        if let exact = try? fetchByCommonName(q) { return exact }
        // Contains-match, preferring the closest-length name.
        if let matches = try? search(q), !matches.isEmpty {
            return matches.min { abs($0.commonName.count - q.count) < abs($1.commonName.count - q.count) }
        }
        // Word-overlap fallback across the whole catalog.
        let qWords = Set(q.split(separator: " ").map(String.init))
        guard !qWords.isEmpty, let all = try? fetchAll() else { return nil }
        func overlap(_ s: Species) -> Int {
            Set(s.commonName.lowercased().split(separator: " ").map(String.init)).intersection(qWords).count
        }
        let best = all.max { overlap($0) < overlap($1) }
        return best.flatMap { overlap($0) > 0 ? $0 : nil }
    }

    /// Case-insensitive exact match on the scientific name (used to link a
    /// fishing regulation to its species artwork + guide page).
    func fetchByScientificName(_ name: String) throws -> Species? {
        try db.db.read { db in
            try Species
                .filter(Column("scientificName").collating(.nocase) == name)
                .fetchOne(db)
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

    /// Set of species IDs the user has logged at least one catch for.
    /// Drives the collection's caught / not-yet-caught state.
    func caughtSpeciesIds() throws -> Set<Int64> {
        try db.db.read { db in
            let ids = try Int64.fetchAll(
                db,
                sql: "SELECT DISTINCT speciesId FROM catch WHERE speciesId IS NOT NULL"
            )
            return Set(ids)
        }
    }

    /// Seed or upgrade species from the bundled dataset.
    ///
    /// Installs that seeded from an older, smaller dataset (the original 194)
    /// kept it forever because seeding was count==0-gated — so the species
    /// picker didn't reflect the species the rest of the app (artwork, AI ID
    /// embeddings) was built around. Now: whenever the bundled dataset has
    /// more species than the DB, every row is upserted (IDs are stable and
    /// additive across dataset builds, so existing catches keep pointing at
    /// the right species) and bait data is re-applied.
    /// Bump whenever the bundled dataset's CONTENT changes (not just its
    /// count) so existing installs re-upsert — e.g. when temps/baits were
    /// added for the non-curated species.
    private static let seedDataVersion = 4

    func seedIfNeeded() throws {
        let speciesList: [Species]
        do {
            speciesList = try JSONDecoder().decode([Species].self, from: SpeciesSeedData.json)
        } catch {
            print("[Currents] Failed to decode species seed data: \(error)")
            return
        }

        let count = try db.db.read { db in try Species.fetchCount(db) }
        let storedVersion = UserDefaults.standard.integer(forKey: "speciesSeedDataVersion")
        guard count < speciesList.count || storedVersion < Self.seedDataVersion else { return }

        // Upsert each row independently. A single bad row (e.g. a duplicate
        // scientificName hitting the UNIQUE index) must never roll back the
        // whole dataset — that once froze the DB at an old count and hid the
        // mythical species. Skip and log the offender, keep the rest.
        try db.db.write { db in
            var failed = 0
            for var species in speciesList {
                do {
                    try species.save(db) // upsert by primary key
                } catch {
                    failed += 1
                    print("[Currents] Skipped species \(species.id) during seed: \(error)")
                }
            }
            if failed > 0 { print("[Currents] \(failed) species rows skipped during seed") }
        }
        UserDefaults.standard.set(Self.seedDataVersion, forKey: "speciesSeedDataVersion")
        print("[Currents] Seeded/upgraded to \(speciesList.count) species (was \(count))")

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
