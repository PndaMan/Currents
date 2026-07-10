import Foundation
import WidgetKit

/// Composes and persists the shared widget snapshot, preserving fields it isn't
/// updating. Reloads widget timelines after each write.
@MainActor
enum WidgetSnapshotWriter {

    static func writeBite(score: Int, verdict: String, location: String) {
        var s = SharedStore.load() ?? CurrentsSnapshot()
        s.biteScore = score
        s.biteVerdict = verdict
        if !location.isEmpty { s.locationName = location }
        s.updatedAt = .now
        SharedStore.save(s)
        reload()
    }

    static func writeActiveSession(name: String?, start: Date?, catches: Int) {
        var s = SharedStore.load() ?? CurrentsSnapshot()
        s.activeSessionName = name
        s.activeSessionStart = start
        s.activeSessionCatches = catches
        SharedStore.save(s)
        reload()
    }

    static func writeNextSession(name: String?, date: Date?) {
        var s = SharedStore.load() ?? CurrentsSnapshot()
        s.nextSessionName = name
        s.nextSessionDate = date
        SharedStore.save(s)
        reload()
    }

    private static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
