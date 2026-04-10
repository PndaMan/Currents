import Foundation
import GRDB

/// Tracks personal best catches per species. Auto-computed from catch data.
struct PersonalBest: Sendable {
    let speciesId: Int64
    let commonName: String
    let scientificName: String
    let heaviestKg: Double?
    let longestCm: Double?
    let heaviestCatchId: String?
    let longestCatchId: String?
    let totalCatches: Int
    let firstCaught: Date?
    let lastCaught: Date?
}
