import Foundation

/// Estimates a fish's weight from its length using the standard FishBase
/// length–weight relationship  W(g) = a · L(cm)ᵇ.
///
/// Because weight scales with the CUBE of length, small fish are genuinely
/// light — e.g. a 30 cm trout really is only ~0.3 kg (anglers routinely
/// over-estimate). Coefficients are picked from the species' family first
/// (the strongest signal for body build), then name keywords, so different
/// species give different estimates rather than one flat number.
enum WeightEstimator {

    /// Estimated weight in kilograms, or nil for non-positive length.
    static func estimateKg(lengthCm: Double, species: Species?) -> Double? {
        guard lengthCm > 0 else { return nil }
        let (a, b) = coefficients(for: species)
        return (a * pow(lengthCm, b)) / 1000.0
    }

    /// (a, b) for W(g) = a · L(cm)ᵇ.
    private static func coefficients(for species: Species?) -> (a: Double, b: Double) {
        // 1) Name keywords win — they pin specific body shapes.
        if let name = species?.commonName.lowercased() {
            func has(_ w: [String]) -> Bool { w.contains { name.contains($0) } }

            if has(["eel", "needlefish", "cornetfish", "trumpetfish", "snipe eel"]) { return (0.0011, 3.10) }
            if has(["gar", "cutlass", "barracuda", "snoek", "hound", "pike", "muskellunge", "muskie"]) { return (0.0035, 3.05) }
            if has(["shark", "sawfish", "guitarfish"]) { return (0.0038, 3.08) }
            if has(["ray", "skate", "stingray", "manta", "mobula"]) { return (0.0080, 3.05) } // disc-shaped, heavy
            if has(["sunfish", "bluegill", "pumpkinseed", "crappie", "bream", "seabream",
                    "roman", "poenskop", "musselcracker", "triggerfish", "spadefish", "pomfret"]) { return (0.0210, 3.05) }
            if has(["tuna", "bonito", "mackerel", "grouper", "cod", "kob", "cobia", "amberjack"]) { return (0.0150, 3.02) }
            if has(["catfish", "barbel", "sharptooth"]) { return (0.0090, 3.05) }
            if has(["carp", "tilapia", "yellowfish", "mullet"]) { return (0.0155, 3.00) }
        }

        // 2) Family — a strong, broad signal available for most species.
        if let family = species?.family, let fc = familyCoefficients[family] {
            return fc
        }

        // 3) Sensible fusiform default (bass/trout/snapper-ish).
        return (0.0110, 3.04)
    }

    /// FishBase-informed medians by family (W in grams, L in cm).
    private static let familyCoefficients: [String: (Double, Double)] = [
        "Salmonidae": (0.0095, 3.05),          // trout, salmon
        "Centrarchidae": (0.0190, 3.08),       // bass, sunfish, crappie (deep)
        "Cyprinidae": (0.0150, 3.00),          // carp, minnows, barbs
        "Percidae": (0.0095, 3.06),            // perch, walleye
        "Esocidae": (0.0045, 3.05),            // pike (slender)
        "Ictaluridae": (0.0060, 3.05),         // channel/blue catfish (slim)
        "Clariidae": (0.0090, 3.05),           // sharptooth catfish (robust)
        "Sparidae": (0.0200, 3.02),            // breams, stumpnose (deep)
        "Scombridae": (0.0140, 3.02),          // tuna, mackerel
        "Carangidae": (0.0140, 3.00),          // jacks, trevally, yellowtail
        "Serranidae": (0.0180, 3.01),          // groupers, sea bass (robust)
        "Epinephelidae": (0.0180, 3.01),       // groupers
        "Lutjanidae": (0.0150, 3.02),          // snappers
        "Sciaenidae": (0.0110, 3.05),          // drums, kob, croakers
        "Moronidae": (0.0110, 3.06),           // temperate basses
        "Cichlidae": (0.0200, 3.00),           // tilapia, cichlids (deep)
        "Mugilidae": (0.0090, 3.10),           // mullet (slim)
        "Pomatomidae": (0.0090, 3.05),         // bluefish/elf
        "Carcharhinidae": (0.0038, 3.08),      // requiem sharks
        "Lamnidae": (0.0045, 3.10),            // mackerel sharks
        "Sphyrnidae": (0.0035, 3.08),          // hammerheads
        "Anguillidae": (0.0011, 3.10),         // eels
        "Belonidae": (0.0011, 3.10),           // needlefish
        "Istiophoridae": (0.0018, 3.30),       // marlins/sailfish (billfish)
        "Xiphiidae": (0.0025, 3.20),           // swordfish
    ]
}
