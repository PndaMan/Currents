import Foundation

/// "What to Throw" — a transparent, rules-based lure recommender.
///
/// Deliberately *not* a model: every suggestion can explain itself in plain
/// English, it works fully offline, and it needs no training data. The weights
/// encode well-established angling heuristics (water clarity drives colour,
/// water temperature drives retrieve speed and lure family, falling pressure
/// favours reaction baits, post-front high pressure favours finesse).
///
/// What makes it *yours* rather than generic: it ranks lures you actually own
/// first, and it counts how often each family has genuinely caught you fish in
/// similar water — read from the loadout recorded against every catch.
enum LureEngine {

    // MARK: - Inputs

    struct Conditions {
        var waterTempC: Double?
        var clarity: WaterClarity
        var cloudCoverPct: Int?
        var windSpeedKmh: Double?
        var pressureChange6h: Double?
        var date: Date = .now

        /// Overcast, dawn or dusk — when fish lose their light advantage and
        /// bolder presentations start to out-fish natural ones.
        var isLowLight: Bool {
            if let c = cloudCoverPct, c >= 65 { return true }
            let h = Calendar.current.component(.hour, from: date)
            return h < 7 || h >= 18
        }

        var isWindy: Bool { (windSpeedKmh ?? 0) >= 15 }
        /// A falling glass is the classic pre-front feeding trigger.
        var isFalling: Bool { (pressureChange6h ?? 0) <= -1.5 }
        /// Bluebird high pressure behind a front — the toughest bite there is.
        var isPostFront: Bool { (pressureChange6h ?? 0) >= 1.5 }
    }

    // MARK: - Output

    struct Suggestion: Identifiable {
        let id = UUID()
        let lure: String
        let color: String
        let technique: String
        let depth: String
        /// Plain-English chips explaining why this made the list.
        let reasons: [String]
        /// 0…1 — drives the confidence bar.
        let score: Double
        /// Set when this matches something in the angler's tackle box.
        let ownedName: String?
        /// Times a loadout matching this family has caught this angler a fish.
        let personalCatches: Int

        var isOwned: Bool { ownedName != nil }
    }

    // MARK: - Lure archetypes

    private struct Archetype {
        let name: String
        let keywords: [String]
        let minTempC: Double
        let maxTempC: Double
        let clarity: [WaterClarity: Double]
        let lowLightBonus: Double
        let windBonus: Double
        let fallingBonus: Double
        let postFrontBonus: Double
        /// Working depth in metres. Nil for surface and bottom presentations,
        /// which say where they are fished in `depthWord` instead.
        let depth: ClosedRange<Double>?
        var depthWord: String? = nil
        let technique: String
    }

