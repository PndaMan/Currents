import Foundation
import CoreLocation

/// A year of estimated surface water temperatures for one place, January
/// first, in Celsius. Built by `SpeciesSeason.waterYear`.
struct WaterYear: Equatable {
    let southern: Bool
    /// Twelve monthly estimates, January first.
    let months: [Double]

    /// The estimate for a month, 1 to 12.
    func temp(_ month: Int) -> Double {
        months.indices.contains(month - 1) ? months[month - 1] : 15
    }
}

/// Season estimates for the species guide and species pages.
///
/// Seasonality is driven by each species' own thermal tolerance band
/// (minTempC…optimalTempC…maxTempC) against the estimated monthly surface
/// water at the place the forecast is for. A wide-tolerance fish stays
/// catchable across more of the year, a stenothermal one peaks sharply, and
/// cold- or warm-water species map to the cold or warm months.
enum SpeciesSeason {
    /// Annual mean surface water by absolute latitude, in Celsius: the zonal
    /// mean sea surface temperature from the NOAA World Ocean Atlas 2018
    /// annual surface climatology, rounded to the half degree. Warm and flat
    /// through the tropics, falling fast across the mid latitudes.
    private static let annualMean: [(latitude: Double, celsius: Double)] = [
        (0, 27), (10, 27.5), (20, 25.5), (30, 22), (40, 16.5), (50, 10), (60, 5), (70, 1.5), (90, 0)
    ]

    /// Half the annual swing by absolute latitude, in Celsius. The open
    /// ocean swings about 1 °C either way in the tropics and 3 to 5 °C at
    /// mid latitudes (same climatology); lakes, dams and shallow coasts swing
    /// two to three times that. The guide covers both, so these sit between
    /// them, and `waterYear` levels the curve to the place's own reading.
    private static let halfRange: [(latitude: Double, celsius: Double)] = [
        (0, 1), (10, 1.5), (20, 3), (30, 4.5), (40, 6), (50, 7), (60, 7), (90, 4)
    ]

    /// Surface water peaks in late summer, a month or so after the air:
    /// mid August in the north, mid February in the south.
    private static let peakMonth = (north: 8.0, south: 2.0)

    /// A latitude when the place is not known: a temperate 35 degrees.
    private static let defaultLatitude = 35.0

    /// The month score at and above which a fish counts as in season. The
    /// season bars draw these months filled, so the tag and the bars agree.
    static let inSeasonScore = 40

