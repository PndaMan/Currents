import Foundation
import CoreLocation

/// Season estimates for the species guide and species pages.
///
/// Seasonality is driven by each species' own thermal tolerance band
/// (minTempC…optimalTempC…maxTempC) against a typical monthly surface water
/// temperature, flipped for the southern hemisphere. A wide-tolerance fish
/// stays catchable across more of the year, a stenothermal one peaks sharply,
/// and cold- or warm-water species map to the cold or warm months.
enum SpeciesSeason {
    /// Approximate monthly surface water temperatures in Celsius across a full
    /// temperate year (northern hemisphere). Index 1 = January. The range is
    /// deliberately wide (about 4 to 27 °C) so every species, cold-water,
    /// temperate and tropical alike, has a month where water reaches its band.
    private static let northernTemps: [Int: Double] = [
        1: 5, 2: 4, 3: 6, 4: 10, 5: 15, 6: 20,
        7: 24, 8: 27, 9: 23, 10: 18, 11: 12, 12: 7
    ]

    static let shortMonths: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortMonthSymbols
    }()

    static let fullMonths: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.standaloneMonthSymbols
    }()

    static var currentMonth: Int { Calendar.current.component(.month, from: .now) }

    /// The phone's last known latitude, read once. Nil without location
    /// permission or before the first fix.
    private static let lastKnownLatitude: Double? = CLLocationManager().location?.coordinate.latitude

    /// Whether the angler is in the southern hemisphere: from the last known
    /// location, falling back to the time zone.
    static var isSouthernHemisphere: Bool {
        if let latitude = lastKnownLatitude { return latitude < 0 }
        let tz = TimeZone.current.identifier.lowercased()
        let southern = ["australia", "auckland", "wellington", "buenos_aires",
                        "santiago", "johannesburg", "harare", "perth",
                        "sydney", "melbourne", "brasilia", "sao_paulo"]
        return southern.contains(where: { tz.contains($0) })
    }

    static var hemisphereName: String {
        isSouthernHemisphere ? "Southern hemisphere" : "Northern hemisphere"
    }

    /// Estimated surface water temperature for a month (1 to 12).
    static func waterTemp(for month: Int) -> Double {
        if isSouthernHemisphere {
            let flipped = ((month - 1 + 6) % 12) + 1
            return northernTemps[flipped] ?? 15
        }
        return northernTemps[month] ?? 15
    }

    /// The comfortable band edges for a species, falling back to a moderate
    /// spread around the optimum when explicit min/max aren't known.
    static func band(_ sp: Species) -> (lower: Double, optimal: Double, upper: Double)? {
        guard let optimal = sp.optimalTempC else { return nil }
        let lower = sp.minTempC ?? (optimal - 6)
        let upper = sp.maxTempC ?? (optimal + 6)
        return (min(lower, optimal), optimal, max(upper, optimal))
    }

    /// 0 to 100: peaks at the optimum and falls to 0 at the band edge
    /// (quadratic falloff for a smooth ramp).
    static func matchScore(_ sp: Species, month: Int) -> Int {
        guard let band = band(sp) else { return 0 }
        let temp = waterTemp(for: month)
        let span = max(band.upper - band.optimal, band.optimal - band.lower, 3)
        let norm = abs(temp - band.optimal) / span
        return Int(max(0, 100 * (1 - norm * norm)))
    }

    static func isInSeason(_ sp: Species, month: Int) -> Bool {
        guard let band = band(sp) else { return false }
        let temp = waterTemp(for: month)
        return temp >= band.lower && temp <= band.upper
    }

    /// Twelve monthly scores, January first.
    static func scores(_ sp: Species) -> [Int] {
        (1...12).map { matchScore(sp, month: $0) }
    }

    /// "Peak November to March", from the longest run of months scoring 80 or
    /// more, wrapping around the year. Nil when nothing peaks.
    static func peakText(_ scores: [Int]) -> String? {
        guard scores.count == 12 else { return nil }
        let peak = scores.map { $0 >= 80 }
        guard peak.contains(true) else { return nil }
        if !peak.contains(false) { return "Good all year" }
        // Start scanning just after a non-peak month so a wrapped run stays whole.
        let start = (peak.firstIndex(of: false) ?? 0) + 1
        var best: (start: Int, length: Int) = (0, 0)
        var runStart = -1, runLength = 0
        for step in 0..<12 {
            let i = (start + step) % 12
            if peak[i] {
                if runLength == 0 { runStart = i }
                runLength += 1
                if runLength > best.length { best = (runStart, runLength) }
            } else {
                runLength = 0
            }
        }
        let first = best.start, last = (best.start + best.length - 1) % 12
        if best.length == 1 { return "Peak in \(fullMonths[first])" }
        return "Peak \(fullMonths[first]) to \(fullMonths[last])"
    }

    static func habitatName(_ habitat: Species.Habitat?) -> String? {
        switch habitat {
        case .freshwater: "Freshwater"
        case .marine: "Saltwater"
        case .brackish: "Estuary"
        case nil: nil
        }
    }

    /// "18°C to 24°C" around the optimum (where it feeds best), or the
    /// tolerance band when there is no optimum.
    static func comfortText(_ sp: Species, imperial: Bool) -> String? {
        if let opt = sp.optimalTempC {
            return rangeText(opt - 3, opt + 3, imperial: imperial)
        }
        if let lo = sp.minTempC, let hi = sp.maxTempC {
            return rangeText(lo, hi, imperial: imperial)
        }
        return nil
    }

    static func rangeText(_ lo: Double, _ hi: Double, imperial: Bool) -> String {
        "\(Units.temperature(lo, imperial: imperial)) to \(Units.temperature(hi, imperial: imperial))"
    }
}
