import Foundation
import GRDB

struct GearLoadout: Codable, Identifiable, Sendable {
    var id: String // UUID
    var name: String
    var rod: String?
    var reel: String?
    var lineLb: Double?
    var leaderLb: Double?
    var lure: String?
    var lureColor: String?
    var lureWeightG: Double?
    var technique: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        rod: String? = nil,
        reel: String? = nil,
        lineLb: Double? = nil,
        leaderLb: Double? = nil,
        lure: String? = nil,
        lureColor: String? = nil,
        lureWeightG: Double? = nil,
        technique: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.rod = rod
        self.reel = reel
        self.lineLb = lineLb
        self.leaderLb = leaderLb
        self.lure = lure
        self.lureColor = lureColor
        self.lureWeightG = lureWeightG
        self.technique = technique
        self.createdAt = createdAt
    }
}

extension GearLoadout: FetchableRecord, PersistableRecord {
    static let databaseTableName = "gearLoadout"
}

extension GearLoadout {
    static let catches = hasMany(Catch.self)
}
