import Foundation
import WidgetKit

/// Composes and persists the shared widget snapshot, preserving fields it isn't
/// updating. Reloads widget timelines after each write.
@MainActor
enum WidgetSnapshotWriter {

    static func writeBite(score: Int, verdict: String, location: String, hourly: [SnapHour] = []) {
        var s = SharedStore.load() ?? CurrentsSnapshot()
        s.biteScore = score
        s.biteVerdict = verdict
        if !location.isEmpty { s.locationName = location }
        if !hourly.isEmpty { s.hourly = hourly }
        s.updatedAt = .now
        SharedStore.save(s)
        reload()
        // Keep the watch face's hourly scores in step too.
        PhoneConnectivity.shared.pushState()
    }

    /// Convert a forecast's `hourlyScores` (hour-of-day → score) into dated
    /// upcoming entries starting at the current hour, spanning ~18 hours.
    static func hourlyEntries(from hourlyScores: [(hour: Int, score: Int)], now: Date = .now) -> [SnapHour] {
        guard !hourlyScores.isEmpty else { return [] }
        let cal = Calendar.current
        let byHour = Dictionary(hourlyScores.map { ($0.hour, $0.score) }, uniquingKeysWith: { a, _ in a })
        let start = cal.date(bySetting: .minute, value: 0, of: now) ?? now
        return (0..<18).compactMap { offset -> SnapHour? in
            guard let date = cal.date(byAdding: .hour, value: offset, to: start) else { return nil }
            let hour = cal.component(.hour, from: date)
            guard let score = byHour[hour] else { return nil }
            return SnapHour(date: date, score: score)
        }
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
