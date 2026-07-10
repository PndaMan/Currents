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

    static func length(cm: Double, imperial: Bool = isImperial) -> String {
        if imperial {
            let inches = cm / 2.54
            if inches >= 12 {
                let ft = Int(inches / 12)
                let rem = Int((inches.truncatingRemainder(dividingBy: 12)).rounded())
                return rem == 0 ? "\(ft) ft" : "\(ft)′ \(rem)″"
            }
            return "\(round(inches, 1)) in"
        }
        return "\(round(cm, cm < 100 ? 0 : 1)) cm"
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

    /// Length as (value, unit) — inches in imperial, cm in metric.
    static func lengthParts(cm: Double, imperial: Bool = isImperial) -> (String, String) {
        imperial ? (String(format: "%.1f", cm / 2.54), "in") : (String(format: "%.1f", cm), "cm")
    }

    /// Weight as (value, unit) — lb in imperial, kg in metric.
    static func weightParts(kg: Double, imperial: Bool = isImperial) -> (String, String) {
        imperial ? (String(format: "%.2f", kg * 2.2046226), "lb") : (String(format: "%.2f", kg), "kg")
    }

    // MARK: - Helpers

    /// Round to `decimals` places, dropping a trailing ".0".
    private static func round(_ value: Double, _ decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", value)
        if decimals > 0 && s.hasSuffix(String(repeating: "0", count: decimals)) && s.contains(".") {
            return String(format: "%.0f", value)
        }
        return s
    }
}
