import Foundation

/// Turns a logged catch history into plain-language takeaways ("most of your
/// fish come at dawn", "April is your best month"). Purely on-device.
struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

enum InsightsEngine {
    /// Produces a small ranked set of insights. Returns empty until there's
    /// enough history to say anything meaningful.
    static func compute(from catches: [CatchDetail]) -> [Insight] {
        guard catches.count >= 3 else { return [] }
        var out: [Insight] = []
        let cal = Calendar.current
        let total = catches.count

        // Best time-of-day window.
        let windows: [(name: String, range: String, test: (Int) -> Bool)] = [
            ("dawn", "4–8am", { (4..<8).contains($0) }),
            ("the morning", "8am–12pm", { (8..<12).contains($0) }),
            ("midday", "12–4pm", { (12..<16).contains($0) }),
            ("the evening", "4–8pm", { (16..<20).contains($0) }),
            ("after dark", "8pm–4am", { $0 >= 20 || $0 < 4 }),
        ]
        let hours = catches.map { cal.component(.hour, from: $0.catchRecord.caughtAt) }
        if let best = windows.map({ w in (w, hours.filter(w.test).count) }).max(by: { $0.1 < $1.1 }),
           best.1 > 0 {
            let pct = Int((Double(best.1) / Double(total)) * 100)
            if pct >= 30 {
                out.append(.init(icon: "sunrise.fill",
                                 text: "\(pct)% of your catches come in \(best.0.name) (\(best.0.range))."))
            }
        }

        // Best month.
        let months = Dictionary(grouping: catches, by: { cal.component(.month, from: $0.catchRecord.caughtAt) })
        if let best = months.max(by: { $0.value.count < $1.value.count }), best.value.count >= 2 {
            let name = cal.monthSymbols[best.key - 1]
            out.append(.init(icon: "calendar", text: "\(name) is your most productive month so far."))
        }

        // Top species.
        let species = Dictionary(grouping: catches.compactMap { $0.species?.commonName }, by: { $0 })
        if let top = species.max(by: { $0.value.count < $1.value.count }), top.value.count >= 2 {
            out.append(.init(icon: "fish.fill",
                             text: "\(top.key) is your most-caught species (\(top.value.count) landed)."))
        }

        // Most productive spot.
        let spots = Dictionary(grouping: catches.compactMap { $0.spot?.name }, by: { $0 })
        if let top = spots.max(by: { $0.value.count < $1.value.count }), top.value.count >= 2 {
            let pct = Int((Double(top.value.count) / Double(total)) * 100)
            out.append(.init(icon: "mappin.circle.fill",
                             text: "\(pct)% of your fish come from \(top.key)."))
        }

        // Bite-score read.
        let scores = catches.compactMap { $0.catchRecord.forecastScoreAtCapture }
        if scores.count >= 3 {
            let avg = scores.reduce(0, +) / scores.count
            let tail = avg >= 65 ? " — you read the conditions well." : "."
            out.append(.init(icon: "gauge.with.dots.needle.67percent",
                             text: "Your catches average a bite score of \(avg)/100\(tail)"))
        }

        // Best lure.
        let lures = catches.compactMap { $0.gearLoadout?.lure ?? $0.gearLoadout?.name }
        let lureGroups = Dictionary(grouping: lures, by: { $0 })
        if let top = lureGroups.max(by: { $0.value.count < $1.value.count }), top.value.count >= 3 {
            out.append(.init(icon: "scribble.variable",
                             text: "\(top.key) is your most effective lure (\(top.value.count) catches)."))
        }

        // Release rate.
        let released = catches.filter { $0.catchRecord.released }.count
        if released > 0 {
            let pct = Int((Double(released) / Double(total)) * 100)
            if pct >= 20 {
                out.append(.init(icon: "arrow.uturn.backward",
                                 text: "You release \(pct)% of your catches — nice conservation ethic."))
            }
        }

        return out
    }
}
