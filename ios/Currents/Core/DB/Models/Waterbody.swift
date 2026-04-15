import Foundation
import GRDB

struct Waterbody: Codable, Identifiable, Sendable {
    var id: Int64?
    var name: String
    var type: WaterbodyType
    var latitude: Double
    var longitude: Double
    var geohash: String?
    var maxDepthM: Double?
    var surfaceAreaKm2: Double?
    var globathyId: String?
    var isPublic: Bool
    var structureTypes: String? // JSON array e.g. ["rocky","sandy"]
    var description: String?
    var fishSpeciesIds: String? // JSON array of species IDs
    var averageDepthM: Double?
    var elevation: Double?
    var osmId: Int64? // OpenStreetMap feature ID for deduplication

    enum WaterbodyType: String, Codable, Sendable, CaseIterable {
        case dam
        case river
        case estuary
        case coast
        case lake
    }

    /// Decoded structure types from JSON string.
    var decodedStructureTypes: [String] {
        guard let data = structureTypes?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Decoded fish species IDs from JSON string.
    var decodedFishSpeciesIds: [Int64] {
        guard let data = fishSpeciesIds?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Int64].self, from: data)) ?? []
    }

    /// Approximate radius in meters based on surface area (assuming circular).
    var approximateRadiusM: Double {
        guard let area = surfaceAreaKm2, area > 0 else { return 500 }
        return sqrt(area / .pi) * 1000
    }
}

extension Waterbody: FetchableRecord, PersistableRecord {
    static let databaseTableName = "waterbody"
}
