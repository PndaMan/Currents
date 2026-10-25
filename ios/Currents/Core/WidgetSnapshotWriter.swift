import Foundation
import WidgetKit

/// Composes and persists the shared widget snapshot, preserving fields it isn't
/// updating. Reloads widget timelines after each write.
@MainActor
enum WidgetSnapshotWriter {

    static func writeBite(score: Int, location: String, latitude: Double, longitude: Double,
                          hourly: [SnapHour] = []) {
        var s = SharedStore.load() ?? CurrentsSnapshot()
        s.biteScore = score
        s.biteVerdict = BiteVerdict.word(score)
        if !location.isEmpty { s.locationName = location }
        s.latitude = latitude
        s.longitude = longitude
        if !hourly.isEmpty { s.hourly = hourly }
        s.updatedAt = .now
        SharedStore.save(s)
        reload()
        // Keep the watch face's hourly scores in step too.
        PhoneConnectivity.shared.pushState()
    }

    /// Dated hourly scores from the start of this hour through tomorrow, so
    /// the widget can tick on its own until the app or a background refresh
    /// writes again. Hours after midnight come from tomorrow's forecast, not
    /// today's scores for the same clock hour.
    static func hourlyEntries(today: [(hour: Int, score: Int)],
                              tomorrow: [(hour: Int, score: Int)],
                              now: Date = .now) -> [SnapHour] {
        guard !today.isEmpty else { return [] }
        let cal = Calendar.current
        let todayByHour = Dictionary(today.map { ($0.hour, $0.score) }, uniquingKeysWith: { a, _ in a })
        let tomorrowByHour = Dictionary(tomorrow.map { ($0.hour, $0.score) }, uniquingKeysWith: { a, _ in a })
        let start = cal.dateInterval(of: .hour, for: now)?.start ?? now
        return (0..<36).compactMap { offset -> SnapHour? in
            guard let date = cal.date(byAdding: .hour, value: offset, to: start) else { return nil }
            let hour = cal.component(.hour, from: date)
            let scores = cal.isDate(date, inSameDayAs: now) ? todayByHour : tomorrowByHour
            guard let score = scores[hour] else { return nil }
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
