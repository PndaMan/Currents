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
                reasons.append("Ideal pressure (\(Int(p)) hPa)")
            } else if p >= 1013 && p < 1018 {
                wPressure = 0.65
            } else if p > 1028 && p <= 1035 {
                wPressure = 0.55
                reasons.append("High pressure (\(Int(p)) hPa) — fish may be deep")
            } else if p >= 1005 && p < 1013 {
                wPressure = 0.3
                reasons.append("Low pressure (\(Int(p)) hPa)")
            } else if p > 1035 {
                wPressure = 0.2
                reasons.append("Very high pressure (\(Int(p)) hPa) — sluggish bite")
            } else {
                wPressure = 0.1
                reasons.append("Storm-level pressure (\(Int(p)) hPa)")
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
                reasons.append("Pressure crashing — fish in a feeding frenzy")
            } else if delta < -3 {
                wPressureTrend = 0.9
                reasons.append("Pressure dropping — aggressive feeding")
            } else if delta < -1 {
                wPressureTrend = 0.7
                reasons.append("Pressure falling — fish active")
            } else if delta >= -1 && delta <= 1 {
                wPressureTrend = 0.3
                // Stable = below average, not above
            } else if delta > 1 && delta <= 3 {
                wPressureTrend = 0.15
                reasons.append("Pressure rising — bite shutting down")
            } else {
                wPressureTrend = 0.05
                reasons.append("Pressure spiking — fish lockjaw")
            }
        } else {
            havePressureTrend = false
            wPressureTrend = 0.3
        }

        // === Tide ===
        let wTide: Double
        switch tidePhase {
        case .nearHighOrLow:
            wTide = 1.0
            reasons.append("Tide change — peak feeding period")
        case .moving:
            wTide = 0.55
        case .slack:
            wTide = 0.1
            reasons.append("Slack tide — dead water")
        }

        // === Moon Phase ===
        let wMoon: Double
        switch solunar.moonPhase {
        case .new, .full:
            wMoon = 1.0
            reasons.append("\(solunar.moonPhase.displayName) — strongest solunar pull")
        case .waxingGibbous, .waningGibbous:
            wMoon = 0.65
        case .waxingCrescent, .waningCrescent:
            wMoon = 0.4
        case .firstQuarter, .lastQuarter:
            wMoon = 0.2
            reasons.append("Quarter moon — weakest solunar influence")
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
            reasons.append("Major solunar period — prime feeding window")
        } else if inMinor {
            wSolunar = 0.7
            reasons.append("Minor solunar period — elevated activity")
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
            reasons.append("Dawn golden hour — prime time")
        } else if solunar.duskGoldenHour.contains(date) {
            wTimeOfDay = 0.95
            reasons.append("Dusk golden hour — evening bite")
        } else {
            let isNight = date < solunar.sunrise.addingTimeInterval(-1800) ||
                          date > solunar.sunset.addingTimeInterval(1800)
            if isNight {
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
                    reasons.append("Midday — fish holding deep, low activity")
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
                reasons.append("Dead calm — fish line-shy, tough topwater")
            case 3..<8:
                wWind = 0.7
                reasons.append("Light breeze — slight chop, good visibility")
            case 8..<20:
                wWind = 1.0
                reasons.append("Moderate wind — ideal chop breaking up the surface")
            case 20..<30:
                wWind = 0.5
                reasons.append("Windy — fish the wind-blown bank")
            case 30..<45:
                wWind = 0.2
                reasons.append("Strong wind (\(Int(wind)) km/h) — difficult casting")
            default:
                wWind = 0.05
                reasons.append("Gale (\(Int(wind)) km/h) — dangerous conditions")
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
                reasons.append("Water \(String(format: "%.0f°C", temp)) — ideal range for \(species.commonName)")
            } else if diff <= range {
                reasons.append("Water \(String(format: "%.0f°C", temp)) — marginal for \(species.commonName)")
            } else {
                reasons.append("Water \(String(format: "%.0f°C", temp)) — outside comfort for \(species.commonName)")
            }
        } else if let temp = waterTempC {
            haveTemp = true
            // No species selected — use a general freshwater heuristic.
            // 15-25°C is the universal sweet spot for most gamefish.
            if temp >= 15 && temp <= 25 {
                wTemp = 0.85
            } else if temp >= 10 && temp < 15 {
                wTemp = 0.5
                reasons.append("Water \(String(format: "%.0f°C", temp)) — cool, slower metabolism")
            } else if temp > 25 && temp <= 30 {
                wTemp = 0.55
                reasons.append("Water \(String(format: "%.0f°C", temp)) — warm, fish go deep")
            } else if temp > 30 {
                wTemp = 0.2
                reasons.append("Water \(String(format: "%.0f°C", temp)) — too warm, low oxygen")
            } else {
                wTemp = 0.25
                reasons.append("Water \(String(format: "%.0f°C", temp)) — cold, fish lethargic")
            }
        } else {
            haveTemp = false
            wTemp = 0.5
        }

        // === Spawning Season ===
        let wSeason: Double
        if isInSpawningZone {
            wSeason = 1.0
            reasons.append("Active spawning zone — aggressive territorial fish")
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
            Factor(value: wTide,          baseWeight: 12, hasData: true),  // always computed
            Factor(value: wMoon,          baseWeight: 8,  hasData: true),
            Factor(value: wSolunar,       baseWeight: 18, hasData: true),
            Factor(value: wTimeOfDay,     baseWeight: 16, hasData: true),
            Factor(value: wWind,          baseWeight: 8,  hasData: haveWind),
            Factor(value: wTemp,          baseWeight: 6,  hasData: haveTemp),
            Factor(value: wSeason,        baseWeight: 4,  hasData: true),
        ]

        let totalBaseWeight = factors.reduce(0.0) { $0 + $1.baseWeight }
        let availableWeight = factors.filter(\.hasData).reduce(0.0) { $0 + $1.baseWeight }
        let scale = availableWeight > 0 ? totalBaseWeight / availableWeight : 1.0

        var rawSum = 0.0
        for f in factors {
            let w = f.hasData ? f.baseWeight * scale : 0
            rawSum += f.value * w
        }
        // rawSum is in 0...100 but clusters around 40-60 in practice.
        // Apply a power-curve stretch: x^0.85 * 1.1 (boosts highs,
        // preserves lows, widens the spread).
        let normalized = rawSum / 100.0 // 0-1
        let stretched = pow(normalized, 0.8) * 1.15
        let score = min(100, max(0, Int(stretched * 100)))

        if reasons.isEmpty {
            reasons.append("Average conditions — worth a cast")
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
                solunar: wSolunar
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
        case .new: "New Moon"
        case .waxingCrescent: "Waxing Crescent"
        case .firstQuarter: "First Quarter"
        case .waxingGibbous: "Waxing Gibbous"
        case .full: "Full Moon"
        case .waningGibbous: "Waning Gibbous"
        case .lastQuarter: "Last Quarter"
        case .waningCrescent: "Waning Crescent"
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
