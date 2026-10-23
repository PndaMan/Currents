import Foundation
import GRDB

/// Per-spot notification choices. A spot without a row follows the defaults
/// on the Notifications screen, so only spots the angler has changed are
/// stored. Removed with the spot (foreign key cascade).
struct SpotAlert: Codable, Sendable, Equatable {
    var spotId: String
    /// A notification when a bite window opens at this spot.
    var biteAlerts: Bool
    /// A heads-up about 45 minutes before the window opens.
    var headsUp: Bool
    /// The score a window must reach here. Nil follows the default threshold.
    var threshold: Int?

    static func defaults(for spotId: String) -> SpotAlert {
        SpotAlert(spotId: spotId, biteAlerts: true, headsUp: true, threshold: nil)
    }

    var isDefault: Bool { biteAlerts && headsUp && threshold == nil }
}

extension SpotAlert: FetchableRecord, PersistableRecord {
    static let databaseTableName = "spotAlert"
}
