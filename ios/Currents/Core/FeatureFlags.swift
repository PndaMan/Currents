import Foundation

/// Compile-time feature gates.
///
/// Features that exist in the codebase but are not ready for the current
/// release are hidden here rather than deleted, so they can be re-enabled
/// by flipping a single flag.
enum FeatureFlags {
    /// Live fishing-session tracking (GPS track, catch limits, planner).
    static let liveTrips = true

    /// Public/private spot sharing. The app is fully offline right now, so
    /// spot privacy is meaningless — hide it everywhere until sharing exists.
    static let spotPrivacy = false
}