    private static let archetypes: [Archetype] = [
        Archetype(name: "Spinnerbait", keywords: ["spinner", "spinnerbait", "blade"],
                  minTempC: 10, maxTempC: 26,
                  clarity: [.clear: 0.35, .stained: 1.0, .muddy: 0.85],
                  lowLightBonus: 0.15, windBonus: 0.20, fallingBonus: 0.15, postFrontBonus: -0.10,
                  depth: 0.5...2, technique: "Slow-roll it just fast enough to feel the blade thump."),

        Archetype(name: "Chatterbait", keywords: ["chatter", "bladed jig", "vibrating jig"],
                  minTempC: 10, maxTempC: 26,
                  clarity: [.clear: 0.4, .stained: 1.0, .muddy: 0.9],
                  lowLightBonus: 0.10, windBonus: 0.15, fallingBonus: 0.15, postFrontBonus: -0.10,
                  depth: 0.5...2.5, technique: "Steady retrieve, ripping it free whenever it ticks cover."),

        Archetype(name: "Lipless crankbait", keywords: ["lipless", "rattle trap", "rat-l-trap", "vib"],
                  minTempC: 6, maxTempC: 20,
                  clarity: [.clear: 0.5, .stained: 0.95, .muddy: 0.85],
                  lowLightBonus: 0.05, windBonus: 0.15, fallingBonus: 0.20, postFrontBonus: -0.05,
                  depth: 1...3, technique: "Yo-yo it over grass. Most bites come as it falls."),

        Archetype(name: "Squarebill crankbait", keywords: ["crank", "squarebill", "crankbait", "plug"],
                  minTempC: 10, maxTempC: 28,
                  clarity: [.clear: 0.6, .stained: 0.95, .muddy: 0.6],
                  lowLightBonus: 0.10, windBonus: 0.20, fallingBonus: 0.15, postFrontBonus: -0.15,
                  depth: 0.5...2, technique: "Grind it into cover and pause the moment it deflects."),

        Archetype(name: "Jerkbait", keywords: ["jerkbait", "minnow", "stickbait", "suspend"],
                  minTempC: 3, maxTempC: 15,
                  clarity: [.clear: 1.0, .stained: 0.55, .muddy: 0.2],
                  lowLightBonus: 0.05, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.20,
                  depth: 1...2.5, technique: "Two twitches then a long pause. The colder it is, the longer the pause."),

        Archetype(name: "Skirted jig", keywords: ["jig", "flipping jig", "football"],
                  minTempC: 3, maxTempC: 22,
                  clarity: [.clear: 0.6, .stained: 0.85, .muddy: 1.0],
                  lowLightBonus: 0.05, windBonus: 0.0, fallingBonus: 0.05, postFrontBonus: 0.20,
                  depth: 1...6, technique: "Drag it slowly along the bottom, pausing hard against structure."),

        Archetype(name: "Ned rig", keywords: ["ned", "finesse", "shroom", "trd"],
                  minTempC: 5, maxTempC: 24,
                  clarity: [.clear: 1.0, .stained: 0.6, .muddy: 0.25],
                  lowLightBonus: -0.05, windBonus: -0.10, fallingBonus: -0.05, postFrontBonus: 0.30,
                  depth: 1...5, technique: "Barely move it and let the bottom do the work."),

        Archetype(name: "Drop shot", keywords: ["drop shot", "dropshot", "finesse worm"],
                  minTempC: 6, maxTempC: 27,
                  clarity: [.clear: 1.0, .stained: 0.55, .muddy: 0.2],
                  lowLightBonus: -0.05, windBonus: -0.10, fallingBonus: -0.05, postFrontBonus: 0.30,
                  depth: 2...10, technique: "Hold it in place and shake it, keeping the weight pinned to the bottom."),

        Archetype(name: "Texas-rigged worm", keywords: ["worm", "texas", "soft plastic", "creature", "senko"],
                  minTempC: 14, maxTempC: 32,
                  clarity: [.clear: 0.9, .stained: 0.85, .muddy: 0.7],
                  lowLightBonus: 0.0, windBonus: -0.05, fallingBonus: 0.0, postFrontBonus: 0.20,
                  depth: 1...5, technique: "Pitch to cover, let it sink on slack line, lift and drop."),

        Archetype(name: "Swimbait", keywords: ["swimbait", "paddle tail", "shad", "glide"],
                  minTempC: 8, maxTempC: 26,
                  clarity: [.clear: 1.0, .stained: 0.7, .muddy: 0.35],
                  lowLightBonus: 0.10, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.05,
                  depth: 1...4, technique: "Slow, steady wind at the depth the bait is holding."),

        Archetype(name: "Topwater walker", keywords: ["topwater", "walk", "spook", "popper", "surface"],
                  minTempC: 16, maxTempC: 32,
                  clarity: [.clear: 0.9, .stained: 0.8, .muddy: 0.4],
                  lowLightBonus: 0.30, windBonus: -0.10, fallingBonus: 0.10, postFrontBonus: -0.15,
                  depth: nil, depthWord: "Surface", technique: "Walk it with a steady rhythm and don't set the hook until you feel weight."),

        Archetype(name: "Hollow-body frog", keywords: ["frog", "hollow", "toad"],
                  minTempC: 18, maxTempC: 33,
                  clarity: [.clear: 0.6, .stained: 0.9, .muddy: 0.8],
                  lowLightBonus: 0.25, windBonus: -0.10, fallingBonus: 0.10, postFrontBonus: -0.10,
                  depth: nil, depthWord: "Surface and over mats", technique: "Walk it across pads and pause in every opening."),

        Archetype(name: "Jigging spoon", keywords: ["spoon", "jigging spoon", "blade bait"],
                  minTempC: 2, maxTempC: 14,
                  clarity: [.clear: 0.95, .stained: 0.6, .muddy: 0.3],
                  lowLightBonus: 0.0, windBonus: 0.0, fallingBonus: 0.05, postFrontBonus: 0.25,
                  depth: 4...15, technique: "Fish it straight down. Lift the rod high and let it flutter back on a tight line."),

        Archetype(name: "Inline spinner", keywords: ["inline", "mepps", "rooster", "spinner"],
                  minTempC: 8, maxTempC: 22,
                  clarity: [.clear: 0.8, .stained: 0.9, .muddy: 0.5],
                  lowLightBonus: 0.10, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.0,
                  depth: 0.3...1.5, technique: "Cast upstream and retrieve just fast enough to turn the blade."),

        Archetype(name: "Live or natural bait", keywords: ["live", "worm", "bait", "minnow", "prawn", "shrimp", "cut"],
                  minTempC: -2, maxTempC: 35,
                  clarity: [.clear: 0.7, .stained: 0.8, .muddy: 0.85],
                  lowLightBonus: 0.05, windBonus: 0.0, fallingBonus: 0.0, postFrontBonus: 0.35,
                  depth: nil, depthWord: "Bottom or suspended", technique: "Use the smallest weight you can get away with, and give them time to eat."),
    ]

