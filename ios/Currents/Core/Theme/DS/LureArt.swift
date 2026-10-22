import SwiftUI
import UIKit

/// Square rounded thumbnail for a lure, bait or tackle suggestion. Shows the
/// bundled illustration (asset `lure_<key>`, made by
/// scripts/generate_lure_art.py) on the same neutral plate the fish art sits
/// on, otherwise a neutral placeholder: one SF Symbol for the lure's family.
struct LureArtView: View {
    let name: String
    var size: CGFloat = 56

    init(name: String, size: CGFloat = 56) {
        self.name = name
        self.size = size
    }

    private var key: String? { LureArt.key(for: name) }

    private var radius: CGFloat { size < 48 ? size * 0.25 : DS.Radius.thumb }

    var body: some View {
        Group {
            if let key, LureArt.hasArt(for: key) {
                ThumbView(tint: Color.gray, size: size) {
                    Image(LureArt.assetName(for: key))
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.1)
                }
            } else {
                ZStack {
                    Color.dsFill2
                    ThumbSymbol(systemImage: LureArt.symbol(for: key), tint: .dsText2, size: size)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(.isImage)
    }
}

/// Maps free-text lure and bait names (LureEngine archetypes, species bait
/// lists, gear types) to a small fixed set of art keys. Rules are checked in
/// order and the first keyword hit wins, so specific phrases sit above the
/// generic ones ("cut squid" is squid, "cut bait" is cut bait).
enum LureArt {
    enum Family {
        case blade, hardBait, surface, jig, softPlastic, metal, fly, trolling
        case baitfish, seafood, worm, insect, grocery, eggs

        var symbol: String {
            switch self {
            case .blade: return "wind"
            case .hardBait: return "fish"
            case .surface: return "water.waves"
            case .jig: return "arrow.down.to.line"
            case .softPlastic: return "scribble.variable"
            case .metal: return "drop"
            case .fly: return "ladybug"
            case .trolling: return "sailboat"
            case .baitfish: return "fish.fill"
            case .seafood: return "fork.knife"
            case .worm: return "scribble"
            case .insect: return "ant"
            case .grocery: return "leaf"
            case .eggs: return "circle.hexagongrid"
            }
        }
    }

    private struct Rule {
        let key: String
        let family: Family
        let keywords: [String]
    }

    /// Keywords are lower case, singular and space separated, matched as whole
    /// words against the normalised name. scripts/generate_lure_art.py reads
    /// this table, so keep one `Rule(...)` per entry.
    private static let rules: [Rule] = [
        // Artificial lures first: "gulp swimming mullet" is a lure, not a mullet.
        Rule(key: "fly", family: .fly, keywords: ["fly", "dry fly", "nymph", "streamer", "fly pattern", "crab pattern", "woolly bugger", "clouser"]),
        Rule(key: "sabiki", family: .jig, keywords: ["sabiki", "bait jig", "flasher rig"]),
        Rule(key: "frog", family: .surface, keywords: ["frog", "toad", "hollow body"]),
        Rule(key: "spinnerbait", family: .blade, keywords: ["spinnerbait", "buzzbait", "buzz bait"]),
        Rule(key: "chatterbait", family: .blade, keywords: ["chatterbait", "chatter", "bladed jig", "vibrating jig"]),
        Rule(key: "inline_spinner", family: .blade, keywords: ["spinner", "inline spinner", "in line spinner", "mepps", "rooster tail", "bucktail spinner"]),
        Rule(key: "topwater", family: .surface, keywords: ["topwater", "top water", "surface lure", "walker", "walking bait", "spook", "popper", "chugger", "prop bait", "stickbait", "pencil"]),
        Rule(key: "lipless_crankbait", family: .hardBait, keywords: ["lipless", "rattle trap", "rattletrap", "rat l trap", "vib", "vibe", "blade bait"]),
        Rule(key: "jerkbait", family: .hardBait, keywords: ["jerkbait", "twitchbait", "rapala", "minnow plug", "sinking minnow", "swimming minnow", "floating minnow", "hard body", "hardbody", "suspending"]),
        Rule(key: "swimbait", family: .softPlastic, keywords: ["swimbait", "swim bait", "paddle tail", "paddletail", "glide bait", "glidebait", "swimming mullet", "soft plastic shad"]),
        Rule(key: "drop_shot", family: .softPlastic, keywords: ["drop shot", "dropshot", "finesse worm"]),
        Rule(key: "ned_rig", family: .softPlastic, keywords: ["ned", "ned rig", "shaky head", "shakey head", "mushroom head"]),
        Rule(key: "plastic_worm", family: .softPlastic, keywords: ["plastic worm", "soft plastic worm", "texas", "texas rigged", "senko", "stick worm", "creature bait"]),
        Rule(key: "jigging_spoon", family: .metal, keywords: ["jigging spoon", "ice jigging spoon", "metal jig", "vertical jig", "butterfly jig", "deep jig", "slow pitch", "pirk", "metal slug", "slug"]),
        Rule(key: "spoon", family: .metal, keywords: ["spoon", "casting spoon", "trolling spoon", "weedless spoon"]),
        Rule(key: "crankbait", family: .hardBait, keywords: ["crankbait", "crank", "squarebill", "square bill", "plug", "diving plug", "deep diver"]),
        Rule(key: "trolling_lure", family: .trolling, keywords: ["trolling", "trolling lure", "skirted lure", "skirted ballyhoo", "trolling skirt", "trolling feather", "konahead", "kona"]),
        Rule(key: "soft_plastic", family: .softPlastic, keywords: ["soft plastic", "plastic", "grub", "curly tail", "jighead", "jig head", "small jig", "micro jig", "crappie jig", "road runner", "jig and minnow", "jig and grub", "tube", "underspin", "gulp"]),
        Rule(key: "jig", family: .jig, keywords: ["jig", "skirted jig", "flipping jig", "football jig", "swim jig", "bucktail", "feathered jig", "tenya"]),
        // Natural baits: specific animals before the generic live and cut baits.
        Rule(key: "squid", family: .seafood, keywords: ["squid", "chokka", "calamari", "cuttlefish", "octopus"]),
        Rule(key: "clam", family: .seafood, keywords: ["clam", "mussel", "white mussel", "pipi", "cockle", "oyster", "barnacle", "limpet"]),
        Rule(key: "sand_flea", family: .seafood, keywords: ["sand flea", "mole crab", "sand crab"]),
        Rule(key: "crayfish", family: .seafood, keywords: ["crayfish", "crawfish", "crawdad", "yabby", "yabbie"]),
        Rule(key: "crab", family: .seafood, keywords: ["crab", "fiddler crab", "peeler crab"]),
        Rule(key: "shrimp", family: .seafood, keywords: ["shrimp", "prawn", "sand prawn", "mud prawn", "krill"]),
        Rule(key: "salmon_eggs", family: .eggs, keywords: ["egg", "roe", "salmon egg", "egg sack", "spawn sack"]),
        Rule(key: "worm", family: .worm, keywords: ["worm", "nightcrawler", "crawler", "bloodworm", "ragworm", "lugworm", "wonderworm", "waxworm", "mealworm", "redworm", "maggot", "leech", "leeche"]),
        Rule(key: "insect", family: .insect, keywords: ["cricket", "grasshopper", "hopper", "insect", "beetle", "cicada"]),
        Rule(key: "corn", family: .grocery, keywords: ["corn", "sweetcorn", "sweet corn", "maize", "hemp", "hemp seed", "particle"]),
        Rule(key: "dough_bait", family: .grocery, keywords: ["dough", "dough bait", "boilie", "boily", "pellet", "powerbait", "power bait", "punch bait", "stink bait", "dip bait", "paste"]),
        Rule(key: "bread", family: .grocery, keywords: ["bread", "bread flake", "crust"]),
        Rule(key: "cut_bait", family: .seafood, keywords: ["cut", "cut bait", "strip", "strip bait", "chunk", "chunk bait", "fillet", "fish head", "tuna head", "chicken liver", "liver", "chicken innard", "meat"]),
        Rule(key: "baitfish", family: .baitfish, keywords: ["live", "live bait", "natural bait", "baitfish", "bait fish", "minnow", "sardine", "pilchard", "herring", "mullet", "mackerel", "anchovy", "shad", "shiner", "sucker", "bunker", "menhaden", "bluegill", "perch", "pinfish", "ballyhoo", "eel", "sandeel", "sand eel", "small fish", "whole fish", "dead bait", "deadbait", "stinger"]),
    ]

    /// Every art key, in rule order.
    static var keys: [String] { rules.map(\.key) }

    /// The art key for a free-text lure or bait name, or nil when nothing fits.
    static func key(for name: String) -> String? {
        let text = " " + normalised(name) + " "
        for rule in rules where rule.keywords.contains(where: { text.contains(" " + $0 + " ") }) {
            return rule.key
        }
        return nil
    }

    static func assetName(for key: String) -> String { "lure_" + key }

    static func hasArt(for key: String) -> Bool { UIImage(named: assetName(for: key)) != nil }

    /// Placeholder symbol: the key's family, or a generic fishing glyph.
    static func symbol(for key: String?) -> String {
        guard let key, let rule = rules.first(where: { $0.key == key }) else { return "figure.fishing" }
        return rule.family.symbol
    }

    /// Lower case, letters and digits only, each word made singular.
    private static func normalised(_ name: String) -> String {
        let words = name.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map { singular(String($0)) }
        return words.joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3, word != "texas" else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if ["ss", "us", "is"].contains(where: { word.hasSuffix($0) }) { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }
}
