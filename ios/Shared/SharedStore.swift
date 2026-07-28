import Foundation

/// Tiny snapshot the main app writes into the shared App Group container so the
/// home-screen widgets can render without launching the app. Kept deliberately
/// small (Codable → JSON in shared UserDefaults).
/// One hour's bite score, so widgets + the watch face can tick through the day
/// on their own timeline without the app relaunching each hour.
public struct SnapHour: Codable, Equatable {
    public var date: Date
    public var score: Int
    public init(date: Date, score: Int) { self.date = date; self.score = score }
}

public struct CurrentsSnapshot: Codable, Equatable {
    public var biteScore: Int
    public var biteVerdict: String
    public var locationName: String
    public var updatedAt: Date

    /// Next planned session, if any.
    public var nextSessionName: String?
    public var nextSessionDate: Date?

    /// Active session, if one is recording.
    public var activeSessionName: String?
    public var activeSessionStart: Date?
    public var activeSessionCatches: Int

    /// Upcoming hourly bite scores (optional; drives hourly widget/complication
    /// updates). Empty on older snapshots.
    public var hourly: [SnapHour]

    public init(biteScore: Int = 0, biteVerdict: String = "—", locationName: String = "",
                updatedAt: Date = .now, nextSessionName: String? = nil, nextSessionDate: Date? = nil,
                activeSessionName: String? = nil, activeSessionStart: Date? = nil,
                activeSessionCatches: Int = 0, hourly: [SnapHour] = []) {
        self.biteScore = biteScore
        self.biteVerdict = biteVerdict
        self.locationName = locationName
        self.updatedAt = updatedAt
        self.nextSessionName = nextSessionName
        self.nextSessionDate = nextSessionDate
        self.activeSessionName = activeSessionName
        self.activeSessionStart = activeSessionStart
        self.activeSessionCatches = activeSessionCatches
        self.hourly = hourly
    }

    /// The score for the current hour from `hourly`, falling back to `biteScore`.
    public func score(at date: Date = .now) -> Int {
        hourly.last(where: { $0.date <= date })?.score
            ?? hourly.first?.score
            ?? biteScore
    }

    // Tolerant decoding so snapshots written before `hourly` existed still load.
    private enum CodingKeys: String, CodingKey {
        case biteScore, biteVerdict, locationName, updatedAt, nextSessionName,
             nextSessionDate, activeSessionName, activeSessionStart, activeSessionCatches, hourly
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        biteScore = try c.decodeIfPresent(Int.self, forKey: .biteScore) ?? 0
        biteVerdict = try c.decodeIfPresent(String.self, forKey: .biteVerdict) ?? "—"
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        nextSessionName = try c.decodeIfPresent(String.self, forKey: .nextSessionName)
        nextSessionDate = try c.decodeIfPresent(Date.self, forKey: .nextSessionDate)
        activeSessionName = try c.decodeIfPresent(String.self, forKey: .activeSessionName)
        activeSessionStart = try c.decodeIfPresent(Date.self, forKey: .activeSessionStart)
        activeSessionCatches = try c.decodeIfPresent(Int.self, forKey: .activeSessionCatches) ?? 0
        hourly = try c.decodeIfPresent([SnapHour].self, forKey: .hourly) ?? []
    }
}

/// Read/write access to the shared snapshot, used by both the app (writer) and
/// the widget extension (reader).
public enum SharedStore {
    /// Must match the App Group configured on both targets' entitlements.
    public static let appGroup = "group.com.aidanmcconnon.currents"
    private static let key = "currentsSnapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    public static func save(_ snapshot: CurrentsSnapshot) {
        guard let d = defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        d.set(data, forKey: key)
    }

    public static func load() -> CurrentsSnapshot? {
        guard let d = defaults, let data = d.data(forKey: key),
              let snap = try? JSONDecoder().decode(CurrentsSnapshot.self, from: data) else { return nil }
        return snap
    }
}
