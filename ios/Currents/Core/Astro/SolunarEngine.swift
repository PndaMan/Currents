import Foundation
import CoreLocation

/// Astronomical calculations for solunar fishing theory.
/// Computes moon transit times, sun times, and feeding windows.
enum SolunarEngine {

    // MARK: - Public API

    struct SolunarDay: Sendable {
        let date: Date
        let sunrise: Date
        let sunset: Date
        let dawnGoldenHour: ClosedRange<Date>   // 30min before → 60min after sunrise
        let duskGoldenHour: ClosedRange<Date>   // 60min before → 30min after sunset
        let moonrise: Date?
        let moonset: Date?
        let majorPeriods: [FeedingWindow]        // Moon overhead + underfoot (~2h each)
        let minorPeriods: [FeedingWindow]        // Moonrise + moonset (~1h each)
        let moonPhase: MoonPhase
        let moonIllumination: Double             // 0.0 – 1.0
        let dayRating: DayRating
    }

    struct FeedingWindow: Sendable {
        let start: Date
        let peak: Date
        let end: Date
        let kind: Kind

        enum Kind: String, Sendable {
            case majorOverhead = "Moon Overhead"
            case majorUnderfoot = "Moon Underfoot"
            case minorMoonrise = "Moonrise"
            case minorMoonset = "Moonset"
        }

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    enum DayRating: Int, Sendable, Comparable {
        case poor = 1
        case fair = 2
        case good = 3
        case best = 4

        static func < (lhs: DayRating, rhs: DayRating) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .poor: "Poor"
            case .fair: "Fair"
            case .good: "Good"
            case .best: "Best"
            }
        }
    }

    /// Compute full solunar data for a given date and location.
    static func compute(date: Date, coordinate: CLLocationCoordinate2D) -> SolunarDay {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // Sun times
        let (sunrise, sunset) = sunTimes(date: noon, latitude: lat, longitude: lon)

        // Golden hours
        let dawnStart = sunrise.addingTimeInterval(-30 * 60)
        let dawnEnd = sunrise.addingTimeInterval(60 * 60)
        let duskStart = sunset.addingTimeInterval(-60 * 60)
        let duskEnd = sunset.addingTimeInterval(30 * 60)

        // Moon times
        let moonrise = moonEvent(date: noon, latitude: lat, longitude: lon, isRise: true)
        let moonset = moonEvent(date: noon, latitude: lat, longitude: lon, isRise: false)

        // Moon transit (overhead) and anti-transit (underfoot)
        let transit = moonTransit(date: noon, longitude: lon)
        let antiTransit = transit.addingTimeInterval(12.37 * 3600) // ~12h 22m later

        // Major periods: 1h before → 1h after transit
        var majors: [FeedingWindow] = []
        let majorDuration: TimeInterval = 3600 // 1h each side
        majors.append(FeedingWindow(
            start: transit.addingTimeInterval(-majorDuration),
            peak: transit,
            end: transit.addingTimeInterval(majorDuration),
            kind: .majorOverhead
        ))
        majors.append(FeedingWindow(
            start: antiTransit.addingTimeInterval(-majorDuration),
            peak: antiTransit,
            end: antiTransit.addingTimeInterval(majorDuration),
            kind: .majorUnderfoot
        ))

        // Minor periods: 30m before → 30m after rise/set
        var minors: [FeedingWindow] = []
        let minorDuration: TimeInterval = 1800 // 30m each side
        if let mr = moonrise {
            minors.append(FeedingWindow(
                start: mr.addingTimeInterval(-minorDuration),
                peak: mr,
                end: mr.addingTimeInterval(minorDuration),
                kind: .minorMoonrise
            ))
        }
        if let ms = moonset {
            minors.append(FeedingWindow(
                start: ms.addingTimeInterval(-minorDuration),
                peak: ms,
                end: ms.addingTimeInterval(minorDuration),
                kind: .minorMoonset
            ))
        }

        // Moon phase and illumination
        let phase = MoonPhase.current(for: date)
        let illumination = moonIllumination(for: date)

        // Day rating based on moon phase + solunar alignment
        let rating = computeDayRating(phase: phase, illumination: illumination,
                                       sunrise: sunrise, sunset: sunset,
                                       majors: majors, minors: minors)

        return SolunarDay(
            date: date,
            sunrise: sunrise,
            sunset: sunset,
            dawnGoldenHour: dawnStart...dawnEnd,
            duskGoldenHour: duskStart...duskEnd,
            moonrise: moonrise,
            moonset: moonset,
            majorPeriods: majors,
            minorPeriods: minors,
            moonPhase: phase,
            moonIllumination: illumination,
            dayRating: rating
        )
    }

    /// Hourly fishing score for a 24-hour period.
    static func hourlyScores(date: Date, coordinate: CLLocationCoordinate2D) -> [(hour: Int, score: Double)] {
        let solunar = compute(date: date, coordinate: coordinate)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        return (0..<24).map { hour in
            let hourDate = dayStart.addingTimeInterval(Double(hour) * 3600 + 1800) // mid-hour
            let score = hourScore(at: hourDate, solunar: solunar)
            return (hour: hour, score: score)
        }
    }

    // MARK: - Hour Score

    private static func hourScore(at date: Date, solunar: SolunarDay) -> Double {
        var score = 0.3 // baseline

        // Major period boost (+0.4)
        for major in solunar.majorPeriods {
            if date >= major.start && date <= major.end {
                let proximity = 1.0 - abs(date.timeIntervalSince(major.peak)) / (major.duration / 2)
                score += 0.4 * max(0, proximity)
            }
        }

        // Minor period boost (+0.2)
        for minor in solunar.minorPeriods {
            if date >= minor.start && date <= minor.end {
                let proximity = 1.0 - abs(date.timeIntervalSince(minor.peak)) / (minor.duration / 2)
                score += 0.2 * max(0, proximity)
            }
        }

        // Golden hour boost (+0.25)
        if solunar.dawnGoldenHour.contains(date) {
            let peakTime = solunar.sunrise
            let dist = abs(date.timeIntervalSince(peakTime)) / 3600
            score += 0.25 * max(0, 1.0 - dist)
        }
        if solunar.duskGoldenHour.contains(date) {
            let peakTime = solunar.sunset
            let dist = abs(date.timeIntervalSince(peakTime)) / 3600
            score += 0.25 * max(0, 1.0 - dist)
        }

        // Night penalty (not during golden hours)
        let isNight = date < solunar.sunrise.addingTimeInterval(-1800) ||
                      date > solunar.sunset.addingTimeInterval(1800)
        if isNight {
            score *= 0.6
        }

        // Moon phase multiplier
        switch solunar.moonPhase {
        case .new, .full:
            score *= 1.2
        case .firstQuarter, .lastQuarter:
            score *= 0.9
        default:
            break
        }

        return min(1.0, max(0.0, score))
    }

    // MARK: - Day Rating

    private static func computeDayRating(phase: MoonPhase, illumination: Double,
                                          sunrise: Date, sunset: Date,
                                          majors: [FeedingWindow],
                                          minors: [FeedingWindow]) -> DayRating {
        var points = 0

        // Moon phase score
        switch phase {
        case .new, .full: points += 3
        case .waxingGibbous, .waningGibbous: points += 2
        case .firstQuarter, .lastQuarter: points += 1
        default: points += 1
        }

        // Do major periods overlap golden hours?
        let dawnStart = sunrise.addingTimeInterval(-1800)
        let dawnEnd = sunrise.addingTimeInterval(3600)
        let duskStart = sunset.addingTimeInterval(-3600)
        let duskEnd = sunset.addingTimeInterval(1800)

        for major in majors {
            if major.peak >= dawnStart && major.peak <= dawnEnd { points += 2 }
            if major.peak >= duskStart && major.peak <= duskEnd { points += 2 }
        }
        for minor in minors {
            if minor.peak >= dawnStart && minor.peak <= dawnEnd { points += 1 }
            if minor.peak >= duskStart && minor.peak <= duskEnd { points += 1 }
        }

        switch points {
        case 0...2: return .poor
        case 3...4: return .fair
        case 5...6: return .good
        default: return .best
        }
    }

    // MARK: - Astronomical Calculations

    /// Julian Day Number from Date.
    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Sun rise/set times using simplified solar position.
    static func sunTimes(date: Date, latitude: Double, longitude: Double) -> (sunrise: Date, sunset: Date) {
        let cal = Calendar(identifier: .gregorian)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Solar declination (simplified)
        let declination = -23.45 * cos(toRadians(360.0 / 365.0 * (dayOfYear + 10)))
        let decRad = toRadians(declination)
        let latRad = toRadians(latitude)

        // Hour angle at sunrise/sunset
        let cosH = (cos(toRadians(90.833)) - sin(latRad) * sin(decRad)) / (cos(latRad) * cos(decRad))
        let hourAngle: Double
        if cosH > 1 {
            hourAngle = 0 // No sunrise (polar night)
        } else if cosH < -1 {
            hourAngle = 180 // No sunset (midnight sun)
        } else {
            hourAngle = toDegrees(acos(cosH))
        }

        // Equation of time (minutes)
        let b = toRadians(360.0 / 365.0 * (dayOfYear - 81))
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        // Solar noon in minutes from midnight UTC
        let solarNoon = 720.0 - 4.0 * longitude - eot

        let sunriseMin = solarNoon - hourAngle * 4.0
        let sunsetMin = solarNoon + hourAngle * 4.0

        let startOfDay = cal.startOfDay(for: date)
        let timeZoneOffset = Double(cal.timeZone.secondsFromGMT(for: date)) / 60.0

        let sunrise = startOfDay.addingTimeInterval((sunriseMin + timeZoneOffset) * 60)
        let sunset = startOfDay.addingTimeInterval((sunsetMin + timeZoneOffset) * 60)

        return (sunrise, sunset)
    }

    /// Approximate moon transit time (when moon is at its highest).
    private static func moonTransit(date: Date, longitude: Double) -> Date {
        let jd = julianDay(date)
        let T = (jd - 2451545.0) / 36525.0

        // Mean lunar longitude
        let L = 218.3165 + 481267.8813 * T
        let normalizedL = L.truncatingRemainder(dividingBy: 360)

        // Approximate transit: when moon's hour angle = 0
        // Moon moves ~13.2° per day relative to sun, transits ~50 min later each day
        let knownTransitJD = 2451545.0 + (normalizedL - longitude) / 360.0
        let daysSinceKnown = jd - knownTransitJD
        let lunarDay = 24.0 + 50.0 / 60.0 // hours between successive transits
        let transitsSince = (daysSinceKnown * 24.0 / lunarDay).rounded()
        let transitJD = knownTransitJD + transitsSince * lunarDay / 24.0

        // Clamp to the given date
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        var result = Date(timeIntervalSince1970: (transitJD - 2440587.5) * 86400.0)

        // Adjust to be within the day
        while result < startOfDay { result = result.addingTimeInterval(lunarDay * 3600) }
        while result > startOfDay.addingTimeInterval(86400) { result = result.addingTimeInterval(-lunarDay * 3600) }

        return result
    }

    /// Approximate moonrise/moonset using iterative search.
    private static func moonEvent(date: Date, latitude: Double, longitude: Double, isRise: Bool) -> Date? {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)

        // Search hour by hour for sign change in moon altitude
        var prevAlt = moonAltitude(at: startOfDay, latitude: latitude, longitude: longitude)

        for hour in 1...24 {
            let t = startOfDay.addingTimeInterval(Double(hour) * 3600)
            let alt = moonAltitude(at: t, latitude: latitude, longitude: longitude)

            if isRise && prevAlt < 0 && alt >= 0 {
                // Interpolate
                let fraction = -prevAlt / (alt - prevAlt)
                return t.addingTimeInterval(-(1.0 - fraction) * 3600)
            }
            if !isRise && prevAlt >= 0 && alt < 0 {
                let fraction = prevAlt / (prevAlt - alt)
                return t.addingTimeInterval(-(1.0 - fraction) * 3600)
            }
            prevAlt = alt
        }
        return nil // Moon doesn't rise/set on this day (can happen near poles)
    }

    /// Approximate moon altitude above horizon in degrees.
    private static func moonAltitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let jd = julianDay(date)
        let T = (jd - 2451545.0) / 36525.0

        // Simplified lunar position
        let L = 218.3165 + 481267.8813 * T // Mean longitude
        let M = 134.9634 + 477198.8676 * T // Mean anomaly
        let F = 93.2721 + 483202.0175 * T  // Argument of latitude

        let Lrad = toRadians(L)
        let Mrad = toRadians(M)
        let Frad = toRadians(F)

        // Ecliptic longitude and latitude (simplified)
        let lambda = L + 6.289 * sin(Mrad)
        let beta = 5.128 * sin(Frad)

        let lambdaRad = toRadians(lambda)
        let betaRad = toRadians(beta)

        // Obliquity of ecliptic
        let epsilon = toRadians(23.439 - 0.00000036 * (jd - 2451545.0))

        // Equatorial coordinates
        let sinDec = sin(betaRad) * cos(epsilon) + cos(betaRad) * sin(epsilon) * sin(lambdaRad)
        let dec = asin(sinDec)
        let ra = atan2(sin(lambdaRad) * cos(epsilon) - tan(betaRad) * sin(epsilon), cos(lambdaRad))

        // Hour angle
        let gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
        let lst = toRadians(gmst + longitude)
        let ha = lst - ra

        // Altitude
        let latRad = toRadians(latitude)
        let sinAlt = sin(latRad) * sin(dec) + cos(latRad) * cos(dec) * cos(ha)
        return toDegrees(asin(sinAlt))
    }

    /// Moon illumination fraction (0 = new, 1 = full).
    static func moonIllumination(for date: Date) -> Double {
        let knownNew = Date(timeIntervalSince1970: 947182440) // Jan 6, 2000
        let lunarCycle = 29.53058770576
        let daysSince = date.timeIntervalSince(knownNew) / 86400
        let phase = daysSince.truncatingRemainder(dividingBy: lunarCycle) / lunarCycle
        // Illumination follows a cosine curve
        return (1.0 - cos(phase * 2.0 * .pi)) / 2.0
    }

    // MARK: - Helpers

    private static func toRadians(_ degrees: Double) -> Double { degrees * .pi / 180.0 }
    private static func toDegrees(_ radians: Double) -> Double { radians * 180.0 / .pi }
}
