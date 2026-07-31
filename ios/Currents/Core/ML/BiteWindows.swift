import Foundation

/// Turns the hour-by-hour bite scores into the two or three windows worth
/// planning your day around, rather than 24 numbers to read yourself.
enum BiteWindows {

    struct Window: Identifiable {
        let id = UUID()
        let startHour: Int
        /// Inclusive — a single-hour window has `endHour == startHour`.
        let endHour: Int
        let peakScore: Int

        func label(use24Hour: Bool) -> String {
            "\(Self.hour(startHour, use24Hour: use24Hour))–\(Self.hour(endHour + 1, use24Hour: use24Hour))"
        }

        /// True once the window has fully passed today.
        func hasPassed(now: Date = .now) -> Bool {
            Calendar.current.component(.hour, from: now) > endHour
        }

        func isNow(_ now: Date = .now) -> Bool {
            let h = Calendar.current.component(.hour, from: now)
            return h >= startHour && h <= endHour
        }

        private static func hour(_ h: Int, use24Hour: Bool) -> String {
            let hh = h % 24
            if use24Hour { return String(format: "%02d:00", hh) }
            let suffix = hh < 12 ? "AM" : "PM"
            var display = hh % 12
            if display == 0 { display = 12 }
            return "\(display) \(suffix)"
        }
    }

    /// The best contiguous stretches of the day. Windows are grouped runs of
    /// hours scoring near the day's peak, so a flat day yields one long window
    /// rather than three arbitrary ones.
    static func best(from hourly: [(hour: Int, score: Int)], limit: Int = 3) -> [Window] {
        guard !hourly.isEmpty else { return [] }
        let sorted = hourly.sorted { $0.hour < $1.hour }
        let peak = sorted.map(\.score).max() ?? 0
        // Near-peak, but never bother highlighting a genuinely dead day.
        let threshold = max(50, peak - 12)

        var windows: [Window] = []
        var runStart: Int?
        var runPeak = 0

        for point in sorted {
            if point.score >= threshold {
                if runStart == nil { runStart = point.hour; runPeak = point.score }
                runPeak = max(runPeak, point.score)
            } else if let s = runStart {
                windows.append(Window(startHour: s, endHour: point.hour - 1, peakScore: runPeak))
                runStart = nil; runPeak = 0
            }
        }
        if let s = runStart {
            windows.append(Window(startHour: s, endHour: sorted.last!.hour, peakScore: runPeak))
        }

        return windows
            .sorted { $0.peakScore > $1.peakScore }
            .prefix(limit)
            .sorted { $0.startHour < $1.startHour }
    }

    /// How to fish a window of this quality — the "tap a peak for advice"
    /// behaviour, kept honest rather than pretending to know the water.
    static func guidance(forScore score: Int) -> String {
        switch score {
        case 80...:
            return "Prime. Fish aggressively — cover water with reaction baits and expect them to chase."
        case 65..<80:
            return "Strong. Work your confidence areas thoroughly; a moving bait should get bitten."
        case 50..<65:
            return "Workable. Slow down and downsize — pick apart structure instead of covering water."
        default:
            return "Tough. Finesse presentations on the highest-percentage spots you know."
        }
    }
}
