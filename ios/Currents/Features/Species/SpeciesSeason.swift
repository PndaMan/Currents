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

    /// The place the forecast is for, chosen as Today chooses it: the saved
    /// spot Today is set to, else the phone's location. Nil when neither is
    /// known. Read on every call, so a fix that arrives later counts.
    @MainActor
    static func forecastCoordinate(_ appState: AppState) -> CLLocationCoordinate2D? {
        let spotId = UserDefaults.standard.string(forKey: "todaySpotId") ?? ""
        if !spotId.isEmpty,
           let spot = ((try? appState.spotRepository.fetchAll()) ?? []).first(where: { $0.id == spotId }) {
            return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        }
        return appState.locationManager.currentLocation?.coordinate
    }

    /// Whether a place is south of the equator, falling back to the time
    /// zone when the latitude is not known.
    static func isSouthern(latitude: Double?) -> Bool {
        if let latitude { return latitude < 0 }
        let tz = TimeZone.current.identifier.lowercased()
        let southern = ["australia", "auckland", "wellington", "buenos_aires",
                        "santiago", "johannesburg", "harare", "perth",
                        "sydney", "melbourne", "brasilia", "sao_paulo"]
        return southern.contains(where: { tz.contains($0) })
    }

    /// Whether the forecast's place is south of the equator.
    @MainActor
    static func isSouthernHemisphere(_ appState: AppState) -> Bool {
        isSouthern(latitude: forecastCoordinate(appState)?.latitude)
    }

    static func hemisphereName(southern: Bool) -> String {
        southern ? "Southern hemisphere" : "Northern hemisphere"
    }

    /// Estimated surface water temperature for a month (1 to 12).
    static func waterTemp(for month: Int, southern: Bool) -> Double {
        if southern {
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
    static func matchScore(_ sp: Species, month: Int, southern: Bool) -> Int {
        guard let band = band(sp) else { return 0 }
        let temp = waterTemp(for: month, southern: southern)
        let span = max(band.upper - band.optimal, band.optimal - band.lower, 3)
        let norm = abs(temp - band.optimal) / span
        return Int(max(0, 100 * (1 - norm * norm)))
    }

    static func isInSeason(_ sp: Species, month: Int, southern: Bool) -> Bool {
        guard let band = band(sp) else { return false }
        let temp = waterTemp(for: month, southern: southern)
        return temp >= band.lower && temp <= band.upper
    }

    /// Twelve monthly scores, January first.
    static func scores(_ sp: Species, southern: Bool) -> [Int] {
        (1...12).map { matchScore(sp, month: $0, southern: southern) }
    }

    /// "Peak November to March", from the longest run of months scoring 80 or
    /// more, wrapping around the year. Nil when nothing peaks.
    static func peakText(_ scores: [Int]) -> String? {
        guard let run = peakRun(scores) else { return nil }
        if run.length == 12 { return "Good all year" }
        let first = run.start, last = (run.start + run.length - 1) % 12
        if run.length == 1 { return "Peak in \(fullMonths[first])" }
        return "Peak \(fullMonths[first]) to \(fullMonths[last])"
    }

    /// "Nov to Mar", the same peak in short month names, captioning the
    /// season bars on a species guide row. Nil when nothing peaks.
    static func shortPeakText(_ scores: [Int]) -> String? {
        guard let run = peakRun(scores) else { return nil }
        if run.length == 12 { return "All year" }
        let first = run.start, last = (run.start + run.length - 1) % 12
        if run.length == 1 { return shortMonths[first] }
        return "\(shortMonths[first]) to \(shortMonths[last])"
    }

    /// The longest run of months scoring 80 or more, wrapping around the
    /// year, as its first month (0 to 11) and its length. Nil when nothing
    /// peaks; a length of 12 means every month does.
    private static func peakRun(_ scores: [Int]) -> (start: Int, length: Int)? {
        guard scores.count == 12 else { return nil }
        let peak = scores.map { $0 >= 80 }
        guard peak.contains(true) else { return nil }
        if !peak.contains(false) { return (0, 12) }
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
        return best
    }

    static func habitatName(_ habitat: Species.Habitat?) -> String? {
        switch habitat {
        case .freshwater: "Freshwater"
        case .marine: "Saltwater"
        case .brackish: "Estuary"
        case nil: nil
        }
    }

    /// The stand-in bands (min, optimum, max in Celsius) the seed gives
    /// species with no recorded temperatures: about 600 hold 8, 20, 28 and
    /// about 140 hold 8, 18, 28.
    private static let placeholderBands: [(Double, Double, Double)] = [(8, 20, 28), (8, 18, 28)]

    /// True when the record holds one of the seed's stand-in bands rather
    /// than temperatures recorded for the species, so no range is shown.
    static func hasPlaceholderTemps(_ sp: Species) -> Bool {
        guard let lo = sp.minTempC, let opt = sp.optimalTempC, let hi = sp.maxTempC else { return false }
        return placeholderBands.contains { $0.0 == lo && $0.1 == opt && $0.2 == hi }
    }

    /// "18°C to 24°C", the band the species feeds best in, worked out as
    /// Today works it out (`ConditionText.comfort`). Nil when the record has
    /// no temperatures of its own.
    @MainActor
    static func comfortText(_ sp: Species, imperial: Bool) -> String? {
        guard !hasPlaceholderTemps(sp) else { return nil }
        if sp.optimalTempC == nil {
            guard let lo = sp.minTempC, let hi = sp.maxTempC, hi > lo else { return nil }
        }
        let band = ConditionText.comfort(for: sp)
        return rangeText(band.lowerBound, band.upperBound, imperial: imperial)
    }

    static func rangeText(_ lo: Double, _ hi: Double, imperial: Bool) -> String {
        "\(Units.temperature(lo, imperial: imperial)) to \(Units.temperature(hi, imperial: imperial))"
    }
}
