import Foundation
// ActivityKit is unavailable on watchOS — this type is only used by the iOS app
// and its widget extension, so guard the whole file for those platforms.
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity descriptor for an active fishing session. The static
/// `attributes` hold the session name; the dynamic `ContentState` carries the
/// values that tick during the session (elapsed handled by the widget via the
/// start date, plus catch count, bite score, and an optional catch-limit line).
public struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startDate: Date
        public var catchCount: Int
        public var biteScore: Int
        /// e.g. "2 / 4 kept" — nil when no bag limit applies to logged species.
        public var catchLimitText: String?

        public init(startDate: Date, catchCount: Int, biteScore: Int, catchLimitText: String? = nil) {
            self.startDate = startDate
            self.catchCount = catchCount
            self.biteScore = biteScore
            self.catchLimitText = catchLimitText
        }
    }

    public var sessionName: String

    public init(sessionName: String) {
        self.sessionName = sessionName
    }
}
#endif
