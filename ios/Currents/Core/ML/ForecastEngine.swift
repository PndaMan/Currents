import Foundation
import CoreLocation

/// On-device bite forecast scoring engine.
/// Combines barometric pressure, solunar theory, tides, temperature,
/// wind, time-of-day, and seasonal patterns into a 0-100 score.
struct ForecastEngine {

    struct ForecastResult: Sendable {
        let score: Int // 0-100
        let reasons: [String]
        let breakdown: ScoreBreakdown
        let bestHours: [Int]          // Top 3 hours to fish today
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

    /// Full forecast with hourly breakdown for a location.
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
        // Get solunar data
        let solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
        let solunarHourly = SolunarEngine.hourlyScores(date: date, coordinate: coordinate)

        // Get tide data
        let tide = TideEngine.predict(date: date, coordinate: coordinate)

        // Compute current conditions score
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

        // Hourly scores: solunar time pattern (60%) + conditions (40%)
        let conditionScore = Double(currentResult.score)
        let hourlyScores = solunarHourly.map { item in
            let solunarPart = item.score * 100 * 0.6
            let conditionPart = conditionScore * 0.4
            let combined = Int(solunarPart + conditionPart)
            return (hour: item.hour, score: min(100, max(0, combined)))
        }

        // Best hours
        let bestHours = hourlyScores.sorted { $0.score > $1.score }.prefix(3).map(\.hour).sorted()

        // All feeding windows
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

