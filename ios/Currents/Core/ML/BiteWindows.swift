import Foundation
import CoreLocation

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

// MARK: - Days ahead

extension BiteWindows {
    /// A window on the clock, for planning alerts ahead of time.
    struct Upcoming: Sendable {
        let start: Date
        /// Exclusive: the top of the hour after the window's last hour.
        let end: Date
        let peakScore: Int
    }

    /// The windows for today and the following days at a place, worked out
    /// the way Today shows them. A window running past midnight joins the
    /// next day's first window, so it is one window, not two.
    static func upcoming(coordinate: CLLocationCoordinate2D,
                         current: WeatherService.WeatherData?,
                         outlook: [WeatherService.WeatherData],
                         species: Species?,
                         days: Int,
                         now: Date = .now) -> [Upcoming] {
        let cal = Calendar.current
        var all: [Upcoming] = []
        for offset in 0..<days {
            let day = ForecastEngine.day(offset, coordinate: coordinate, current: current,
                                         outlook: outlook, species: species, now: now)
            let dayStart = cal.startOfDay(for: day.date)
            for window in best(from: day.result.hourlyScores) {
                guard let start = cal.date(byAdding: .hour, value: window.startHour, to: dayStart),
                      let end = cal.date(byAdding: .hour, value: window.endHour + 1, to: dayStart)
                else { continue }
                if let last = all.last, last.end == start {
                    all[all.count - 1] = Upcoming(start: last.start, end: end,
                                                  peakScore: max(last.peakScore, window.peakScore))
                } else {
                    all.append(Upcoming(start: start, end: end, peakScore: window.peakScore))
                }
            }
        }
        return all
    }
}

extension ForecastEngine {
    /// One day's forecast as Today shows it: this moment with the live
    /// reading for today, noon with the outlook's day for later days. Today,
    /// the widget and the bite alerts all go through here so they agree. An
    /// offline estimate scores on its pressure alone.
    static func day(_ offset: Int,
                    coordinate: CLLocationCoordinate2D,
                    current: WeatherService.WeatherData?,
                    outlook: [WeatherService.WeatherData],
                    species: Species?,
                    now: Date = .now) -> (date: Date, weather: WeatherService.WeatherData?, result: ForecastResult) {
        let cal = Calendar.current
        let date: Date
        let weather: WeatherService.WeatherData?
        if offset == 0 {
            date = now
            weather = current ?? outlook.first
        } else {
            let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) ?? now
            date = start.addingTimeInterval(12 * 3600)
            weather = outlook.indices.contains(offset) ? outlook[offset] : nil
        }
        let result = forecast(
            date: date,
            coordinate: coordinate,
            currentPressureHpa: weather?.pressureHpa,
            pressureChange6h: weather?.pressureChange6h,
            waterTempC: weather?.measured?.waterTempC,
            windSpeedKmh: weather?.measured?.windSpeedKmh,
            windDirection: weather?.measured?.windDirectionDeg,
            species: species,
            isInSpawningZone: false
        )
        return (date, weather, result)
    }
}
