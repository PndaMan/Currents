import Foundation
import GRDB

/// Cached fish species observation from iNaturalist or GBIF.
/// Stores which fish have been observed near a geohash cell (precision 3).
struct ObservedSpeciesCache: Codable, Identifiable, Sendable {
    var id: Int64?
    var geohashCell: String       // geohash precision-3 for the query area
    var scientificName: String
    var commonName: String?
    var observationCount: Int
    var source: String            // "iNaturalist" or "GBIF"
    var iNaturalistTaxonId: Int64?
    var photoUrl: String?
    var localSpeciesId: Int64?    // Matched to our species table
    var fetchedAt: Date
}

extension ObservedSpeciesCache: FetchableRecord, PersistableRecord {
    static let databaseTableName = "observedSpeciesCache"
}
