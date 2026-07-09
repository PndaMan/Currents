import Foundation
import GRDB
import CoreLocation

struct Trip: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var startDate: Date
    var endDate: Date?
    var spotId: String?
    var notes: String?
    var weatherConditions: String? // "clear", "cloudy", "rain", etc.
    var photoPaths: String? // JSON array of photo filenames stored via PhotoManager
    var trackPoints: String? // JSON array of GPS breadcrumb points
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        startDate: Date = .now,
        endDate: Date? = nil,
        spotId: String? = nil,
        notes: String? = nil,
        weatherConditions: String? = nil,
        photoPaths: String? = nil,
        trackPoints: String? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.spotId = spotId
        self.notes = notes
        self.weatherConditions = weatherConditions
        self.photoPaths = photoPaths
        self.trackPoints = trackPoints
        self.createdAt = .now
    }

    /// Decoded photo filenames.
    var allPhotoPaths: [String] {
        guard let photoPaths, let data = photoPaths.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Encode filenames to JSON for storage.
    static func encodePhotoPaths(_ paths: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(paths),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: - GPS track

    /// A single GPS breadcrumb recorded during a live session.
    struct TrackPoint: Codable, Sendable, Hashable {
        var lat: Double
        var lon: Double
        var t: Date
    }

    var decodedTrack: [TrackPoint] {
        guard let trackPoints, let data = trackPoints.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TrackPoint].self, from: data)) ?? []
    }

    static func encodeTrack(_ points: [TrackPoint]) -> String? {
        guard !points.isEmpty, let data = try? JSONEncoder().encode(points) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Total distance along the recorded track, in metres.
    var trackDistanceMeters: Double {
        let pts = decodedTrack
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                .distance(from: CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon))
        }
        return total
    }

    /// Elapsed session time (running total if still active).
    var durationSeconds: TimeInterval { (endDate ?? .now).timeIntervalSince(startDate) }
    var isActive: Bool { endDate == nil }
}

extension Trip: FetchableRecord, PersistableRecord {
    static let databaseTableName = "trip"
}

extension Trip {
    static let catches = hasMany(Catch.self)
    static let spot = belongsTo(Spot.self)
}

struct TripDetail: Decodable, FetchableRecord, Sendable {
    var trip: Trip
    var spot: Spot?

    enum CodingKeys: String, CodingKey {
        case trip
        case spot
    }
}
