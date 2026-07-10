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
    public static let ok = "ok"
}
