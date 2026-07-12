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
    // Planning: set when a session is scheduled ahead of time (not yet started).
    var plannedDate: Date?
    var plannedLatitude: Double?
    var plannedLongitude: Double?
    // Multi-day: `days` holds finished days (JSON [DayLog]); `currentDayStart`
    // marks when the in-progress day began (its track is in `trackPoints`).
    var days: String?
    var currentDayStart: Date?
    /// JSON-encoded gear checklist ([ChecklistItem]) set when planning, so it
    /// persists and stays editable.
    var checklist: String?
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
        trackPoints: String? = nil,
        plannedDate: Date? = nil,
        plannedLatitude: Double? = nil,
        plannedLongitude: Double? = nil,
        days: String? = nil,
        currentDayStart: Date? = nil,
        checklist: String? = nil
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
        self.plannedDate = plannedDate
        self.plannedLatitude = plannedLatitude
        self.plannedLongitude = plannedLongitude
        self.days = days
        self.currentDayStart = currentDayStart
        self.checklist = checklist
        self.createdAt = .now
    }

    // MARK: - Planning checklist

    struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
        var id = UUID()
        var name: String
        var checked: Bool = false
    }

    var decodedChecklist: [ChecklistItem] {
        guard let checklist, let data = checklist.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ChecklistItem].self, from: data)) ?? []
    }

    static func encodeChecklist(_ items: [ChecklistItem]) -> String? {
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A scheduled-but-not-started session.
    var isPlanned: Bool { plannedDate != nil && endDate == nil }

    var plannedCoordinate: CLLocationCoordinate2D? {
        guard let plannedLatitude, let plannedLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: plannedLatitude, longitude: plannedLongitude)
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
    /// Currently-recording session (not planned, not ended).
    var isActive: Bool { endDate == nil && plannedDate == nil }
    var isCompleted: Bool { endDate != nil }

    // MARK: - Multi-day

    /// One outing within a multi-day trip.
    struct DayLog: Codable, Sendable, Identifiable {
        var index: Int
        var start: Date
        var end: Date
        var trackPoints: String?
        var notes: String?

        var id: Int { index }
        var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
        var track: [TrackPoint] {
            guard let trackPoints, let data = trackPoints.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TrackPoint].self, from: data)) ?? []
        }
        var distanceMeters: Double {
            let pts = track
            guard pts.count > 1 else { return 0 }
            var total = 0.0
            for i in 1..<pts.count {
                total += CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                    .distance(from: CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon))
            }
            return total
        }
    }

    var decodedDays: [DayLog] {
        guard let days, let data = days.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DayLog].self, from: data)) ?? []
    }

    static func encodeDays(_ days: [DayLog]) -> String? {
        guard !days.isEmpty, let data = try? JSONEncoder().encode(days) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every day of the trip, uniform across single- and multi-day trips:
    /// finished days plus the current/last day (synthesised from the trip's own
    /// track for legacy single-day trips that predate the day model).
    var allDayLogs: [DayLog] {
        var result = decodedDays
        if let cds = currentDayStart {
            result.append(DayLog(index: result.count, start: cds, end: endDate ?? .now,
                                 trackPoints: trackPoints, notes: nil))
        } else if result.isEmpty {
            result.append(DayLog(index: 0, start: startDate, end: endDate ?? .now,
                                 trackPoints: trackPoints, notes: notes))
        }
        return result
    }

    var dayCount: Int { max(1, allDayLogs.count) }
    var isMultiDay: Bool { !decodedDays.isEmpty }

    /// Total distance/duration across every day of the trip.
    var totalTrackDistanceMeters: Double { allDayLogs.reduce(0) { $0 + $1.distanceMeters } }
    var totalDurationSeconds: TimeInterval { allDayLogs.reduce(0) { $0 + $1.durationSeconds } }

    /// All track points across every day, for drawing the full route.
    var allTrackPoints: [TrackPoint] { allDayLogs.flatMap(\.track) }
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
