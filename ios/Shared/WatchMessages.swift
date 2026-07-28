import Foundation

/// Message keys shared between the iOS app and the watchOS companion over
/// WatchConnectivity. The watch sends an `action`; the phone replies with a
/// state dictionary describing the current session + bite score.
public enum WatchMessage {
    public static let action = "action"

    // Actions the watch can request.
    public static let requestState = "state"
    public static let startSession = "start"
    public static let endSession = "end"
    public static let logCatch = "log"

    // Reply / application-context keys describing phone state.
    public static let isTracking = "isTracking"
    public static let sessionName = "sessionName"
    public static let sessionStart = "sessionStart"   // epoch seconds
    public static let catchCount = "catchCount"
    public static let biteScore = "biteScore"
    /// Short human string for the next prime feeding window, e.g. "6–8 AM".
    public static let nextPrimeWindow = "nextPrimeWindow"
    /// Species name (typed/dictated on the watch) to attach to a logged catch.
    public static let speciesName = "speciesName"
    /// Recent species [String] sent to the watch for quick-log buttons.
    public static let recentSpecies = "recentSpecies"
    /// Upcoming hourly bite scores: [[epochSeconds, score]] so the watch face
    /// can tick through the day on its own.
    public static let hourly = "hourly"
    public static let ok = "ok"
}
