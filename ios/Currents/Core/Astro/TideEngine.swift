import Foundation
import CoreLocation

/// Simplified tidal prediction using lunar harmonics.
/// For real accuracy you'd need harmonic constituents for specific tide stations,
/// but this gives a reasonable approximation for fishing purposes.
enum TideEngine {

    struct TidePoint: Sendable {
        let time: Date
        let height: Double     // Relative height -1.0 to 1.0
        let isRising: Bool
    }

    struct TideDay: Sendable {
        let points: [TidePoint]        // Hourly points
        let highTides: [TideEvent]
        let lowTides: [TideEvent]
        let currentPhase: TidePhase
    }

    struct TideEvent: Sendable, Identifiable {
        let id = UUID()
        let time: Date
        let height: Double
        let isHigh: Bool
    }

    /// Generate a 24-hour tide curve for a location.
    /// Uses lunisolar harmonic approximation.
    static func predict(date: Date, coordinate: CLLocationCoordinate2D) -> TideDay {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Generate points every 15 minutes for smooth curve
        var points: [TidePoint] = []
        var prevHeight = tideHeight(at: startOfDay, longitude: coordinate.longitude)

        for minute in stride(from: 0, through: 24 * 60, by: 15) {
            let t = startOfDay.addingTimeInterval(Double(minute) * 60)
            let h = tideHeight(at: t, longitude: coordinate.longitude)
            let rising = h > prevHeight
            points.append(TidePoint(time: t, height: h, isRising: rising))
            prevHeight = h
        }

        // Find high and low tides (local extrema)
        var highs: [TideEvent] = []
        var lows: [TideEvent] = []

        for i in 1..<(points.count - 1) {
            let prev = points[i - 1].height
            let curr = points[i].height
            let next = points[i + 1].height

            if curr > prev && curr > next {
                highs.append(TideEvent(time: points[i].time, height: curr, isHigh: true))
            }
            if curr < prev && curr < next {
                lows.append(TideEvent(time: points[i].time, height: curr, isHigh: false))
            }
        }

        // Current tide phase
        let now = Date.now
        let currentHeight = tideHeight(at: now, longitude: coordinate.longitude)
        let nearFutureHeight = tideHeight(at: now.addingTimeInterval(900), longitude: coordinate.longitude)
        let isRising = nearFutureHeight > currentHeight

        // Check if near a high or low tide
        let nearThreshold: TimeInterval = 3600 // 1 hour
        let nearHigh = highs.contains { abs($0.time.timeIntervalSince(now)) < nearThreshold }
        let nearLow = lows.contains { abs($0.time.timeIntervalSince(now)) < nearThreshold }

        let phase: TidePhase
        if nearHigh || nearLow {
            phase = .nearHighOrLow
        } else if abs(nearFutureHeight - currentHeight) > 0.01 {
            phase = .moving
        } else {
            phase = .slack
        }

        // Downsample to hourly for the main points array
        let hourlyPoints = points.enumerated().compactMap { i, p in
            i % 4 == 0 ? p : nil
        }

        return TideDay(
            points: hourlyPoints,
            highTides: highs,
            lowTides: lows,
            currentPhase: phase
        )
    }

    /// Compute tide height using principal lunar and solar harmonic constituents.
    /// M2 (principal lunar, 12.42h period) + S2 (principal solar, 12h period)
    /// + K1 (lunisolar diurnal, 23.93h period)
    private static func tideHeight(at date: Date, longitude: Double) -> Double {
        let hours = date.timeIntervalSince1970 / 3600.0

        // Phase offset based on longitude (tides propagate)
        let lonOffset = longitude / 360.0

        // M2: Principal lunar semi-diurnal (period = 12.4206 hours)
        let m2Period = 12.4206
        let m2 = 0.5 * cos(2.0 * .pi * (hours / m2Period + lonOffset))

        // S2: Principal solar semi-diurnal (period = 12.0 hours)
        let s2Period = 12.0
        let s2 = 0.2 * cos(2.0 * .pi * (hours / s2Period + lonOffset))

        // K1: Lunisolar diurnal (period = 23.9345 hours)
        let k1Period = 23.9345
        let k1 = 0.15 * cos(2.0 * .pi * (hours / k1Period + lonOffset * 0.5))

        // O1: Principal lunar diurnal (period = 25.8193 hours)
        let o1Period = 25.8193
        let o1 = 0.1 * cos(2.0 * .pi * (hours / o1Period + lonOffset * 0.5))

        // Spring/neap modulation based on moon phase
        let moonIll = SolunarEngine.moonIllumination(for: date)
        // Near new/full moon = spring tides (larger), quarter = neap (smaller)
        let springNeap = 0.8 + 0.4 * abs(2.0 * moonIll - 1.0)

        return (m2 + s2 + k1 + o1) * springNeap
    }
}
