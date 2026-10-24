import Foundation
import CoreLocation

/// On-device bite forecast scoring engine.
///
/// Combines barometric pressure, solunar theory, tides, temperature,
/// wind, time-of-day, and seasonal patterns into a 0-100 score.
///
/// Design principles:
/// 1. Factors with no data are excluded from scoring, not defaulted
///    to an arbitrary midpoint. This prevents all scores from clustering
///    around 55-65.
/// 2. A nonlinear stretch (power curve) is applied after the raw
///    weighted sum so the output uses the full 0-100 range.
/// 3. Negative factors (strong wind, wrong temp, rising pressure) can
///    drag the score below 30; positive factors (dropping pressure +
///    major solunar + golden hour) can push it above 85.
struct ForecastEngine {

    struct ForecastResult: Sendable {
        let score: Int // 0-100
        let reasons: [String]
        let breakdown: ScoreBreakdown
        let bestHours: [Int]
        let hourlyScores: [(hour: Int, score: Int)]
        let feedingWindows: [SolunarEngine.FeedingWindow]
        let dayRating: SolunarEngine.DayRating
    }

    struct ScoreBreakdown: Sendable {
        let pressure: Double
        let pressureTrend: Double
        let tide: Double
        let moon: Double
        let temperature: Double
        let season: Double
        let timeOfDay: Double
        let wind: Double
        let solunar: Double
        /// Points each factor could add, out of 100, once the share of any
        /// factor without data has gone to the others. Zero means not counted.
        let weights: FactorWeights
    }

    struct FactorWeights: Sendable {
        let pressure: Double
        let pressureTrend: Double
        let tide: Double
        let moon: Double
        let temperature: Double
        let season: Double
        let timeOfDay: Double
        let wind: Double
        let solunar: Double
    }

    // MARK: - Species traits

    /// What a targeted species changes beyond its temperature range, read
    /// from its record. With no target, or a record too thin to trust, every
    /// factor keeps its general weight, so the untargeted score never moves.
    struct SpeciesTraits: Sendable, Equatable {
        enum Tide: Sendable, Equatable {
            /// General weight: nothing targeted, or the habitat is not known.
            case general
            /// Saltwater and estuary fish: moving water brings their food.
            case heavier
            /// Freshwater fish never see a tide, so it is left out.
            case ignored
        }

        let tide: Tide
        /// Catfish, eels and burbot do most of their feeding after dark.
        let feedsAtNight: Bool

        static let untargeted = SpeciesTraits(tide: .general, feedsAtNight: false)

        /// Catfish, freshwater eel and burbot families.
        static let nightFeedingFamilies: Set<String> = [
            "Ictaluridae", "Siluridae", "Clariidae", "Ariidae", "Pimelodidae",
            "Anguillidae", "Lotidae",
        ]

        init(tide: Tide, feedsAtNight: Bool) {
            self.tide = tide
            self.feedsAtNight = feedsAtNight
        }

        init(_ species: Species?) {
            guard let species else {
                self = .untargeted
                return
            }
            switch species.habitat {
            case .marine, .brackish:
                tide = .heavier
            case .freshwater where species.family != nil:
                // The seed marks every species without a curated record as
                // freshwater (reef fish included), so only trust it when the
                // record is curated, which is when the family is known.
                tide = .ignored
            default:
                tide = .general
            }
            feedsAtNight = species.family.map { Self.nightFeedingFamilies.contains($0) } ?? false
        }
    }

    // MARK: - Full forecast with per-hour breakdown

