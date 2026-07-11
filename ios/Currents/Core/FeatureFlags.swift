import Foundation

/// Compile-time feature gates.
///
/// Features that exist in the codebase but are not ready for the current
/// release are hidden here rather than deleted, so they can be re-enabled
/// by flipping a single flag.
enum FeatureFlags {
    /// Live fishing-session tracking (GPS track, catch limits, planner).
    static let liveTrips = true

    /// Legacy per-spot public/private toggle. Spot sharing now goes through the
    /// opt-in Community (share directly to a friend), so this old global flag
    /// stays hidden.
    static let spotPrivacy = false
}