    /// Weedless and bass-style families that have no place in the surf or an
    /// estuary. Skipped only when a saltwater or estuary species is targeted.
    private static let freshwaterOnly: Set<String> = [
        "Spinnerbait", "Chatterbait", "Squarebill crankbait", "Skirted jig",
        "Ned rig", "Texas-rigged worm", "Hollow-body frog",
    ]

    // MARK: - Colour selection

    /// Colour is chosen almost entirely by clarity, then nudged by light,
    /// the most reliable rule in lure fishing: match a clear sky and clear
    /// water with natural tones, and low visibility with contrast. Two-tone
    /// names join their colours with "and".
    static func colors(for clarity: WaterClarity, lowLight: Bool) -> [String] {
        switch clarity {
        case .clear:
            return lowLight
                ? ["White", "Pearl shad", "Black and silver"]
                : ["Green pumpkin", "Watermelon", "Natural shad", "Chrome and silver"]
        case .stained:
            return lowLight
                ? ["Chartreuse", "White and chartreuse", "Orange"]
                : ["Chartreuse and white", "Firetiger", "Gold"]
        case .muddy:
            return ["Black and blue", "Black", "High-vis chartreuse", "Red and orange"]
        }
    }

    private static func colorReason(_ clarity: WaterClarity) -> String {
        switch clarity {
        case .clear:   "Clear water suits natural, see-through colours"
        case .stained: "Stained water calls for bright chartreuse"
        case .muddy:   "Muddy water calls for a dark outline and vibration"
        }
    }

    /// "0.5 to 2 m", or "2 to 7 ft" in imperial.
    private static func depthText(_ range: ClosedRange<Double>) -> String {
        let low = Units.depth(m: range.lowerBound)
        let high = Units.depth(m: range.upperBound)
        let lowNumber = low.split(separator: " ").first.map(String.init) ?? low
        return "\(lowNumber) to \(high)"
    }

    // MARK: - Recommend

