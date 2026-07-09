import Foundation

/// Estimates a fish's weight from its length using the standard length–weight
/// relationship W = a · Lᵇ (W in grams, L in cm). Because we don't ship
/// per-species FishBase a/b constants, coefficients are chosen from the
/// species' body shape (elongated, average, deep-bodied, shark/ray), which
/// gets within a sensible ballpark for a quick field estimate.
enum WeightEstimator {

    /// Estimated weight in kilograms, or nil if length is non-positive.
    static func estimateKg(lengthCm: Double, species: Species?) -> Double? {
        guard lengthCm > 0 else { return nil }
        let (a, b) = coefficients(for: species)
        let grams = a * pow(lengthCm, b)
        return grams / 1000.0
    }

    /// (a, b) for W(g) = a · L(cm)ᵇ, by rough body shape.
    private static func coefficients(for species: Species?) -> (a: Double, b: Double) {
        guard let name = species?.commonName.lowercased() else { return (0.0120, 3.02) }

        func has(_ words: [String]) -> Bool { words.contains { name.contains($0) } }

        // Long, slender bodies — much lighter for their length.
        if has(["eel", "gar", "needlefish", "cutlass", "barracuda", "snoek", "wahoo",
                "cornetfish", "trumpetfish", "pike", "hound"]) {
            return (0.0030, 3.00)
        }
        // Sharks & rays — long, cartilaginous.
        if has(["shark", "ray", "skate", "sawfish", "guitarfish"]) {
            return (0.0045, 3.10)
        }
        // Deep / round-bodied — heavier for their length.
        if has(["sunfish", "bream", "crappie", "bluegill", "triggerfish", "drum",
                "roman", "poenskop", "musselcracker", "grunter", "spadefish", "seabream"]) {
            return (0.0200, 3.10)
        }
        // Tuna / mackerel / trevally — stocky, fast pelagics.
        if has(["tuna", "bonito", "mackerel", "trevally", "kingfish", "jack",
                "yellowtail", "amberjack", "cobia", "dorado", "mahi"]) {
            return (0.0150, 3.05)
        }
        // Default "average" fusiform fish (bass, trout, snapper, kob, etc.).
        return (0.0120, 3.02)
    }
}
