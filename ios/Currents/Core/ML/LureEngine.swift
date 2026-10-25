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
        /// The lure colour from the palette. Empty for the natural bait
        /// pick, which has no colour.
        let color: String
        /// The fish's own baits from its record, for the natural bait pick.
        /// Empty for a lure, and when the record names none of its own.
        var baits: [String] = []
        let technique: String
        /// How to fish it in a few words, for a row with room for one line.
        let brief: String
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

        /// The line under the name in place of a colour on the natural bait
        /// pick: "Red bait, white mussel, sardine". Nil for a lure, or when
        /// the record names no baits of its own.
        var baitLine: String? {
            guard !baits.isEmpty else { return nil }
            let list = baits.prefix(3).joined(separator: ", ")
            guard let first = list.first else { return nil }
            return String(first).uppercased() + list.dropFirst()
        }
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
        let brief: String
    }

    private static let archetypes: [Archetype] = [
        Archetype(name: "Spinnerbait", keywords: ["spinner", "spinnerbait", "blade"],
                  minTempC: 10, maxTempC: 26,
                  clarity: [.clear: 0.35, .stained: 1.0, .muddy: 0.85],
                  lowLightBonus: 0.15, windBonus: 0.20, fallingBonus: 0.15, postFrontBonus: -0.10,
                  depth: 0.5...2, technique: "Slow-roll it just fast enough to feel the blade thump.",
                  brief: "Slow-roll it so the blade thumps."),

        Archetype(name: "Chatterbait", keywords: ["chatter", "bladed jig", "vibrating jig"],
                  minTempC: 10, maxTempC: 26,
                  clarity: [.clear: 0.4, .stained: 1.0, .muddy: 0.9],
                  lowLightBonus: 0.10, windBonus: 0.15, fallingBonus: 0.15, postFrontBonus: -0.10,
                  depth: 0.5...2.5, technique: "Steady retrieve, ripping it free whenever it ticks cover.",
                  brief: "Steady retrieve, rip it off cover."),

        Archetype(name: "Lipless crankbait", keywords: ["lipless", "rattle trap", "rat-l-trap", "vib"],
                  minTempC: 6, maxTempC: 20,
                  clarity: [.clear: 0.5, .stained: 0.95, .muddy: 0.85],
                  lowLightBonus: 0.05, windBonus: 0.15, fallingBonus: 0.20, postFrontBonus: -0.05,
                  depth: 1...3, technique: "Yo-yo it over grass. Most bites come as it falls.",
                  brief: "Yo-yo it over grass."),

        Archetype(name: "Squarebill crankbait", keywords: ["crank", "squarebill", "crankbait", "plug"],
                  minTempC: 10, maxTempC: 28,
                  clarity: [.clear: 0.6, .stained: 0.95, .muddy: 0.6],
                  lowLightBonus: 0.10, windBonus: 0.20, fallingBonus: 0.15, postFrontBonus: -0.15,
                  depth: 0.5...2, technique: "Grind it into cover and pause the moment it deflects.",
                  brief: "Bump cover and pause."),

        Archetype(name: "Jerkbait", keywords: ["jerkbait", "minnow", "stickbait", "suspend"],
                  minTempC: 3, maxTempC: 15,
                  clarity: [.clear: 1.0, .stained: 0.55, .muddy: 0.2],
                  lowLightBonus: 0.05, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.20,
                  depth: 1...2.5, technique: "Two twitches then a long pause. The colder it is, the longer the pause.",
                  brief: "Two twitches, then a long pause."),

        Archetype(name: "Skirted jig", keywords: ["jig", "flipping jig", "football"],
                  minTempC: 3, maxTempC: 22,
                  clarity: [.clear: 0.6, .stained: 0.85, .muddy: 1.0],
                  lowLightBonus: 0.05, windBonus: 0.0, fallingBonus: 0.05, postFrontBonus: 0.20,
                  depth: 1...6, technique: "Drag it slowly along the bottom, pausing hard against structure.",
                  brief: "Drag it slowly along the bottom."),

        Archetype(name: "Ned rig", keywords: ["ned", "finesse", "shroom", "trd"],
                  minTempC: 5, maxTempC: 24,
                  clarity: [.clear: 1.0, .stained: 0.6, .muddy: 0.25],
                  lowLightBonus: -0.05, windBonus: -0.10, fallingBonus: -0.05, postFrontBonus: 0.30,
                  depth: 1...5, technique: "Barely move it and let the bottom do the work.",
                  brief: "Barely move it."),

        Archetype(name: "Drop shot", keywords: ["drop shot", "dropshot", "finesse worm"],
                  minTempC: 6, maxTempC: 27,
                  clarity: [.clear: 1.0, .stained: 0.55, .muddy: 0.2],
                  lowLightBonus: -0.05, windBonus: -0.10, fallingBonus: -0.05, postFrontBonus: 0.30,
                  depth: 2...10, technique: "Hold it in place and shake it, keeping the weight pinned to the bottom.",
                  brief: "Shake it in place."),

        Archetype(name: "Texas-rigged worm", keywords: ["worm", "texas", "soft plastic", "creature", "senko"],
                  minTempC: 14, maxTempC: 32,
                  clarity: [.clear: 0.9, .stained: 0.85, .muddy: 0.7],
                  lowLightBonus: 0.0, windBonus: -0.05, fallingBonus: 0.0, postFrontBonus: 0.20,
                  depth: 1...5, technique: "Pitch to cover, let it sink on slack line, lift and drop.",
                  brief: "Pitch to cover, lift and drop."),

        Archetype(name: "Swimbait", keywords: ["swimbait", "paddle tail", "shad", "glide"],
                  minTempC: 8, maxTempC: 26,
                  clarity: [.clear: 1.0, .stained: 0.7, .muddy: 0.35],
                  lowLightBonus: 0.10, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.05,
                  depth: 1...4, technique: "Slow, steady wind at the depth the bait is holding.",
                  brief: "Slow, steady wind."),

        Archetype(name: "Topwater walker", keywords: ["topwater", "walk", "spook", "popper", "surface"],
                  minTempC: 16, maxTempC: 32,
                  clarity: [.clear: 0.9, .stained: 0.8, .muddy: 0.4],
                  lowLightBonus: 0.30, windBonus: -0.10, fallingBonus: 0.10, postFrontBonus: -0.15,
                  depth: nil, depthWord: "Surface", technique: "Walk it with a steady rhythm and don't set the hook until you feel weight.",
                  brief: "Walk it and wait for weight."),

        Archetype(name: "Hollow-body frog", keywords: ["frog", "hollow", "toad"],
                  minTempC: 18, maxTempC: 33,
                  clarity: [.clear: 0.6, .stained: 0.9, .muddy: 0.8],
                  lowLightBonus: 0.25, windBonus: -0.10, fallingBonus: 0.10, postFrontBonus: -0.10,
                  depth: nil, depthWord: "Surface and over mats", technique: "Walk it across pads and pause in every opening.",
                  brief: "Walk it and pause in openings."),

        Archetype(name: "Jigging spoon", keywords: ["spoon", "jigging spoon", "blade bait"],
                  minTempC: 2, maxTempC: 14,
                  clarity: [.clear: 0.95, .stained: 0.6, .muddy: 0.3],
                  lowLightBonus: 0.0, windBonus: 0.0, fallingBonus: 0.05, postFrontBonus: 0.25,
                  depth: 4...15, technique: "Fish it straight down. Lift the rod high and let it flutter back on a tight line.",
                  brief: "Lift it and let it flutter."),

        Archetype(name: "Inline spinner", keywords: ["inline", "mepps", "rooster", "spinner"],
                  minTempC: 8, maxTempC: 22,
                  clarity: [.clear: 0.8, .stained: 0.9, .muddy: 0.5],
                  lowLightBonus: 0.10, windBonus: 0.05, fallingBonus: 0.10, postFrontBonus: 0.0,
                  depth: 0.3...1.5, technique: "Cast across the current and retrieve just fast enough to turn the blade.",
                  brief: "Steady, just turning the blade."),

        Archetype(name: naturalBait, keywords: ["live", "worm", "bait", "minnow", "prawn", "shrimp", "cut"],
                  minTempC: -2, maxTempC: 35,
                  clarity: [.clear: 0.7, .stained: 0.8, .muddy: 0.85],
                  lowLightBonus: 0.05, windBonus: 0.0, fallingBonus: 0.0, postFrontBonus: 0.35,
                  depth: nil, depthWord: "Bottom or suspended", technique: "Use the smallest weight you can get away with, and give them time to eat.",
                  brief: "Go light and give them time."),
    ]

    /// Weedless, bass-style and stream families that have no place in the
    /// surf or an estuary. Skipped only when a saltwater or estuary species is
    /// targeted.
    private static let freshwaterOnly: Set<String> = [
        "Spinnerbait", "Chatterbait", "Squarebill crankbait", "Skirted jig",
        "Ned rig", "Texas-rigged worm", "Hollow-body frog", "Inline spinner",
    ]

    /// The one family that is not a lure.
    static let naturalBait = "Live or natural bait"

    /// Words that make an entry in a species' bait list a lure: every lure
    /// family's keywords except those that also name a natural food ("worm",
    /// "minnow"), plus the general names for lures and flies. Matched as
    /// substrings, so an unclear entry counts as a lure and leaves the
    /// species' picks as they were.
    private static let lureWords: [String] = {
        let food = Set(archetypes.first { $0.name == naturalBait }?.keywords ?? [])
        let families = archetypes
            .filter { $0.name != naturalBait }
            .flatMap(\.keywords)
            .filter { !food.contains($0) }
        return families + ["lure", "fly", "flies", "plug", "pirk", "plastic", "feather", "sabiki",
                           "slug", "streamer", "nymph", "bucktail", "tenya", "rapala", "buzzbait",
                           "teaser", "trolling"]
    }()

    private static func isLure(_ entry: String) -> Bool {
        let text = entry.lowercased()
        return lureWords.contains { text.contains($0) }
    }

    /// The stand-in list the species seed gives fish with no bait record of
    /// their own, with its notes.
    private static let placeholderBaits = ["worms", "small spinners", "soft plastics", "local live bait"]
    private static let placeholderNotes = "General freshwater tactics"

    /// True when the species has a bait list of its own, false for none or
    /// the seed's stand-in list.
    static func hasBaitRecord(_ species: Species) -> Bool {
        let baits = species.parsedBaits
        guard !baits.isEmpty else { return false }
        if species.baitNotes?.hasPrefix(placeholderNotes) == true { return false }
        return baits.map { $0.lowercased() } != placeholderBaits
    }

    /// True when the species' own bait list names natural bait the bait
    /// family knows and no lure, as for galjoen, catfish and carp. Such a fish
    /// is caught on bait, so its picks lead with bait and leave lures out.
    static func isBaitOnly(_ species: Species?) -> Bool {
        guard let species, hasBaitRecord(species),
              let bait = archetypes.first(where: { $0.name == naturalBait }) else { return false }
        let baits = species.parsedBaits.map { $0.lowercased() }
        let named = baits.contains { b in bait.keywords.contains { b.contains($0) } }
        return named && !baits.contains(where: isLure)
    }

    /// The reason given when the species' own bait list backs a family, so a
    /// page can say it once when every pick shares it.
    static func speciesReason(_ name: String) -> String {
        "Known producer for \(name)"
    }

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

    /// What a family's colour has to do. Families not listed in `colorRoles`
    /// are soft plastics and jigs, which want natural food colours. Natural
    /// bait has no colour.
    private enum ColorRole {
        case natural
        case baitfish
        case flash
        case surface
    }

    private static let colorRoles: [String: ColorRole] = [
        "Lipless crankbait": .baitfish, "Squarebill crankbait": .baitfish,
        "Jerkbait": .baitfish, "Swimbait": .baitfish,
        "Spinnerbait": .flash, "Inline spinner": .flash, "Jigging spoon": .flash,
        "Topwater walker": .surface, "Hollow-body frog": .surface,
    ]

    /// The palette colour for a lure family, so picks differ where the
    /// palette allows: soft plastics natural, hard baits like a baitfish,
    /// blades bright, and surface lures a dark shape at low light.
    private static func familyColor(_ name: String, palette: [String],
                                    clarity: WaterClarity, lowLight: Bool) -> String {
        let role = colorRoles[name] ?? .natural
        let wanted: String
        switch (clarity, lowLight) {
        case (.clear, false):
            switch role {
            case .natural: wanted = "Green pumpkin"
            case .baitfish: wanted = "Natural shad"
            case .flash: wanted = "Chrome and silver"
            case .surface: wanted = "Watermelon"
            }
        case (.clear, true):
            switch role {
            case .natural, .baitfish: wanted = "Pearl shad"
            case .flash: wanted = "White"
            case .surface: wanted = "Black and silver"
            }
        case (.stained, false):
            switch role {
            case .natural, .surface: wanted = "Chartreuse and white"
            case .baitfish: wanted = "Firetiger"
            case .flash: wanted = "Gold"
            }
        case (.stained, true):
            switch role {
            case .natural, .surface: wanted = "Chartreuse"
            case .baitfish: wanted = "Orange"
            case .flash: wanted = "White and chartreuse"
            }
        case (.muddy, _):
            switch role {
            case .natural: wanted = "Black and blue"
            case .baitfish: wanted = "Red and orange"
            case .flash: wanted = "High-vis chartreuse"
            case .surface: wanted = "Black"
            }
        }
        // Always one of the palette's own colours, so a pick matches the strip.
        return palette.contains(wanted) ? wanted : palette.first ?? "Natural"
    }

    private static func colorReason(_ clarity: WaterClarity, color: String) -> String {
        switch clarity {
        case .clear:   "\(color) suits clear water"
        case .stained: "\(color) stands out in stained water"
        case .muddy:   "\(color) shows up in muddy water"
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
        // The fish's own natural baits, named on the bait pick.
        var ownBaits: [String] = []
        if let species, hasBaitRecord(species) {
            ownBaits = species.parsedBaits.filter { entry in !isLure(entry) }
        }

        var out: [Suggestion] = []

        // A saltwater or estuary target rules out the bass-only families.
        let saltwater = species?.habitat == .marine || species?.habitat == .brackish
        // A fish caught only on bait gets the bait pick alone.
        let baitOnly = isBaitOnly(species)

        for a in archetypes {
            if saltwater && freshwaterOnly.contains(a.name) { continue }
            let isBait = a.name == naturalBait
            if baitOnly && !isBait { continue }
            var score = 0.42
            // Most specific first, since a page may show only the first: the
            // species' own baits, then light, wind and pressure, then clarity.
            // The water temperature reads the same for every lure in range, so
            // it goes last.
            var reasons: [String] = []
            let color = isBait ? "" : familyColor(a.name, palette: palette, clarity: c.clarity, lowLight: c.isLowLight)

            // Does the species' own bait list back this up?
            if !speciesBaits.isEmpty,
               speciesBaits.contains(where: { b in a.keywords.contains(where: { b.contains($0) }) }) {
                score += 0.16
                if let name = species?.commonName { reasons.append(speciesReason(name)) }
            }

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

            // Water clarity — drives both family and colour.
            let clarityFit = a.clarity[c.clarity] ?? 0.5
            score += (clarityFit - 0.5) * 0.42
            if clarityFit >= 0.85 {
                reasons.append(isBait ? "Its scent carries in \(c.clarity.label.lowercased()) water"
                                      : colorReason(c.clarity, color: color))
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

            out.append(Suggestion(
                lure: a.name,
                color: color,
                baits: isBait ? ownBaits : [],
                technique: a.technique,
                brief: a.brief,
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
