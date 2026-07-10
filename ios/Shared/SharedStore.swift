import Foundation

/// Tiny snapshot the main app writes into the shared App Group container so the
/// home-screen widgets can render without launching the app. Kept deliberately
/// small (Codable → JSON in shared UserDefaults).
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

    public init(biteScore: Int = 0, biteVerdict: String = "—", locationName: String = "",
                updatedAt: Date = .now, nextSessionName: String? = nil, nextSessionDate: Date? = nil,
                activeSessionName: String? = nil, activeSessionStart: Date? = nil,
                activeSessionCatches: Int = 0) {
        self.biteScore = biteScore
        self.biteVerdict = biteVerdict
        self.locationName = locationName
        self.updatedAt = updatedAt
        self.nextSessionName = nextSessionName
        self.nextSessionDate = nextSessionDate
        self.activeSessionName = activeSessionName
        self.activeSessionStart = activeSessionStart
        self.activeSessionCatches = activeSessionCatches
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
