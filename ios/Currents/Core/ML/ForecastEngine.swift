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

        // Hourly scores combining solunar + conditions
        let hourlyScores = solunarHourly.map { item in
            let conditionMultiplier = Double(currentResult.score) / 50.0 // normalize around 1.0
            let combined = Int(item.score * 100 * conditionMultiplier)
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

        // === Pressure ===
        let wPressure: Double
        if let p = currentPressureHpa {
            switch p {
            case 1018...1030:
                wPressure = 1.0
            case 1013..<1018:
                wPressure = 0.9
                reasons.append("Pressure slightly low (\(Int(p)) hPa)")
            case 1030...:
                wPressure = 0.8
                reasons.append("High pressure — fish may be deep and sluggish")
            case 1005..<1013:
                wPressure = 0.7
                reasons.append("Low pressure (\(Int(p)) hPa)")
            default:
                wPressure = 0.5
                reasons.append("Very low pressure (\(Int(p)) hPa) — storm conditions")
            }
        } else {
            wPressure = 1.0
        }

        // === Pressure Trend (most important single factor) ===
        let wPressureTrend: Double
        if let delta = pressureChange6h {
            if delta < -6 {
                wPressureTrend = 1.7
                reasons.append("Pressure crashing — feeding frenzy before the front")
            } else if delta < -3 {
                wPressureTrend = 1.5
                reasons.append("Pressure dropping fast — fish are feeding aggressively")
            } else if delta < -1 {
                wPressureTrend = 1.3
                reasons.append("Pressure falling — fish should be active")
            } else if delta > 6 {
                wPressureTrend = 0.5
                reasons.append("Pressure spiking — fish shutting down")
            } else if delta > 3 {
                wPressureTrend = 0.7
                reasons.append("Pressure rising fast — bite slowing")
            } else {
                wPressureTrend = 1.0
            }
        } else {
            wPressureTrend = 1.0
        }

        // === Tide ===
        let wTide: Double
        switch tidePhase {
        case .nearHighOrLow:
            wTide = 1.4
            reasons.append("Tide change — peak feeding period")
        case .moving:
            wTide = 1.15
            reasons.append("Tide moving — good current flow")
        case .slack:
            wTide = 0.7
            reasons.append("Slack tide — slow period")
        }

        // === Moon / Solunar ===
        let wMoon: Double
        switch solunar.moonPhase {
        case .new, .full:
            wMoon = 1.25
            reasons.append("\(solunar.moonPhase.displayName) — peak solunar influence")
        case .firstQuarter, .lastQuarter:
            wMoon = 0.85
        default:
            wMoon = 1.0
        }

        // === Solunar feeding window ===
        let wSolunar: Double
        let allWindows = solunar.majorPeriods + solunar.minorPeriods
        let inMajor = solunar.majorPeriods.contains { date >= $0.start && date <= $0.end }
        let inMinor = solunar.minorPeriods.contains { date >= $0.start && date <= $0.end }
        if inMajor {
            wSolunar = 1.4
            reasons.append("Major solunar period — prime feeding window")
        } else if inMinor {
            wSolunar = 1.2
            reasons.append("Minor solunar period — elevated activity")
        } else {
            wSolunar = 1.0
        }

        // === Time of Day ===
        let wTimeOfDay: Double
        if solunar.dawnGoldenHour.contains(date) {
            wTimeOfDay = 1.35
            reasons.append("Dawn golden hour — prime time")
        } else if solunar.duskGoldenHour.contains(date) {
            wTimeOfDay = 1.3
            reasons.append("Dusk golden hour — evening bite")
        } else if date < solunar.sunrise.addingTimeInterval(-1800) || date > solunar.sunset.addingTimeInterval(1800) {
            wTimeOfDay = 0.6
        } else {
            // Middle of the day
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: date)
            if hour >= 10 && hour <= 14 {
                wTimeOfDay = 0.75
            } else {
                wTimeOfDay = 0.9
            }
        }

        // === Wind ===
        let wWind: Double
        if let wind = windSpeedKmh {
            switch wind {
            case 0..<5:
                wWind = 0.85
                reasons.append("Very calm — fish may be wary")
            case 5..<20:
                wWind = 1.15
                reasons.append("Light wind — ideal chop on the water")
            case 20..<35:
                wWind = 0.9
                reasons.append("Moderate wind — fish moving to wind-blown shores")
            default:
                wWind = 0.6
                reasons.append("Strong wind (\(Int(wind)) km/h) — tough conditions")
            }
        } else {
            wWind = 1.0
        }

        // === Temperature ===
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
            wTemp = 1.0
        }

        // === Spawning Season ===
        let wSeason: Double
        if isInSpawningZone {
            wSeason = 1.5
            reasons.append("Active spawning zone — aggressive fish")
        } else {
            wSeason = 1.0
        }

        // === Combine ===
        let raw = wPressure * wPressureTrend * wTide * wMoon * wSolunar * wTimeOfDay * wWind * wTemp * wSeason
        // Max theoretical: 1.0 * 1.7 * 1.4 * 1.25 * 1.4 * 1.35 * 1.15 * 1.0 * 1.5 ≈ 8.1
        let score = min(100, max(0, Int(raw / 8.0 * 100)))

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

        let wPressure: Double
        if let p = currentPressureHpa {
            switch p {
            case 1018...1030: wPressure = 1.0
            case 1014..<1018: wPressure = 0.9; reasons.append("Pressure slightly low (\(Int(p)) hPa)")
            case 1030...: wPressure = 0.85; reasons.append("High pressure — fish may be sluggish")
            default: wPressure = 0.6; reasons.append("Low pressure (\(Int(p)) hPa)")
            }
        } else { wPressure = 1.0 }

        let wPressureTrend: Double
        if let delta = pressureChange6h {
            if delta < -4 { wPressureTrend = 1.6; reasons.append("Pressure dropping fast — feeding frenzy") }
            else if delta < -2 { wPressureTrend = 1.3; reasons.append("Pressure falling — fish active") }
            else if delta > 4 { wPressureTrend = 0.7; reasons.append("Pressure rising sharply") }
            else { wPressureTrend = 1.0 }
        } else { wPressureTrend = 1.0 }

        let wTide: Double
        if let tide = tidePhase {
            switch tide {
            case .nearHighOrLow: wTide = 1.4; reasons.append("Tide change — peak feeding")
            case .moving: wTide = 1.1
            case .slack: wTide = 0.7; reasons.append("Slack tide — slow")
            }
        } else { wTide = 1.0 }

        let wMoon: Double
        switch moonPhase {
        case .new, .full: wMoon = 1.2; reasons.append("\(moonPhase.displayName) — strong solunar")
        case .firstQuarter, .lastQuarter: wMoon = 0.9
        default: wMoon = 1.0
        }

        let wTemp: Double
        if let temp = waterTempC, let species, let optimal = species.optimalTempC {
            let sigma = (species.maxTempC ?? optimal + 5) - optimal
            let diff = abs(temp - optimal)
            wTemp = exp(-(diff * diff) / (2 * sigma * sigma))
        } else { wTemp = 1.0 }

        let wSeason: Double = isInSpawningZone ? 1.5 : 1.0
        if isInSpawningZone { reasons.append("Active spawning zone") }

        let raw = wPressure * wPressureTrend * wTide * wMoon * wTemp * wSeason
        let score = min(100, max(0, Int(raw / 4.0 * 100)))

        if reasons.isEmpty { reasons.append("Average conditions — worth a cast") }

        return InstantResult(
            score: score,
            reasons: reasons,
            breakdown: ScoreBreakdown(
                pressure: wPressure, pressureTrend: wPressureTrend,
                tide: wTide, moon: wMoon, temperature: wTemp,
                season: wSeason, timeOfDay: 1.0, wind: 1.0, solunar: 1.0
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
