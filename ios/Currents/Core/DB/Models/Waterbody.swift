import Foundation
import GRDB

struct Waterbody: Codable, Identifiable, Sendable {
    var id: Int64
    var name: String
    var type: WaterbodyType
    var latitude: Double
    var longitude: Double
    var geohash: String?
    var maxDepthM: Double?
    var surfaceAreaKm2: Double?
    var globathyId: String?

    enum WaterbodyType: String, Codable, Sendable, CaseIterable {
        case dam
        case river
        case estuary
        case coast
    }
}

extension Waterbody: FetchableRecord, PersistableRecord {
    static let databaseTableName = "waterbody"
}
