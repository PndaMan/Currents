import Foundation

/// On-device bite forecast scoring engine.
/// Computes the score formula entirely locally from cached weather data.
struct ForecastEngine {

    struct ForecastResult: Sendable {
        let score: Int // 0-100
        let reasons: [String]
        let breakdown: ScoreBreakdown
    }

    struct ScoreBreakdown: Sendable {
        let pressure: Double
        let pressureTrend: Double
        let tide: Double
        let moon: Double
        let temperature: Double
        let season: Double
    }

    /// Compute forecast score for a given location + species + conditions.
    static func compute(
        currentPressureHpa: Double?,
        pressureChange6h: Double?, // negative = falling
        tidePhase: TidePhase?,
        moonPhase: MoonPhase,
        waterTempC: Double?,
        species: Species?,
        isInSpawningZone: Bool
    ) -> ForecastResult {
        var reasons: [String] = []

        // Pressure (absolute)
        let wPressure: Double
        if let p = currentPressureHpa {
            switch p {
            case 1018...1030:
                wPressure = 1.0
            case 1014..<1018:
                wPressure = 0.9
                reasons.append("Pressure slightly low (\(Int(p)) hPa)")
            case 1030...:
                wPressure = 0.85
                reasons.append("High pressure post-front — fish may be sluggish")
            default:
                wPressure = 0.6
                reasons.append("Low pressure (\(Int(p)) hPa) — tough conditions")
            }
        } else {
            wPressure = 1.0
        }

        // Pressure trend (the secret sauce)
        let wPressureTrend: Double
        if let delta = pressureChange6h {
            if delta < -4 {
                wPressureTrend = 1.6
                reasons.append("Pressure dropping fast — feeding frenzy window before the front")
            } else if delta < -2 {
                wPressureTrend = 1.3
                reasons.append("Pressure falling — fish should be active")
            } else if delta > 4 {
                wPressureTrend = 0.7
                reasons.append("Pressure rising sharply — fish going off the bite")
            } else {
                wPressureTrend = 1.0
            }
        } else {
            wPressureTrend = 1.0
        }

        // Tide (coastal only)
        let wTide: Double
        if let tide = tidePhase {
            switch tide {
            case .nearHighOrLow:
                wTide = 1.4
                reasons.append("Tide change — peak feeding period")
            case .moving:
                wTide = 1.1
                reasons.append("Tide moving — decent current")
            case .slack:
                wTide = 0.7
                reasons.append("Slack tide — slow period")
            }
        } else {
            wTide = 1.0
        }

        // Moon phase
        let wMoon: Double
        switch moonPhase {
        case .new, .full:
            wMoon = 1.2
            reasons.append("\(moonPhase.displayName) — strong solunar influence")
        case .firstQuarter, .lastQuarter:
            wMoon = 0.9
        default:
            wMoon = 1.0
        }

        // Water temperature vs species optimal
        let wTemp: Double
        if let temp = waterTempC, let species, let optimal = species.optimalTempC {
            let sigma = (species.maxTempC ?? optimal + 5) - optimal
            let diff = abs(temp - optimal)
            wTemp = exp(-(diff * diff) / (2 * sigma * sigma)) // Gaussian falloff
            if diff > sigma {
                reasons.append("Water temp \(String(format: "%.0f", temp))°C is outside optimal range for \(species.commonName)")
            } else {
                reasons.append("Water temp \(String(format: "%.0f", temp))°C is in the zone for \(species.commonName)")
            }
        } else {
            wTemp = 1.0
        }

        // Spawning season
        let wSeason: Double
        if isInSpawningZone {
            wSeason = 1.5
            reasons.append("Active spawning zone — fish are aggressive")
        } else {
            wSeason = 1.0
        }

        let raw = 1.0 * wPressure * wPressureTrend * wTide * wMoon * wTemp * wSeason
        // Normalize to 0-100 (raw max is ~1.0 * 1.6 * 1.4 * 1.2 * 1.0 * 1.5 ≈ 4.03)
        let score = min(100, max(0, Int(raw / 4.0 * 100)))

        if reasons.isEmpty {
            reasons.append("Average conditions — worth a cast")
        }

        return ForecastResult(
            score: score,
            reasons: reasons,
            breakdown: ScoreBreakdown(
                pressure: wPressure,
                pressureTrend: wPressureTrend,
                tide: wTide,
                moon: wMoon,
                temperature: wTemp,
                season: wSeason
            )
        )
    }
}

// MARK: - Supporting Types

enum TidePhase: Sendable {
    case nearHighOrLow // within 1 hour of high/low
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

    /// Compute current moon phase from date using a simple algorithm.
    static func current(for date: Date = .now) -> MoonPhase {
        // Known new moon: Jan 6, 2000 18:14 UTC
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
