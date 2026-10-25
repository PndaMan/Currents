import Foundation

/// Central unit formatting for the whole app. Stored data is always metric
/// (°C, cm, kg, km, km/h, m); this converts to the user's chosen system at
/// display time. Views that should update live when the setting changes read
/// `@AppStorage("units")` and pass `imperial:` explicitly; non-view callers
/// (share cards, notifications) use the default, which reads the stored value.
enum Units {
    /// True when the user picked Imperial in Settings › Units.
    static var isImperial: Bool {
        UserDefaults.standard.string(forKey: "units") == "imperial"
    }

    // MARK: Temperature (stored °C)

    static func temperature(_ celsius: Double, imperial: Bool = isImperial, decimals: Int = 0) -> String {
        if imperial {
            return "\(round(celsius * 9 / 5 + 32, decimals))°F"
        }
        return "\(round(celsius, decimals))°C"
    }

    static var temperatureSymbol: String { isImperial ? "°F" : "°C" }

    // MARK: Length (stored cm) — fish sizes

    /// A fish length, rounded as `lengthParts` rounds it so the two agree:
    /// "99.5 cm", "52 cm", or "20.5 in" in imperial (anglers measure fish in
    /// inches, not feet).
    static func length(cm: Double, imperial: Bool = isImperial) -> String {
        let (value, unit) = lengthParts(cm: cm, imperial: imperial)
        return "\(value) \(unit)"
    }

    // MARK: Weight (stored kg or g)

    static func weight(kg: Double, imperial: Bool = isImperial) -> String {
        if imperial {
            let lb = kg * 2.2046226
            if lb < 1 { return "\(round(lb * 16, 1)) oz" }
            return "\(round(lb, 2)) lb"
        }
        if kg < 1 { return "\(round(kg * 1000, 0)) g" }
        return "\(round(kg, 2)) kg"
    }

    static func weight(grams: Double, imperial: Bool = isImperial) -> String {
        weight(kg: grams / 1000, imperial: imperial)
    }

    // MARK: Distance (stored km / m)

    static func distance(km: Double, imperial: Bool = isImperial) -> String {
        if imperial {
            let mi = km * 0.62137119
            if mi < 0.19 { return "\(round(mi * 5280, 0)) ft" }
            return "\(round(mi, mi < 10 ? 1 : 0)) mi"
        }
        if km < 1 { return "\(round(km * 1000, 0)) m" }
        return "\(round(km, km < 10 ? 1 : 0)) km"
    }

    static func distance(m: Double, imperial: Bool = isImperial) -> String {
        distance(km: m / 1000, imperial: imperial)
    }

    /// Depth / short vertical distance (stored m).
    static func depth(m: Double, imperial: Bool = isImperial) -> String {
        if imperial { return "\(round(m * 3.2808399, 0)) ft" }
        return "\(round(m, m < 10 ? 1 : 0)) m"
    }

    // MARK: Speed (stored km/h) — wind

    static func speed(kmh: Double, imperial: Bool = isImperial) -> String {
        if imperial { return "\(round(kmh * 0.62137119, 0)) mph" }
        return "\(round(kmh, 0)) km/h"
    }

    static var speedSymbol: String { isImperial ? "mph" : "km/h" }

    // MARK: Split value/unit (for stat cells that style them separately)

    /// Length as (value, unit) — inches in imperial, cm in metric. 52.0 cm
    /// gives ("52", "cm").
    static func lengthParts(cm: Double, imperial: Bool = isImperial) -> (String, String) {
        imperial ? (round(cm / 2.54, 1), "in") : (round(cm, 1), "cm")
    }

    /// Weight as (value, unit) — lb in imperial, kg in metric. 2.90 kg gives
    /// ("2.9", "kg").
    static func weightParts(kg: Double, imperial: Bool = isImperial) -> (String, String) {
        imperial ? (round(kg * 2.2046226, 2), "lb") : (round(kg, 2), "kg")
    }

    // MARK: Pressure (stored hPa)

    /// A barometer reading: "1016 hPa", or "30.01 inHg" in imperial.
    static func pressure(hpa: Double, imperial: Bool = isImperial) -> String {
        let (value, unit) = pressureParts(hpa: hpa, imperial: imperial)
        return "\(value) \(unit)"
    }

    /// A barometer reading as (value, unit): ("1016", "hPa") or ("30.01", "inHg").
    static func pressureParts(hpa: Double, imperial: Bool = isImperial) -> (String, String) {
        if imperial { return (String(format: "%.2f", hpa * inHgPerHpa), "inHg") }
        return (String(format: "%.0f", hpa), "hPa")
    }

    /// The size of a pressure change, without its direction: "1.5 hPa", or
    /// "0.04 inHg" in imperial.
    static func pressureChange(hpa: Double, imperial: Bool = isImperial) -> String {
        let size = abs(hpa)
        if imperial { return "\(round(size * inHgPerHpa, 2)) inHg" }
        return "\(round(size, 1)) hPa"
    }

    // MARK: Area (stored km²)

    /// An area: "5.2 km²", "85 km²", or "2 sq mi" in imperial. With
    /// `smallInHectares`, an area under 1 km² is "50 ha", or "12 acres" in
    /// imperial.
    static func area(km2: Double, imperial: Bool = isImperial, smallInHectares: Bool = false) -> String {
        if smallInHectares && km2 < 1 {
            if imperial {
                let acres = km2 * 247.105
                let text = acres.formatted(.number.precision(.fractionLength(0)))
                return text == "1" ? "1 acre" : text + " acres"
            }
            return (km2 * 100).formatted(.number.precision(.fractionLength(0))) + " ha"
        }
        if imperial {
            let mi2 = km2 * 0.386102
            return mi2.formatted(.number.precision(.fractionLength(mi2 < 10 ? 1 : 0))) + " sq mi"
        }
        return km2.formatted(.number.precision(.fractionLength(km2 < 10 ? 1 : 0))) + " km²"
    }

    // MARK: Elevation (stored m)

    /// Height above sea level: "120 m", or "394 ft" in imperial.
    static func elevation(m: Double, imperial: Bool = isImperial) -> String {
        if imperial { return "\(round(m * 3.2808399, 0)) ft" }
        return "\(round(m, 0)) m"
    }

    // MARK: Temperature difference (stored °C)

    /// A difference between two temperatures, not a reading: "3°C", or
    /// "5°F" in imperial (scaled by 9/5 with no offset).
    static func temperatureDelta(_ celsius: Double, imperial: Bool = isImperial) -> String {
        if imperial { return "\(round(celsius * 9 / 5, 0))°F" }
        return "\(round(celsius, 0))°C"
    }

    // MARK: Lure weight (stored g)

    /// A lure or sinker weight: "14 g", "3.5 g", or "0.5 oz" in imperial.
    /// Line strength stays in lb everywhere and is not formatted here.
    static func lureWeight(grams: Double, imperial: Bool = isImperial) -> String {
        if imperial { return "\(round(grams / 28.349523, 2)) oz" }
        return "\(round(grams, 1)) g"
    }

    // MARK: - Helpers

    private static let inHgPerHpa = 0.0295300

    /// Round to `decimals` places, then drop trailing zeros after the point
    /// and the point itself if nothing is left: 2.90 gives "2.9", 52.0 gives
    /// "52", 1.25 gives "1.25".
    private static func round(_ value: Double, _ decimals: Int) -> String {
        var s = String(format: "%.\(max(0, decimals))f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }
}