    static func forecast(
        date: Date = .now,
        coordinate: CLLocationCoordinate2D,
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        waterTempC: Double?,
        windSpeedKmh: Double?,
        windDirection: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> ForecastResult {
        let solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
        let tide = TideEngine.predict(date: date, coordinate: coordinate)

        let currentResult = computeInstant(
            date: date,
            solunar: solunar,
            tidePhase: tide.currentPhase,
            currentPressureHpa: currentPressureHpa,
            pressureChange6h: pressureChange6h,
            waterTempC: waterTempC,
            windSpeedKmh: windSpeedKmh,
            species: species,
            isInSpawningZone: isInSpawningZone
        )

        // Compute each hour individually so the solunar/time-of-day
        // component actually varies across the day.
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let hourlyScores: [(hour: Int, score: Int)] = (0..<24).map { hour in
            let hourDate = dayStart.addingTimeInterval(Double(hour) * 3600 + 1800)
            let hourResult = computeInstant(
                date: hourDate,
                solunar: solunar,
                tidePhase: tidePhaseForHour(hour, tide: tide),
                currentPressureHpa: currentPressureHpa,
                pressureChange6h: pressureChange6h,
                waterTempC: waterTempC,
                windSpeedKmh: windSpeedKmh,
                species: species,
                isInSpawningZone: isInSpawningZone
            )
            return (hour: hour, score: hourResult.score)
        }

        let bestHours = hourlyScores
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map(\.hour)
            .sorted()

        let windows = solunar.majorPeriods + solunar.minorPeriods

        return ForecastResult(
            score: currentResult.score,
            reasons: currentResult.reasons,
            breakdown: currentResult.breakdown,
            bestHours: bestHours,
            hourlyScores: hourlyScores,
            feedingWindows: windows,
            dayRating: solunar.dayRating
        )
    }

    /// Compute a score for a specific hour — exposed so the hourly
    /// drill-down can call it directly.
    static func forecastForHour(
        hour: Int,
        date: Date,
        coordinate: CLLocationCoordinate2D,
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        waterTempC: Double?,
        windSpeedKmh: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> ForecastResult {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let hourDate = dayStart.addingTimeInterval(Double(hour) * 3600 + 1800)

        let solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
        let tide = TideEngine.predict(date: date, coordinate: coordinate)

        let result = computeInstant(
            date: hourDate,
            solunar: solunar,
            tidePhase: tidePhaseForHour(hour, tide: tide),
            currentPressureHpa: currentPressureHpa,
            pressureChange6h: pressureChange6h,
            waterTempC: waterTempC,
            windSpeedKmh: windSpeedKmh,
            species: species,
            isInSpawningZone: isInSpawningZone
        )

        return ForecastResult(
            score: result.score,
            reasons: result.reasons,
            breakdown: result.breakdown,
            bestHours: [],
            hourlyScores: [],
            feedingWindows: solunar.majorPeriods + solunar.minorPeriods,
            dayRating: solunar.dayRating
        )
    }

    /// Legacy API (no location data).
    static func compute(
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        tidePhase: TidePhase?,
        moonPhase: MoonPhase,
        waterTempC: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> ForecastResult {
        // Build a minimal solunar stub for the legacy path
        let solunar = SolunarEngine.SolunarDay(
            date: .now,
            sunrise: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: .now)!,
            sunset: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!,
            dawnGoldenHour: Date.distantPast...Date.distantPast,
            duskGoldenHour: Date.distantFuture...Date.distantFuture,
            moonrise: nil,
            moonset: nil,
            majorPeriods: [],
            minorPeriods: [],
            moonPhase: moonPhase,
            moonIllumination: 0.5,
            dayRating: .fair
        )
        let result = computeInstant(
            date: .now,
            solunar: solunar,
            tidePhase: tidePhase ?? .moving,
            currentPressureHpa: currentPressureHpa,
            pressureChange6h: pressureChange6h,
            waterTempC: waterTempC,
            windSpeedKmh: nil,
            species: species,
            isInSpawningZone: isInSpawningZone
        )
        return ForecastResult(
            score: result.score,
            reasons: result.reasons,
            breakdown: result.breakdown,
            bestHours: [],
            hourlyScores: [],
            feedingWindows: [],
            dayRating: .fair
        )
    }

    // MARK: - Core scoring

    private struct InstantResult {
        let score: Int
        let reasons: [String]
        let breakdown: ScoreBreakdown
    }

    private static func computeInstant(
        date: Date,
        solunar: SolunarEngine.SolunarDay,
        tidePhase: TidePhase,
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        waterTempC: Double?,
        windSpeedKmh: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> InstantResult {
        var reasons: [String] = []
        let traits = SpeciesTraits(species)

        // Each factor returns (score: 0-1, weight, hasData: Bool).
        // Factors without data get weight 0; their weight is redistributed
        // to the factors that do have data.

        // === Pressure ===
        let wPressure: Double
        let havePressure: Bool
        if let p = currentPressureHpa {
            havePressure = true
            // Sweet spot is 1018-1028 (the stable-high range fish love).
            // Below 1010 or above 1035 is bad.
            if p >= 1018 && p <= 1028 {
                wPressure = 1.0
                reasons.append("Pressure is ideal at \(Units.pressure(hpa: p))")
            } else if p >= 1013 && p < 1018 {
                wPressure = 0.65
            } else if p > 1028 && p <= 1035 {
                wPressure = 0.55
                reasons.append("High pressure at \(Units.pressure(hpa: p)) can push fish deep")
            } else if p >= 1005 && p < 1013 {
                wPressure = 0.3
                reasons.append("Low pressure at \(Units.pressure(hpa: p))")
            } else if p > 1035 {
                wPressure = 0.2
                reasons.append("Very high pressure at \(Units.pressure(hpa: p)) slows the bite")
            } else {
                wPressure = 0.1
                reasons.append("Storm-level pressure at \(Units.pressure(hpa: p))")
            }
        } else {
            havePressure = false
            wPressure = 0.5
        }

        // === Pressure Trend ===
        // Falling pressure is THE strongest predictor of a hot bite.
        // Stable is mediocre. Rising is bad.
        let wPressureTrend: Double
        let havePressureTrend: Bool
        if let delta = pressureChange6h {
            havePressureTrend = true
            if delta < -6 {
                wPressureTrend = 1.0
                reasons.append("Pressure is crashing, so fish feed hard")
            } else if delta < -3 {
                wPressureTrend = 0.9
                reasons.append("Dropping pressure gets fish feeding")
            } else if delta < -1 {
                wPressureTrend = 0.7
                reasons.append("Falling pressure keeps fish active")
            } else if delta >= -1 && delta <= 1 {
                wPressureTrend = 0.3
                // Stable = below average, not above
            } else if delta > 1 && delta <= 3 {
                wPressureTrend = 0.15
                reasons.append("Rising pressure is shutting the bite down")
            } else {
                wPressureTrend = 0.05
                reasons.append("Pressure is spiking and fish go quiet")
            }
        } else {
            havePressureTrend = false
            wPressureTrend = 0.3
        }

        // === Tide ===
        // Left out entirely for a targeted freshwater species.
        let countsTide = traits.tide != .ignored
        let wTide: Double
        switch tidePhase {
        case .nearHighOrLow:
            wTide = 1.0
            if countsTide { reasons.append("Tide change brings peak feeding") }
        case .moving:
            wTide = 0.55
        case .slack:
            wTide = 0.1
            if countsTide { reasons.append("Slack tide means dead water") }
        }

        // === Moon Phase ===
        let wMoon: Double
        switch solunar.moonPhase {
        case .new, .full:
            wMoon = 1.0
            reasons.append("\(solunar.moonPhase.displayName) gives the strongest pull")
        case .waxingGibbous, .waningGibbous:
            wMoon = 0.65
        case .waxingCrescent, .waningCrescent:
            wMoon = 0.4
        case .firstQuarter, .lastQuarter:
            wMoon = 0.2
            reasons.append("Quarter moon gives the weakest pull")
        }

        // === Solunar Feeding Window ===
        // Major = moon overhead/underfoot. Best 4-5 hours of the day.
        // Outside any window should score LOW — that's the default state.
        let wSolunar: Double
        let inMajor = solunar.majorPeriods.contains { date >= $0.start && date <= $0.end }
        let inMinor = solunar.minorPeriods.contains { date >= $0.start && date <= $0.end }
        let nearMajor = solunar.majorPeriods.contains { abs(date.timeIntervalSince($0.peak)) < 5400 }
        if inMajor {
            wSolunar = 1.0
            reasons.append("Inside a major solunar period")
        } else if inMinor {
            wSolunar = 0.7
            reasons.append("Inside a minor solunar period")
        } else if nearMajor {
            wSolunar = 0.4
        } else {
            wSolunar = 0.1 // Most of the day, fish aren't in a feeding window
        }

        // === Time of Day ===
        // Dawn and dusk are dramatically better than midday.
        let wTimeOfDay: Double
        if solunar.dawnGoldenHour.contains(date) {
            wTimeOfDay = 1.0
            reasons.append("Dawn golden hour brings fish up")
        } else if solunar.duskGoldenHour.contains(date) {
            wTimeOfDay = 0.95
            reasons.append("Dusk golden hour starts the evening bite")
        } else {
            let isNight = date < solunar.sunrise.addingTimeInterval(-1800) ||
                          date > solunar.sunset.addingTimeInterval(1800)
            if isNight && traits.feedsAtNight {
                wTimeOfDay = 0.8
                if let species { reasons.append("After dark is feeding time for \(species.commonName)") }
            } else if isNight {
                wTimeOfDay = 0.15
            } else {
                // Daytime but not golden hour — score varies.
                // Early morning (just after golden) and late afternoon are decent.
                // Midday is poor.
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: date)
                switch hour {
                case 7...8:   wTimeOfDay = 0.65  // post-dawn
                case 9:       wTimeOfDay = 0.45
                case 10...14: wTimeOfDay = 0.2   // midday slump
                    reasons.append("Midday sun keeps fish deep and slow")
                case 15:      wTimeOfDay = 0.35
                case 16...17: wTimeOfDay = 0.55  // pre-dusk buildup
                default:      wTimeOfDay = 0.3
                }
            }
        }

        // === Wind ===
        let wWind: Double
        let haveWind: Bool
        if let wind = windSpeedKmh {
            haveWind = true
            switch wind {
            case 0..<3:
                wWind = 0.25
                reasons.append("Dead calm makes fish line-shy")
            case 3..<8:
                wWind = 0.7
                reasons.append("A light breeze puts a slight chop on the water")
            case 8..<20:
                wWind = 1.0
                reasons.append("A moderate wind gives an ideal chop")
            case 20..<30:
                wWind = 0.5
                reasons.append("Windy, so fish the wind-blown bank")
            case 30..<45:
                wWind = 0.2
                reasons.append("Strong wind at \(Units.speed(kmh: wind)) makes casting hard")
            default:
                wWind = 0.05
                reasons.append("Gale-force wind at \(Units.speed(kmh: wind)) is dangerous")
            }
        } else {
            haveWind = false
            wWind = 0.5
        }

        // === Temperature ===
        let wTemp: Double
        let haveTemp: Bool
        if let temp = waterTempC, let species, let optimal = species.optimalTempC {
            haveTemp = true
            let range = (species.maxTempC ?? optimal + 8) - optimal
            let diff = abs(temp - optimal)
            // Gaussian drop-off: within range = great, 2× range = terrible
            wTemp = exp(-(diff * diff) / (2.0 * range * range))
            if diff <= range * 0.5 {
                reasons.append("Water at \(Units.temperature(temp)) is ideal for \(species.commonName)")
            } else if diff <= range {
                reasons.append("Water at \(Units.temperature(temp)) is marginal for \(species.commonName)")
            } else {
                reasons.append("Water at \(Units.temperature(temp)) is outside the comfort range for \(species.commonName)")
            }
        } else if let temp = waterTempC {
            haveTemp = true
            // No species selected — use a general freshwater heuristic.
            // 15-25°C is the universal sweet spot for most gamefish.
            if temp >= 15 && temp <= 25 {
                wTemp = 0.85
            } else if temp >= 10 && temp < 15 {
                wTemp = 0.5
                reasons.append("Cool water at \(Units.temperature(temp)) slows fish down")
            } else if temp > 25 && temp <= 30 {
                wTemp = 0.55
                reasons.append("Warm water at \(Units.temperature(temp)) sends fish deep")
            } else if temp > 30 {
                wTemp = 0.2
                reasons.append("Water at \(Units.temperature(temp)) is too warm and low in oxygen")
            } else {
                wTemp = 0.25
                reasons.append("Cold water at \(Units.temperature(temp)) makes fish sluggish")
            }
        } else {
            haveTemp = false
            wTemp = 0.5
        }

        // === Spawning Season ===
        let wSeason: Double
        if isInSpawningZone {
            wSeason = 1.0
            reasons.append("Spawning fish here are aggressive and territorial")
        } else {
            wSeason = 0.3
        }

        // === Dynamic weighting ===
        // Base weights for all factors. Factors without real data
        // have their weight redistributed to factors that do.
        struct Factor {
            let value: Double
            let baseWeight: Double
            let hasData: Bool
        }
        let factors: [Factor] = [
            Factor(value: wPressure,      baseWeight: 10, hasData: havePressure),
            Factor(value: wPressureTrend, baseWeight: 18, hasData: havePressureTrend),
            Factor(value: wTide,          baseWeight: traits.tide == .heavier ? 18 : 12, hasData: countsTide),
            Factor(value: wMoon,          baseWeight: 8,  hasData: true),
            Factor(value: wSolunar,       baseWeight: 18, hasData: true),
            Factor(value: wTimeOfDay,     baseWeight: 16, hasData: true),
            Factor(value: wWind,          baseWeight: 8,  hasData: haveWind),
            Factor(value: wTemp,          baseWeight: 6,  hasData: haveTemp),
            Factor(value: wSeason,        baseWeight: 4,  hasData: true),
        ]

        // Weights are scaled to add up to 100, so a heavier tide takes its
        // share from the others. Untargeted, the base weights already add up
        // to 100 and the scale is unchanged.
        let availableWeight = factors.filter(\.hasData).reduce(0.0) { $0 + $1.baseWeight }
        let scale = availableWeight > 0 ? 100 / availableWeight : 1.0
        // Same order as `factors`.
        let effective = factors.map { $0.hasData ? $0.baseWeight * scale : 0 }

        var rawSum = 0.0
        for (f, w) in zip(factors, effective) {
            rawSum += f.value * w
        }
        // rawSum is in 0...100 but clusters around 40-60 in practice.
        // Apply a power-curve stretch: x^0.85 * 1.1 (boosts highs,
        // preserves lows, widens the spread).
        let normalized = rawSum / 100.0 // 0-1
        let stretched = pow(normalized, 0.8) * 1.15
        let score = min(100, max(0, Int(stretched * 100)))

        if reasons.isEmpty {
            reasons.append("Average conditions, still worth a cast")
        }

        return InstantResult(
            score: score,
            reasons: reasons,
            breakdown: ScoreBreakdown(
                pressure: wPressure,
                pressureTrend: wPressureTrend,
                tide: wTide,
                moon: wMoon,
                temperature: wTemp,
                season: wSeason,
                timeOfDay: wTimeOfDay,
                wind: wWind,
                solunar: wSolunar,
                weights: FactorWeights(
                    pressure: effective[0],
                    pressureTrend: effective[1],
                    tide: effective[2],
                    moon: effective[3],
                    temperature: effective[7],
                    season: effective[8],
                    timeOfDay: effective[5],
                    wind: effective[6],
                    solunar: effective[4]
                )
            )
        )
    }

    // MARK: - Tide phase for a given hour

    private static func tidePhaseForHour(_ hour: Int, tide: TideEngine.TideDay) -> TidePhase {
        // Check if this hour is near a high/low tide event
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: tide.points.first?.time ?? .now)
        let hourDate = dayStart.addingTimeInterval(Double(hour) * 3600 + 1800)

        let allEvents = tide.highTides + tide.lowTides
        for event in allEvents {
            let dist = abs(hourDate.timeIntervalSince(event.time))
            if dist < 3600 { return .nearHighOrLow }
        }

        // Check if between high/low (moving) or at peak/trough (slack)
        // Simple heuristic: middle third of interval between events = slack
        let sorted = allEvents.sorted { $0.time < $1.time }
        for i in 0..<sorted.count - 1 {
            let start = sorted[i].time
            let end = sorted[i + 1].time
            let interval = end.timeIntervalSince(start)
            let elapsed = hourDate.timeIntervalSince(start)
            if elapsed >= 0 && elapsed <= interval {
                let frac = elapsed / interval
                if frac > 0.4 && frac < 0.6 {
                    return .slack
                }
                return .moving
            }
        }
        return .moving
    }
}

// MARK: - Supporting Types

enum TidePhase: Sendable {
    case nearHighOrLow
    case moving
    case slack
}

enum MoonPhase: Int, Sendable, CaseIterable {
    case new = 0
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case full
    case waningGibbous
    case lastQuarter
    case waningCrescent