    /// Ranked suggestions, best first. `ownedGear` should be the angler's
    /// lures and baits; `history` recent catches (their loadouts carry the
    /// lure that actually worked).
    static func recommend(conditions c: Conditions,
                          species: Species?,
                          ownedGear: [OwnedGear] = [],
                          history: [CatchDetail] = [],
                          limit: Int = 5) -> [Suggestion] {

        let palette = colors(for: c.clarity, lowLight: c.isLowLight)
        let speciesBaits = (species?.parsedBaits ?? []).map { $0.lowercased() }
        let lureBox = ownedGear.filter { $0.category == .lure || $0.category == .bait }

        var out: [Suggestion] = []

        // A saltwater or estuary target rules out the bass-only families.
        let saltwater = species?.habitat == .marine || species?.habitat == .brackish

        for a in archetypes {
            if saltwater && freshwaterOnly.contains(a.name) { continue }
            var score = 0.42
            var reasons: [String] = []

            // Water temperature — the strongest gate on lure family.
            if let t = c.waterTempC {
                if t >= a.minTempC && t <= a.maxTempC {
                    score += 0.20
                    reasons.append("\(Units.temperature(t)) suits it")
                } else {
                    // Fall away smoothly rather than hard-excluding.
                    let miss = t < a.minTempC ? a.minTempC - t : t - a.maxTempC
                    score -= min(0.34, miss * 0.045)
                }
            }

            // Water clarity — drives both family and colour.
            let clarityFit = a.clarity[c.clarity] ?? 0.5
            score += (clarityFit - 0.5) * 0.42
            if clarityFit >= 0.85 { reasons.append(colorReason(c.clarity)) }

            // Light, wind, pressure.
            if c.isLowLight && a.lowLightBonus != 0 {
                score += a.lowLightBonus
                if a.lowLightBonus > 0.1 { reasons.append("Low light calls for a bolder lure") }
            }
            if c.isWindy && a.windBonus != 0 {
                score += a.windBonus
                if a.windBonus > 0.1 { reasons.append("Chop on the water helps it") }
            }
            if c.isFalling {
                score += a.fallingBonus
                if a.fallingBonus > 0.1 { reasons.append("Falling pressure has fish chasing") }
            }
            if c.isPostFront {
                score += a.postFrontBonus
                if a.postFrontBonus > 0.15 { reasons.append("High pressure means slow down and finesse") }
            }

            // Does the species' own bait list back this up?
            if !speciesBaits.isEmpty,
               speciesBaits.contains(where: { b in a.keywords.contains(where: { b.contains($0) }) }) {
                score += 0.16
                if let name = species?.commonName { reasons.append("Known producer for \(name)") }
            }

            // Personal history — has this actually caught this angler fish?
            let personal = history.filter { detail in
                guard let lure = detail.gearLoadout?.lure?.lowercased() else { return false }
                return a.keywords.contains { lure.contains($0) }
            }.count
            if personal > 0 {
                score += min(0.22, Double(personal) * 0.045)
                reasons.append("Caught you \(personal) fish before")
            }

            // Tackle box — rank what you can actually throw right now first.
            let owned = lureBox.first { g in
                let n = g.name.lowercased()
                return a.keywords.contains { n.contains($0) }
            }
            if owned != nil {
                score += 0.10
                reasons.append("In your tackle box")
            }

            out.append(Suggestion(
                lure: a.name,
                color: palette.first ?? "Natural",
                technique: a.technique,
                depth: a.depth.map(depthText) ?? a.depthWord ?? "",
                reasons: Array(reasons.prefix(3)),
                score: min(1, max(0, score)),
                ownedName: owned?.displayName,
                personalCatches: personal
            ))
        }

        // Owned gear wins ties so the top of the list is always throwable.
        return out
            .sorted {
                if abs($0.score - $1.score) > 0.001 { return $0.score > $1.score }
                return ($0.isOwned ? 1 : 0) > ($1.isOwned ? 1 : 0)
            }
            .prefix(limit)
            .map { $0 }
    }
}
