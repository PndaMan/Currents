import Foundation
import GRDB

struct Species: Codable, Identifiable, Sendable {
    var id: Int64
    var scientificName: String
    var commonName: String
    var family: String?
    var habitat: Habitat?
    var minTempC: Double?
    var maxTempC: Double?
    var optimalTempC: Double?
    var fishbaseId: Int64?
    var imageUrl: String?
    var recommendedBaits: String? // JSON array of strings
    var baitNotes: String?

    /// Decoded bait recommendations from JSON string.
    var parsedBaits: [String] {
        guard let data = recommendedBaits?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    enum Habitat: String, Codable, Sendable, CaseIterable {
        case freshwater
        case marine
        case brackish
    }
}

extension Species: FetchableRecord, PersistableRecord {
    static let databaseTableName = "species"
}

extension Species {
    static let catches = hasMany(Catch.self)

    var catches: QueryInterfaceRequest<Catch> {
        request(for: Species.catches)
    }
}