    /// Simple forecast without location (backward compatible).
    static func compute(
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        tidePhase: TidePhase?,
        moonPhase: MoonPhase,
        waterTempC: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> ForecastResult {
        let result = computeLegacy(
            currentPressureHpa: currentPressureHpa,
            pressureChange6h: pressureChange6h,
            tidePhase: tidePhase,
            moonPhase: moonPhase,
            waterTempC: waterTempC,
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

    // MARK: - Instant Score

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

        // All factors score 0.0 to 1.0 (0 = worst, 0.5 = average, 1.0 = best)

        // === Pressure === (0-1)
        let wPressure: Double
        if let p = currentPressureHpa {
            switch p {
            case 1018...1030:
                wPressure = 1.0
            case 1013..<1018:
                wPressure = 0.7
                reasons.append("Pressure slightly low (\(Int(p)) hPa)")
            case 1030...:
                wPressure = 0.6
                reasons.append("High pressure — fish may be deep and sluggish")
            case 1005..<1013:
                wPressure = 0.4
                reasons.append("Low pressure (\(Int(p)) hPa)")
            default:
                wPressure = 0.2
                reasons.append("Very low pressure (\(Int(p)) hPa) — storm conditions")
            }
        } else {
            wPressure = 0.6 // no data = slightly below average
        }

        // === Pressure Trend === (0-1)
        let wPressureTrend: Double
        if let delta = pressureChange6h {
            if delta < -6 {
                wPressureTrend = 1.0
                reasons.append("Pressure crashing — feeding frenzy before the front")
            } else if delta < -3 {
                wPressureTrend = 0.9
                reasons.append("Pressure dropping fast — fish feeding aggressively")
            } else if delta < -1 {
                wPressureTrend = 0.75
                reasons.append("Pressure falling — fish should be active")
            } else if delta > 6 {
                wPressureTrend = 0.15
                reasons.append("Pressure spiking — fish shutting down")
            } else if delta > 3 {
                wPressureTrend = 0.3
                reasons.append("Pressure rising fast — bite slowing")
            } else {
                wPressureTrend = 0.55
            }
        } else {
            wPressureTrend = 0.5 // no data = neutral
        }

        // === Tide === (0-1)
        let wTide: Double
        switch tidePhase {
        case .nearHighOrLow:
            wTide = 1.0
            reasons.append("Tide change — peak feeding period")
        case .moving:
            wTide = 0.7
            reasons.append("Tide moving — good current flow")
        case .slack:
            wTide = 0.25
            reasons.append("Slack tide — slow period")
        }

        // === Moon === (0-1)
        let wMoon: Double
        switch solunar.moonPhase {
        case .new, .full:
            wMoon = 1.0
            reasons.append("\(solunar.moonPhase.displayName) — peak solunar influence")
        case .waxingGibbous, .waningGibbous:
            wMoon = 0.7
        case .firstQuarter, .lastQuarter:
            wMoon = 0.4
        default:
            wMoon = 0.55
        }

        // === Solunar feeding window === (0-1)
        let wSolunar: Double
        let inMajor = solunar.majorPeriods.contains { date >= $0.start && date <= $0.end }
        let inMinor = solunar.minorPeriods.contains { date >= $0.start && date <= $0.end }
        if inMajor {
            wSolunar = 1.0
            reasons.append("Major solunar period — prime feeding window")
        } else if inMinor {
            wSolunar = 0.75
            reasons.append("Minor solunar period — elevated activity")
        } else {
            wSolunar = 0.35
        }

        // === Time of Day === (0-1)
        let wTimeOfDay: Double
        if solunar.dawnGoldenHour.contains(date) {
            wTimeOfDay = 1.0
            reasons.append("Dawn golden hour — prime time")
        } else if solunar.duskGoldenHour.contains(date) {
            wTimeOfDay = 0.95
            reasons.append("Dusk golden hour — evening bite")
        } else if date < solunar.sunrise.addingTimeInterval(-1800) || date > solunar.sunset.addingTimeInterval(1800) {
            wTimeOfDay = 0.2
        } else {
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            if hour >= 10 && hour <= 14 {
                wTimeOfDay = 0.4
            } else {
                wTimeOfDay = 0.6
            }
        }

        // === Wind === (0-1)
        let wWind: Double
        if let wind = windSpeedKmh {
            switch wind {
            case 0..<5:
                wWind = 0.5
                reasons.append("Very calm — fish may be wary")
            case 5..<20:
                wWind = 1.0
                reasons.append("Light wind — ideal chop on the water")
            case 20..<35:
                wWind = 0.6
                reasons.append("Moderate wind — fish moving to wind-blown shores")
            default:
                wWind = 0.2
                reasons.append("Strong wind (\(Int(wind)) km/h) — tough conditions")
            }
        } else {
            wWind = 0.6 // no data = slight negative
        }

        // === Temperature === (0-1)
        let wTemp: Double
        if let temp = waterTempC, let species, let optimal = species.optimalTempC {
            let sigma = (species.maxTempC ?? optimal + 5) - optimal
            let diff = abs(temp - optimal)
            wTemp = exp(-(diff * diff) / (2 * sigma * sigma))
            if diff > sigma {
                reasons.append("Water \(String(format: "%.0f", temp))°C — outside optimal for \(species.commonName)")
            } else {
                reasons.append("Water \(String(format: "%.0f", temp))°C — in the zone for \(species.commonName)")
            }
        } else {
            wTemp = 0.6
        }

        // === Spawning Season === (0-1)
        let wSeason: Double
        if isInSpawningZone {
            wSeason = 1.0
            reasons.append("Active spawning zone — aggressive fish")
        } else {
            wSeason = 0.5
        }

        // === Combine (additive weighted) ===
        // Each factor: 0-1, weighted to sum to 100 points total
        let weights: [(Double, Double)] = [
            (wPressure, 10),
            (wPressureTrend, 15),
            (wTide, 15),
            (wMoon, 10),
            (wSolunar, 15),
            (wTimeOfDay, 15),
            (wWind, 8),
            (wTemp, 7),
            (wSeason, 5),
        ]
        let raw = weights.reduce(0.0) { sum, pair in
            sum + pair.0 * pair.1
        }
        let score = min(100, max(0, Int(raw)))

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

    // MARK: - Legacy API (no location)

    private static func computeLegacy(
        currentPressureHpa: Double?,
        pressureChange6h: Double?,
        tidePhase: TidePhase?,
        moonPhase: MoonPhase,
        waterTempC: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> InstantResult {
        var reasons: [String] = []

        // All factors 0-1 (same as instant scoring)
        let wPressure: Double
        if let p = currentPressureHpa {
            switch p {
            case 1018...1030: wPressure = 1.0
            case 1013..<1018: wPressure = 0.7; reasons.append("Pressure slightly low (\(Int(p)) hPa)")
            case 1030...: wPressure = 0.6; reasons.append("High pressure — fish may be sluggish")
            case 1005..<1013: wPressure = 0.4; reasons.append("Low pressure (\(Int(p)) hPa)")
            default: wPressure = 0.2; reasons.append("Very low pressure (\(Int(p)) hPa)")
            }
        } else { wPressure = 0.6 }

        let wPressureTrend: Double
        if let delta = pressureChange6h {
            if delta < -6 { wPressureTrend = 1.0; reasons.append("Pressure crashing — feeding frenzy") }
            else if delta < -3 { wPressureTrend = 0.9; reasons.append("Pressure dropping fast — fish feeding") }
            else if delta < -1 { wPressureTrend = 0.75; reasons.append("Pressure falling — fish active") }
            else if delta > 6 { wPressureTrend = 0.15; reasons.append("Pressure spiking") }
            else if delta > 3 { wPressureTrend = 0.3; reasons.append("Pressure rising sharply") }
            else { wPressureTrend = 0.55 }
        } else { wPressureTrend = 0.5 }

        let wTide: Double
        if let tide = tidePhase {
            switch tide {
            case .nearHighOrLow: wTide = 1.0; reasons.append("Tide change — peak feeding")
            case .moving: wTide = 0.7
            case .slack: wTide = 0.25; reasons.append("Slack tide — slow")
            }
        } else { wTide = 0.5 }

        let wMoon: Double
        switch moonPhase {
        case .new, .full: wMoon = 1.0; reasons.append("\(moonPhase.displayName) — strong solunar")
        case .firstQuarter, .lastQuarter: wMoon = 0.4
        default: wMoon = 0.55
        }

        let wTemp: Double
        if let temp = waterTempC, let species, let optimal = species.optimalTempC {
            let sigma = (species.maxTempC ?? optimal + 5) - optimal
            let diff = abs(temp - optimal)
            wTemp = exp(-(diff * diff) / (2 * sigma * sigma))
        } else { wTemp = 0.6 }

        let wSeason: Double = isInSpawningZone ? 1.0 : 0.5
        if isInSpawningZone { reasons.append("Active spawning zone") }

        // Additive: pressure(10) + trend(15) + tide(15) + moon(10) + solunar(15) + time(15) + wind(8) + temp(7) + season(5) = 100
        // Legacy has no solunar/time/wind, so redistribute: pressure(12) + trend(20) + tide(20) + moon(15) + temp(18) + season(15) = 100
        let weights: [(Double, Double)] = [
            (wPressure, 12),
            (wPressureTrend, 20),
            (wTide, 20),
            (wMoon, 15),
            (wTemp, 18),
            (wSeason, 15),
        ]
        let raw = weights.reduce(0.0) { $0 + $1.0 * $1.1 }
        let score = min(100, max(0, Int(raw)))

        if reasons.isEmpty { reasons.append("Average conditions — worth a cast") }

        return InstantResult(
            score: score,
            reasons: reasons,
            breakdown: ScoreBreakdown(
                pressure: wPressure, pressureTrend: wPressureTrend,
                tide: wTide, moon: wMoon, temperature: wTemp,
                season: wSeason, timeOfDay: 0.5, wind: 0.6, solunar: 0.35
            )
        )
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