    var displayName: String {
        switch self {
        case .new: "New moon"
        case .waxingCrescent: "Waxing crescent"
        case .firstQuarter: "First quarter"
        case .waxingGibbous: "Waxing gibbous"
        case .full: "Full moon"
        case .waningGibbous: "Waning gibbous"
        case .lastQuarter: "Last quarter"
        case .waningCrescent: "Waning crescent"
        }
    }

    var symbolName: String {
        switch self {
        case .new: "moon.new"
        case .waxingCrescent: "moon.waxing.crescent"
        case .firstQuarter: "moon.first.quarter"
        case .waxingGibbous: "moon.waxing.gibbous"
        case .full: "moon.full"
        case .waningGibbous: "moon.waning.gibbous"
        case .lastQuarter: "moon.last.quarter"
        case .waningCrescent: "moon.waning.crescent"
        }
    }

    static func current(for date: Date = .now) -> MoonPhase {
        let knownNew = Date(timeIntervalSince1970: 947182440)
        let lunarCycle = 29.53058770576
        let daysSince = date.timeIntervalSince(knownNew) / 86400
        let phase = daysSince.truncatingRemainder(dividingBy: lunarCycle)
        let normalized = phase / lunarCycle

        switch normalized {
        case 0..<0.0625: return .new
        case 0.0625..<0.1875: return .waxingCrescent
        case 0.1875..<0.3125: return .firstQuarter
        case 0.3125..<0.4375: return .waxingGibbous
        case 0.4375..<0.5625: return .full
        case 0.5625..<0.6875: return .waningGibbous
        case 0.6875..<0.8125: return .lastQuarter
        default: return .waningCrescent
        }
    }
}