    /// The month score that counts as the peak of the season.
    private static let peakScore = 80

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
    /// spot Today is set to, else the phone's location, else Today's fallback
    /// place, so the water matches Today with location off. Read on every
    /// call, so a fix that arrives later counts.
    @MainActor
    static func forecastCoordinate(_ appState: AppState) -> CLLocationCoordinate2D {
        let spotId = UserDefaults.standard.string(forKey: "todaySpotId") ?? ""
        if !spotId.isEmpty,
           let spot = ((try? appState.spotRepository.fetchAll()) ?? []).first(where: { $0.id == spotId }) {
            return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        }
        return appState.locationManager.currentLocation?.coordinate ?? ForecastStore.fallbackCoordinate
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

    static func hemisphereName(southern: Bool) -> String {
        southern ? "Southern hemisphere" : "Northern hemisphere"
    }

    // MARK: - Water

    /// The water year for the place Today forecasts for. When the phone has
    /// saved weather there, the curve is levelled so this month reads the
    /// water temperature Today shows. Reads only what is saved on the phone;
    /// it never goes to the network.
    @MainActor
    static func waterYear(_ appState: AppState) async -> WaterYear {
        let place = forecastCoordinate(appState)
        let saved = await WeatherService.shared.saved(for: place)
        // Today's weather is the current reading, else the first outlook
        // day. An offline estimate carries no water reading, as on Today.
        let today = saved.current ?? saved.days.first
        return waterYear(latitude: place.latitude, current: today?.measured?.waterTempC)
    }

    /// The latitude curve: an annual mean and half swing for the latitude,
    /// peaking in late summer for the hemisphere. With `current`, the whole
    /// curve shifts so `month` reads that temperature. Never below 0 °C.
    /// With no latitude, a temperate curve in the time zone's hemisphere.
    static func waterYear(latitude: Double?, current: Double? = nil,
                          month: Int = SpeciesSeason.currentMonth) -> WaterYear {
        let southern = isSouthern(latitude: latitude)
        let lat = min(abs(latitude ?? defaultLatitude), 90)
        let mean = interpolate(annualMean, at: lat)
        let swing = interpolate(halfRange, at: lat)
        let peak = southern ? peakMonth.south : peakMonth.north
        let base = (1...12).map { m in
            max(0, mean + swing * cos(2 * Double.pi * (Double(m) - peak) / 12))
        }
        guard let current, base.indices.contains(month - 1) else {
            return WaterYear(southern: southern, months: base)
        }
        let shift = current - base[month - 1]
        return WaterYear(southern: southern, months: base.map { max(0, $0 + shift) })
    }

    /// Straight-line reading of a latitude table, clamped to its ends.
    private static func interpolate(_ table: [(latitude: Double, celsius: Double)], at latitude: Double) -> Double {
        guard let first = table.first, let last = table.last else { return 15 }
        if latitude <= first.latitude { return first.celsius }
        for (a, b) in zip(table, table.dropFirst()) where latitude <= b.latitude {
            let t = (latitude - a.latitude) / max(b.latitude - a.latitude, 0.001)
            return a.celsius + (b.celsius - a.celsius) * t
        }
        return last.celsius
    }

    // MARK: - Season

    /// The comfortable band edges for a species, falling back to a moderate
    /// spread around the optimum when explicit min/max aren't known.
    static func band(_ sp: Species) -> (lower: Double, optimal: Double, upper: Double)? {
        guard let optimal = sp.optimalTempC else { return nil }
        let lower = sp.minTempC ?? (optimal - 6)
        let upper = sp.maxTempC ?? (optimal + 6)
        return (min(lower, optimal), optimal, max(upper, optimal))
    }

    /// True when the record holds temperatures of its own, so a season can
    /// be worked out. The seed's stand-in bands and records with no optimum
    /// have none.
    static func knowsSeason(_ sp: Species) -> Bool {
        band(sp) != nil && !hasPlaceholderTemps(sp)
    }

    /// 0 to 100: peaks at the optimum and falls to 0 at the band edge
    /// (quadratic falloff for a smooth ramp).
    static func matchScore(_ sp: Species, month: Int, water: WaterYear) -> Int {
        guard let band = band(sp) else { return 0 }
        let temp = water.temp(month)
        let span = max(band.upper - band.optimal, band.optimal - band.lower, 3)
        let norm = abs(temp - band.optimal) / span
        return Int(max(0, 100 * (1 - norm * norm)))
    }

    /// In season when the month scores `inSeasonScore` or more, the months
    /// the season bars draw filled. Never for a record with no season.
    static func isInSeason(_ sp: Species, month: Int, water: WaterYear) -> Bool {
        knowsSeason(sp) && matchScore(sp, month: month, water: water) >= inSeasonScore
    }

    /// Twelve monthly scores, January first. Empty for a record with no
    /// season of its own, so no bars are drawn from a stand-in band.
    static func scores(_ sp: Species, water: WaterYear) -> [Int] {
        guard knowsSeason(sp) else { return [] }
        return (1...12).map { matchScore(sp, month: $0, water: water) }
    }

    /// "Peak November to March": the run of months scoring 80 or more that
    /// holds `month` (1 to 12), else the run holding the year's best score.
    /// Two runs are both named ("Peak March to July and September to
    /// January"), and nine or more months say "Good most of the year, slower
    /// in February and August". Nil when nothing peaks.
    static func peakText(_ scores: [Int], month: Int? = nil) -> String? {
        let runs = peakRuns(scores)
        guard !runs.isEmpty else { return nil }
        let peakMonths = runs.reduce(0) { $0 + $1.length }
        if peakMonths == 12 { return "Good all year" }
        if peakMonths >= 9 {
            let slow = (0..<12).filter { scores[$0] < peakScore }.map { fullMonths[$0] }
            return "Good most of the year, slower in \(andList(slow))"
        }
        if runs.count == 2 {
            let named = runs.sorted { $0.start < $1.start }.map { runName($0) }
            return "Peak " + named.joined(separator: " and ")
        }
        guard let run = peakRun(scores, month: month) else { return nil }
        if run.length == 1 { return "Peak in \(fullMonths[run.start])" }
        return "Peak \(runName(run))"
    }

    /// "March" for one month, "November to March" for a run.
    private static func runName(_ run: (start: Int, length: Int)) -> String {
        let first = run.start, last = (run.start + run.length - 1) % 12
        return run.length == 1 ? fullMonths[first] : "\(fullMonths[first]) to \(fullMonths[last])"
    }

    /// "February", "February and August", "February, March and August".
    private static func andList(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// "Nov to Mar", the same peak in short month names, captioning the
    /// season bars on a species guide row. Nil when nothing peaks.
    static func shortPeakText(_ scores: [Int], month: Int? = nil) -> String? {
        guard let run = peakRun(scores, month: month) else { return nil }
        if run.length == 12 { return "All year" }
        let first = run.start, last = (run.start + run.length - 1) % 12
        if run.length == 1 { return shortMonths[first] }
        return "\(shortMonths[first]) to \(shortMonths[last])"
    }

    /// The peak to name: the run holding `month` when there is one, else the
    /// run holding the highest score, the longer on a tie. As its first month
    /// (0 to 11) and its length; a length of 12 means every month peaks.
    private static func peakRun(_ scores: [Int], month: Int?) -> (start: Int, length: Int)? {
        let runs = peakRuns(scores)
        if let month, let run = runs.first(where: { (month - 1 - $0.start + 12) % 12 < $0.length }) {
            return run
        }
        return runs.max { a, b in
            let bestA = best(a, scores), bestB = best(b, scores)
            return bestA != bestB ? bestA < bestB : a.length < b.length
        }
    }

    /// Every run of months scoring 80 or more, wrapping around the year.
    private static func peakRuns(_ scores: [Int]) -> [(start: Int, length: Int)] {
        guard scores.count == 12 else { return [] }
        let peak = scores.map { $0 >= peakScore }
        guard peak.contains(true) else { return [] }
        // Start scanning just after a non-peak month so a wrapped run stays whole.
        guard let gap = peak.firstIndex(of: false) else { return [(0, 12)] }
        var runs: [(start: Int, length: Int)] = []
        var runStart = 0, runLength = 0
        for step in 1...12 {
            let i = (gap + step) % 12
            if peak[i] {
                if runLength == 0 { runStart = i }
                runLength += 1
            } else if runLength > 0 {
                runs.append((runStart, runLength))
                runLength = 0
            }
        }
        return runs
    }

    /// The highest score inside a run.
    private static func best(_ run: (start: Int, length: Int), _ scores: [Int]) -> Int {
        (0..<run.length).map { scores[(run.start + $0) % 12] }.max() ?? 0
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
