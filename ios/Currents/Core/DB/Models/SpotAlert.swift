import Foundation
import GRDB

/// Per-spot notification choices. A spot saved on this phone gets a row with
/// its alerts off (`off(for:)`), so alerts only come from spots the angler
/// turned on. A spot without a row (saved before that, or synced from
/// another phone) follows the defaults, so only spots that differ from them
/// are stored. Removed with the spot (foreign key cascade).
struct SpotAlert: Codable, Sendable, Equatable {
    var spotId: String
    /// The spot's own switch. Off sends nothing from this spot and keeps the
    /// choices below for when it is turned back on.
    var enabled: Bool
    /// A notification when a bite window opens at this spot.
    var biteAlerts: Bool
    /// A heads-up about 45 minutes before the window opens.
    var headsUp: Bool
    /// The score a window must reach here. Nil follows the default threshold.
    var threshold: Int?

    static func defaults(for spotId: String) -> SpotAlert {
        SpotAlert(spotId: spotId, enabled: true, biteAlerts: true, headsUp: true, threshold: nil)
    }

    /// A new spot's choice: switched off, with both kinds ready for when the
    /// angler turns the spot on.
    static func off(for spotId: String) -> SpotAlert {
        SpotAlert(spotId: spotId, enabled: false, biteAlerts: true, headsUp: true, threshold: nil)
    }

    var isDefault: Bool { enabled && biteAlerts && headsUp && threshold == nil }
}

extension SpotAlert: FetchableRecord, PersistableRecord {
    static let databaseTableName = "spotAlert"
}
