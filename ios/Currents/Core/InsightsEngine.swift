import Foundation

/// One headline pattern from the catch history, shown as a row on the Stats
/// page: "Best time", "Dawn, 42%".
struct Insight: Identifiable {
    enum Kind { case bestTime, bestLure }
    let kind: Kind
    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    /// The lure's name, for the row to lead with the lure's own art.
    var lure: String? = nil
    var id: Kind { kind }
}

/// Turns a logged catch history into headline patterns. Purely on-device.
/// Only patterns the Stats page does not already chart or list are made: the
/// best month, top species, top spot, average bite score and release rate
/// each have their own section there.
enum InsightsEngine {
    /// Dawn and dusk, counted the same in the Best time row and in the Best
    /// hours chart on the Stats page.
    static let dawnHours: Range<Int> = 4..<8
    static let duskHours: Range<Int> = 16..<20

    static func isDawnOrDusk(_ hour: Int) -> Bool {
        dawnHours.contains(hour) || duskHours.contains(hour)
    }

    /// Returns empty until there's enough history to say anything meaningful.
    static func compute(from catches: [CatchDetail], use24: Bool = ForecastFormat.use24) -> [Insight] {
        guard catches.count >= 3 else { return [] }
        var out: [Insight] = []
        let cal = Calendar.current
        let total = catches.count

        // Best time of day, as a share of every catch, in the 24-hour setting.
        func range(_ from: Int, _ to: Int) -> String {
            "\(ForecastFormat.hour(from, use24: use24)) to \(ForecastFormat.hour(to, use24: use24))"
        }
        let windows: [(name: String, from: Int, to: Int, icon: String, test: (Int) -> Bool)] = [
            ("Dawn", InsightsEngine.dawnHours.lowerBound, InsightsEngine.dawnHours.upperBound, "sunrise.fill",
             { InsightsEngine.dawnHours.contains($0) }),
            ("Morning", 8, 12, "sun.max.fill", { (8..<12).contains($0) }),
            ("Midday", 12, 16, "sun.max.fill", { (12..<16).contains($0) }),
            ("Evening", InsightsEngine.duskHours.lowerBound, InsightsEngine.duskHours.upperBound, "sunset.fill",
             { InsightsEngine.duskHours.contains($0) }),
            ("After dark", 20, 4, "moon.stars.fill", { $0 >= 20 || $0 < 4 }),
        ]
        let hours = catches.map { cal.component(.hour, from: $0.catchRecord.caughtAt) }
        if let best = windows.map({ w in (w, hours.filter(w.test).count) }).max(by: { $0.1 < $1.1 }),
           best.1 > 0 {
            let pct = Int((Double(best.1) / Double(total)) * 100)
            if pct >= 30 {
                out.append(Insight(kind: .bestTime, icon: best.0.icon, title: "Best time",
                                   value: "\(best.0.name), \(pct)%", detail: range(best.0.from, best.0.to)))
            }
        }

        // Best lure overall. The page's gear list counts loadouts, and its
        // lure list goes species by species.
        let lures = catches
            .compactMap { $0.gearLoadout?.lure ?? $0.gearLoadout?.name }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lureGroups = Dictionary(grouping: lures, by: { $0 })
        if let top = lureGroups.max(by: { $0.value.count < $1.value.count }), top.value.count >= 3 {
            out.append(Insight(kind: .bestLure, icon: OwnedGear.Category.lure.icon, title: "Best lure",
                               value: "\(top.value.count) catches", detail: top.key, lure: top.key))
        }

        return out
    }
}
