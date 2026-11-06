import Foundation
import CoreLocation

/// Tide prediction from harmonic constants: each constituent's amplitude and
/// phase at this place (the bundled EOT20 grid, see `scripts/build_tide_constants.py`)
/// worked forward with the moon and sun's positions. Good for open coast, less
/// so up rivers and in enclosed bays, which the 1/2 degree grid can't resolve.
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
        fileprivate let quarterHours: [TidePoint]

        /// Whether the water is coming in at this time of the day, nil where
        /// there's no tide.
        func isRising(at time: Date) -> Bool? {
            quarterHours.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }?.isRising
        }
    }

    struct TideEvent: Sendable, Identifiable {
        let id = UUID()
        let time: Date
        let height: Double
        let isHigh: Bool
    }

    /// Whether this place has a tide: salt water within reach of the grid.
    static func hasTide(at coordinate: CLLocationCoordinate2D) -> Bool {
        TideConstants.shared?.site(at: coordinate) != nil
    }

    /// Generate a 24-hour tide curve for a location. Empty where there's no
    /// tide, inland or far offshore.
    static func predict(date: Date, coordinate: CLLocationCoordinate2D) -> TideDay {
        guard let site = TideConstants.shared?.site(at: coordinate) else {
            return TideDay(points: [], highTides: [], lowTides: [], currentPhase: .moving, quarterHours: [])
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(24 * 3600)

        // Generate points every 15 minutes for smooth curve, one past each
        // end of the day so a turn right at midnight is still found
        let quarter: TimeInterval = 900
        let samples = stride(from: -1, through: 97, by: 1).map { step -> TidePoint in
            let t = startOfDay.addingTimeInterval(Double(step) * quarter)
            return TidePoint(time: t, height: site.relativeHeight(at: t),
                             isRising: site.relativeHeight(at: t.addingTimeInterval(60)) > site.relativeHeight(at: t))
        }

        // Find high and low tides (local extrema), placed between samples
        // by the parabola through the three around each turn
        var highs: [TideEvent] = []
        var lows: [TideEvent] = []

        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1].height
            let curr = samples[i].height
            let next = samples[i + 1].height
            let isHigh = curr > prev && curr >= next
            let isLow = curr < prev && curr <= next
            guard isHigh || isLow else { continue }

            let curvature = prev - 2 * curr + next
            let offset = curvature == 0 ? 0 : 0.5 * (prev - next) / curvature
            let time = samples[i].time.addingTimeInterval(offset * quarter)
            guard time >= startOfDay, time < endOfDay else { continue }

            let event = TideEvent(time: time, height: site.relativeHeight(at: time), isHigh: isHigh)
            if isHigh { highs.append(event) } else { lows.append(event) }
        }

        // Current tide phase
        let now = Date.now
        let currentHeight = site.relativeHeight(at: now)
        let nearFutureHeight = site.relativeHeight(at: now.addingTimeInterval(900))

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

        // The day itself, without the extra sample at each end
        let quarterHours = Array(samples[1..<(samples.count - 1)])

        // Downsample to hourly for the main points array
        let hourlyPoints = quarterHours.enumerated().compactMap { i, p in
            i % 4 == 0 ? p : nil
        }

        return TideDay(
            points: hourlyPoints,
            highTides: highs,
            lowTides: lows,
            currentPhase: phase,
            quarterHours: quarterHours
        )
    }

    /// A place's harmonic constants. Each pair is amplitude * cos(phase) and
    /// amplitude * sin(phase), in the order `Astronomy.constituents` returns.
    struct Site: Sendable {
        let constants: [(cosine: Double, sine: Double)]
        private let scale: Double

        init(constants: [(cosine: Double, sine: Double)]) {
            self.constants = constants
            self.scale = constants.reduce(0) { $0 + hypot($1.cosine, $1.sine) }
        }

        /// Height against the most this place's tides could add up to.
        func relativeHeight(at date: Date) -> Double {
            guard scale > 0 else { return 0 }
            let constituents = Astronomy.constituents(at: date)
            var height = 0.0
            for (constant, constituent) in zip(constants, constituents) {
                let angle = constituent.argument * .pi / 180
                height += constituent.factor * (constant.cosine * cos(angle) + constant.sine * sin(angle))
            }
            return height / scale
        }
    }

    /// The moon and sun's mean positions, turned into each constituent's
    /// angle and its 18.6-year nodal factor (Schureman's and Doodson's forms).
    private enum Astronomy {
        struct Constituent {
            let argument: Double   // Degrees
            let factor: Double
        }

        /// M2, S2, N2, K2, K1, O1, P1, Q1, 2N2, M4.
        static func constituents(at date: Date) -> [Constituent] {
            let seconds = date.timeIntervalSince1970
            let centuries = (seconds / 86400 + 2440587.5 - 2451545.0) / 36525

            let s = 218.3164477 + 481267.88123421 * centuries  // Moon's mean longitude
            let h = 280.46645 + 36000.76983 * centuries        // Sun's mean longitude
            let p = 83.35324 + 4069.01363 * centuries          // Moon's perigee
            let node = (125.04452 - 1934.13626 * centuries) * .pi / 180
            let t = 15 * (seconds.truncatingRemainder(dividingBy: 86400) / 3600)

            let cos1 = cos(node), cos2 = cos(2 * node), cos3 = cos(3 * node)
            let sin1 = sin(node), sin2 = sin(2 * node), sin3 = sin(3 * node)

            let fM2: Double = 1.0004 - 0.0373 * cos1 + 0.0002 * cos2
            let uM2: Double = -2.14 * sin1
            let fK2: Double = 1.0241 + 0.2863 * cos1 + 0.0083 * cos2 - 0.0015 * cos3
            let uK2: Double = -17.74 * sin1 + 0.68 * sin2 - 0.04 * sin3
            let fK1: Double = 1.0060 + 0.1150 * cos1 - 0.0088 * cos2 + 0.0006 * cos3
            let uK1: Double = -8.86 * sin1 + 0.68 * sin2 - 0.07 * sin3
            let fO1: Double = 1.0089 + 0.1871 * cos1 - 0.0147 * cos2 + 0.0014 * cos3
            let uO1: Double = 10.80 * sin1 - 1.34 * sin2 + 0.19 * sin3

            let m2: Double = 2 * t - 2 * s + 2 * h
            return [
                Constituent(argument: m2 + uM2, factor: fM2),
                Constituent(argument: 2 * t, factor: 1),
                Constituent(argument: m2 - s + p + uM2, factor: fM2),
                Constituent(argument: 2 * t + 2 * h + uK2, factor: fK2),
                Constituent(argument: t + h + 90 + uK1, factor: fK1),
                Constituent(argument: t - 2 * s + h - 90 + uO1, factor: fO1),
                Constituent(argument: t - h - 90, factor: 1),
                Constituent(argument: t - 3 * s + h + p - 90 + uO1, factor: fO1),
                Constituent(argument: m2 - 2 * s + 2 * p + uM2, factor: fM2),
                Constituent(argument: 2 * m2 + 2 * uM2, factor: fM2 * fM2),
            ]
        }
    }
}

