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