/// The bundled grid of harmonic constants, `Resources/Data/tide_constants.bin`.
/// The file's layout is described in `scripts/build_tide_constants.py`.
struct TideConstants: Sendable {
    static let shared: TideConstants? = {
        let url = Bundle.main.url(forResource: "tide_constants", withExtension: "bin", subdirectory: "Data")
            ?? Bundle.main.url(forResource: "tide_constants", withExtension: "bin")
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return TideConstants(data: data)
    }()

    /// How far from a place to look for water with a tide, in degrees.
    private static let reach = 0.75

    private let data: Data
    private let cellCount: Int
    private let constituentCount: Int
    private let cellsPerDegree: Int
    private let valuesOffset: Int

    init?(data: Data) {
        guard data.count >= 12, data.prefix(4).elementsEqual("TIDE".utf8) else { return nil }
        self.data = data
        cellCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian)
        constituentCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt16.self) }.littleEndian)
        cellsPerDegree = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 10, as: UInt16.self) }.littleEndian)
        valuesOffset = 12 + cellCount * 4
        guard cellsPerDegree > 0, data.count == valuesOffset + cellCount * constituentCount * 4 else { return nil }
    }

    /// The constants at a place, weighted from the nearest few cells of
    /// water. Nil when no cell is within reach.
    func site(at coordinate: CLLocationCoordinate2D) -> TideEngine.Site? {
        let perDegree = Double(cellsPerDegree)
        let columns = 360 * cellsPerDegree
        let rows = 180 * cellsPerDegree
        let longitude = (coordinate.longitude.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let row = (coordinate.latitude + 90) * perDegree
        let column = longitude * perDegree
        let window = Int((Self.reach * perDegree).rounded(.up))
        let shrink = cos(coordinate.latitude * .pi / 180)

        var near: [(distance: Double, cell: Int)] = []
        for y in (Int(row) - window)...(Int(row) + window + 1) where y >= 0 && y < rows {
            for x in (Int(column) - window)...(Int(column) + window + 1) {
                let wrapped = ((x % columns) + columns) % columns
                guard let cell = cellIndex(key: UInt32(y * columns + wrapped)) else { continue }
                let dy = (Double(y) - row) / perDegree
                let dx = (Double(x) - column) / perDegree * shrink
                let distance = dx * dx + dy * dy
                if distance <= Self.reach * Self.reach {
                    near.append((distance, cell))
                }
            }
        }
        guard !near.isEmpty else { return nil }
        near.sort { $0.distance < $1.distance }

        var constants = [(cosine: Double, sine: Double)](repeating: (0, 0), count: constituentCount)
        var totalWeight = 0.0
        for (distance, cell) in near.prefix(4) {
            let weight = 1 / (distance + 1e-4)
            totalWeight += weight
            for c in 0..<constituentCount {
                constants[c].cosine += weight * millimetres(cell: cell, constituent: c, part: 0)
                constants[c].sine += weight * millimetres(cell: cell, constituent: c, part: 1)
            }
        }
        return TideEngine.Site(constants: constants.map { ($0.cosine / totalWeight, $0.sine / totalWeight) })
    }

    /// Binary search of the sorted keys.
    private func cellIndex(key: UInt32) -> Int? {
        data.withUnsafeBytes { bytes in
            var low = 0
            var high = cellCount - 1
            while low <= high {
                let middle = (low + high) / 2
                let found = bytes.loadUnaligned(fromByteOffset: 12 + middle * 4, as: UInt32.self).littleEndian
                if found == key { return middle }
                if found < key { low = middle + 1 } else { high = middle - 1 }
            }
            return nil
        }
    }

    private func millimetres(cell: Int, constituent: Int, part: Int) -> Double {
        let offset = valuesOffset + (cell * constituentCount + constituent) * 4 + part * 2
        return Double(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int16.self) }.littleEndian)
    }
}
