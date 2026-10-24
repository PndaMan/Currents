import SwiftUI

enum BadgeRarity: Int, CaseIterable {
    case common = 0
    case uncommon = 1
    case rare = 2
    case epic = 3
    case legendary = 4
    /// The tier above legendary — reserved for the truly absurd (and the
    /// secret ones).
    case mythic = 5

    /// Each tier's hue. Common is bronze rather than grey, so an earned
    /// common medal never reads as a locked one. The medal deepens its rim
    /// and symbol on light pages; use `DS.ink(color)` where it is text.
    var color: Color {
        switch self {
        case .common:    return Self.bronze
        case .uncommon:  return .dsScoreGood
        case .rare:      return Self.ocean
        case .epic:      return Self.violet
        case .legendary: return .dsScoreFair
        case .mythic:    return Self.coral
        }
    }

    private static let bronze = Color(red: 0.80, green: 0.50, blue: 0.20) // ui-lint: allow, badge rarity hue
    private static let ocean = Color(red: 0.20, green: 0.66, blue: 0.90) // ui-lint: allow, badge rarity hue
    private static let violet = Color(red: 0.66, green: 0.36, blue: 0.88) // ui-lint: allow, badge rarity hue
    private static let coral = Color(red: 0.96, green: 0.27, blue: 0.42) // ui-lint: allow, badge rarity hue

    var label: String {
        switch self {
        case .common:    return "Common"
        case .uncommon:  return "Uncommon"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        case .mythic:    return "Mythic"
        }
    }
}

/// A wearable profile title. Each achievement unlocks a title with its OWN
/// name ("Century" unlocks "Centurion"). The achievement is the
/// provenance, shown when the worn title is tapped. Colours follow the
/// unlocking achievement's rarity.
struct TitleFlair: Identifiable {
    let achievement: String   // the BadgeDefinition title that unlocks it
    let name: String          // what's worn under the profile name
    let rarity: BadgeRarity
    let icon: String          // the achievement's symbol, for the detail modal
    var id: String { achievement }

    /// The line under a worn title; nothing when the title is the
    /// achievement's own name.
    var unlockLine: String? {
        name == achievement ? nil : "Unlocked by \(BadgeDefinition.displayName(for: achievement))"
    }

    /// The unlocking badge, for BadgeDetailView. `earned: true` because a worn
    /// title is proof of unlock by definition.
    var badge: BadgeDefinition {
        BadgeDefinition(icon: icon, title: achievement, rarity: rarity, earned: true)
    }

    /// Resolve a stored profile title — matches the flair name, and falls back
    /// to the achievement name so titles saved before the rename still render.
    static func resolve(_ stored: String) -> TitleFlair? {
        all.first { $0.name == stored || $0.achievement == stored }
    }

    static let all: [TitleFlair] = [
        // Common
        .init(achievement: "First Catch", name: "First Hook", rarity: .common, icon: "fish.fill"),
        .init(achievement: "Snap Happy", name: "Shutterbug", rarity: .common, icon: "camera.fill"),
        .init(achievement: "Marked It", name: "Pathfinder", rarity: .common, icon: "mappin.circle.fill"),
        .init(achievement: "Good Sport", name: "Good Sport", rarity: .common, icon: "arrow.uturn.backward"),
        .init(achievement: "Keeper", name: "Keeper", rarity: .common, icon: "scalemass"),
        .init(achievement: "Doubleheader", name: "Doubleheader", rarity: .common, icon: "fish.fill"),
        .init(achievement: "Weekend Warrior", name: "Weekend Warrior", rarity: .common, icon: "tent.fill"),
        // Uncommon
        .init(achievement: "10 Club", name: "Rising Angler", rarity: .uncommon, icon: "trophy.fill"),
        .init(achievement: "Quarter Century", name: "Regular", rarity: .uncommon, icon: "star.leadinghalf.filled"),
        .init(achievement: "5 Species", name: "Species Scout", rarity: .uncommon, icon: "leaf.fill"),
        .init(achievement: "Explorer", name: "Explorer", rarity: .uncommon, icon: "globe.americas.fill"),
        .init(achievement: "Photographer", name: "Photographer", rarity: .uncommon, icon: "camera.fill"),
        .init(achievement: "Hot Streak", name: "On a Roll", rarity: .uncommon, icon: "flame.fill"),
        .init(achievement: "Conservationist", name: "Conservationist", rarity: .uncommon, icon: "arrow.uturn.backward.circle.fill"),
        .init(achievement: "Hat Trick", name: "Hat Trick", rarity: .uncommon, icon: "fish.fill"),
        .init(achievement: "Solid Fish", name: "Rod Bender", rarity: .uncommon, icon: "scalemass"),
        .init(achievement: "Four Seasons", name: "Four Seasons", rarity: .uncommon, icon: "calendar"),
        // Rare
        .init(achievement: "50 Catches", name: "Seasoned Angler", rarity: .rare, icon: "star.fill"),
        .init(achievement: "Night Owl", name: "Night Owl", rarity: .rare, icon: "moon.fill"),
        .init(achievement: "Dawn Patrol", name: "Early Riser", rarity: .rare, icon: "sun.max.fill"),
        .init(achievement: "Heavy Hitter", name: "Heavy Hitter", rarity: .rare, icon: "scalemass"),
        .init(achievement: "Long One", name: "Longliner", rarity: .rare, icon: "ruler"),
        .init(achievement: "Diversified", name: "Naturalist", rarity: .rare, icon: "leaf.fill"),
        .init(achievement: "On Fire", name: "Firebrand", rarity: .rare, icon: "flame.fill"),
        .init(achievement: "Full Stringer", name: "Full Stringer", rarity: .rare, icon: "fish.fill"),
        .init(achievement: "Wanderer", name: "Wanderer", rarity: .rare, icon: "map.fill"),
        .init(achievement: "Sharp Eye", name: "Sharp Eye", rarity: .rare, icon: "gauge.medium"),
        .init(achievement: "Release Artist", name: "Release Artist", rarity: .rare, icon: "arrow.uturn.backward.circle.fill"),
        // Epic
        .init(achievement: "Century", name: "Centurion", rarity: .epic, icon: "crown.fill"),
        .init(achievement: "Nomad", name: "Nomad", rarity: .epic, icon: "globe.americas.fill"),
        .init(achievement: "Perfect Read", name: "Water Whisperer", rarity: .epic, icon: "gauge.medium"),
        .init(achievement: "Year-Round", name: "All-Season Angler", rarity: .epic, icon: "calendar.badge.checkmark"),
        .init(achievement: "Monster", name: "Monster Hunter", rarity: .epic, icon: "scalemass"),
        .init(achievement: "Portfolio", name: "Curator", rarity: .epic, icon: "camera.fill"),
        .init(achievement: "Big Day", name: "Big Day Hero", rarity: .epic, icon: "sun.max.fill"),
        .init(achievement: "Relentless", name: "Relentless", rarity: .epic, icon: "flame.fill"),
        .init(achievement: "Meter Class", name: "Meter Class", rarity: .epic, icon: "ruler"),
        .init(achievement: "Collector", name: "Collector", rarity: .epic, icon: "leaf.fill"),
        // Legendary
        .init(achievement: "Double Century", name: "Double Centurion", rarity: .legendary, icon: "star.circle.fill"),
        .init(achievement: "500 Club", name: "Old Salt", rarity: .legendary, icon: "rosette"),
        .init(achievement: "Species Master", name: "Master of Species", rarity: .legendary, icon: "crown.fill"),
        .init(achievement: "Unstoppable", name: "Unstoppable", rarity: .legendary, icon: "flame.fill"),
        .init(achievement: "Trophy Hunter", name: "Trophy Hunter", rarity: .legendary, icon: "scalemass"),
        .init(achievement: "Meter Monster", name: "Meter Monster", rarity: .legendary, icon: "ruler"),
        .init(achievement: "Water Guardian", name: "Water Guardian", rarity: .legendary, icon: "arrow.uturn.backward.circle.fill"),
        .init(achievement: "Shutter Legend", name: "Shutter Legend", rarity: .legendary, icon: "camera.fill"),
        .init(achievement: "World Traveler", name: "World Traveler", rarity: .legendary, icon: "globe.americas.fill"),
        // Mythic
        .init(achievement: "Thousand Club", name: "Thousand Legend", rarity: .mythic, icon: "medal.fill"),
        .init(achievement: "Leviathan", name: "Leviathan", rarity: .mythic, icon: "scalemass"),
        .init(achievement: "Master of All Waters", name: "Master of All Waters", rarity: .mythic, icon: "crown.fill"),
        .init(achievement: "Eternal Flame", name: "Eternal Flame", rarity: .mythic, icon: "flame.fill"),
        .init(achievement: "Bass Daddy", name: "Bass Daddy", rarity: .mythic, icon: "fish.fill"),
        .init(achievement: "Patron", name: "Patron", rarity: .mythic, icon: "heart.fill"),
    ]
}

// MARK: - Badge rules

/// What a badge counts. A badge is earned once its metric reaches the target.
enum BadgeMetric {
    case catches, species, spots, released, photos
    case weightKg, lengthCm, biteScore, months, bestDay, streakWeeks
    case weekend, night, dawn
    /// Unlocked outside the logbook (the Bass Daddy code).
    case secret
    /// Left a tip of any size.
    case supporter

    /// Kept out of locked lists and counts until earned.
    var isHidden: Bool { self == .secret || self == .supporter }

    /// Earned or not, with no count in between.
    var isYesNo: Bool {
        switch self {
        case .weekend, .night, .dawn, .secret, .supporter: return true
        default: return false
        }
    }

    var group: BadgeGroup {
        switch self {
        case .catches:              return .catches
        case .species:              return .species
        case .weightKg, .lengthCm:  return .size
        case .spots:                return .spots
        case .bestDay:              return .bigDays
        case .streakWeeks:          return .streaks
        case .released:             return .releases
        case .photos:               return .photos
        case .weekend, .night, .dawn, .months: return .timing
        case .biteScore:            return .biteScore
        case .secret, .supporter:   return .secret
        }
    }
}

/// The shelves of the achievements page, in page order.
enum BadgeGroup: Int, CaseIterable {
    case catches, species, size, spots, bigDays, streaks, releases, photos, timing, biteScore, secret

    var title: String {
        switch self {
        case .catches:   return "Catches"
        case .species:   return "Species"
        case .size:      return "Big fish"
        case .spots:     return "Spots"
        case .bigDays:   return "Big days"
        case .streaks:   return "Streaks"
        case .releases:  return "Releases"
        case .photos:    return "Photos"
        case .timing:    return "Times and seasons"
        case .biteScore: return "Bite score"
        case .secret:    return "Secret"
        }
    }
}

/// The rule behind one badge: its look, what it counts and the target.
struct BadgeSpec {
    let title: String
    let icon: String
    let rarity: BadgeRarity
    let metric: BadgeMetric
    let target: Double

    /// The name people read. `title` stays the key.
    var displayName: String { BadgeDefinition.displayName(for: title) }
}

struct BadgeDefinition: Identifiable {
    let icon: String
    let title: String
    let rarity: BadgeRarity
    let earned: Bool
    /// Hidden badges (easter eggs) stay invisible until earned — they never
    /// appear in locked lists or counts.
    var hidden: Bool = false
    /// When it was earned: the date of the catch that reached the target.
    /// Nil while locked, and when the date is not known (a friend's badge,
    /// a worn title).
    var earnedAt: Date? = nil

    var id: String { title }

    /// The name people read: sentence case and British spelling ("Metre
    /// monster"). `title` is left as it was, because it is the key that
    /// TitleFlair, Game Center and stored profile titles look badges up by.
    var displayName: String { Self.displayName(for: title) }

    /// The display name for a badge title, also for titles held elsewhere
    /// (a worn title's unlocking badge, a friend's badge).
    static func displayName(for title: String) -> String {
        if let fixed = displayNameOverrides[title] { return fixed }
        guard let first = title.first else { return title }
        return String(first) + title.dropFirst().lowercased()
    }

    private static let displayNameOverrides: [String: String] = [
        "Meter Class": "Metre class",
        "Meter Monster": "Metre monster",
        "World Traveler": "World traveller",
        // A persona's name, not a phrase.
        "Bass Daddy": "Bass Daddy",
    ]

    /// The rule this badge follows, nil for a title BadgeDefinition does not know.
    var spec: BadgeSpec? { Self.specsByTitle[title] }

    var group: BadgeGroup { spec?.metric.group ?? .secret }

    /// "Long One, rare, earned 12 October 2026" for VoiceOver.
    var accessibilityLabel: String {
        let state: String
        if let earnedAt {
            state = "earned \(LogbookFormat.fullDate(earnedAt))"
        } else {
            state = earned ? "earned" : "not earned yet"
        }
        return "\(displayName), \(rarity.label.lowercased()), \(state)"
    }

    /// The secret Bass Daddy unlock — typing 90210 into the friend-code box.
    /// Stored locally; once unlocked it's yours forever.
    static var bassDaddyUnlocked: Bool {
        UserDefaults.standard.bool(forKey: "bassDaddyUnlocked")
    }
    /// When Bass Daddy was unlocked; nil for unlocks from before the date was kept.
    static var bassDaddyUnlockedAt: Date? {
        guard bassDaddyUnlocked else { return nil }
        return UserDefaults.standard.object(forKey: "bassDaddyUnlockedAt") as? Date
    }
    static func unlockBassDaddy() {
        if !bassDaddyUnlocked {
            UserDefaults.standard.set(Date.now, forKey: "bassDaddyUnlockedAt")
        }
        UserDefaults.standard.set(true, forKey: "bassDaddyUnlocked")
    }

    /// When the first tip went through; tips counted before the date was
    /// kept fall back to the count alone.
    static var supporterSince: Date? {
        UserDefaults.standard.object(forKey: "supporterSince") as? Date
    }
    static var isSupporter: Bool {
        supporterSince != nil || UserDefaults.standard.integer(forKey: "tipJarCount") > 0
    }
    static func markSupporter() {
        guard supporterSince == nil else { return }
        UserDefaults.standard.set(Date.now, forKey: "supporterSince")
    }

    /// The secret badge shows a quote instead of how it is earned.
    static let bassDaddyQuote = "My rod is my sword, the water my kingdom, and every bass bows before the throne."
    static let bassDaddyQuoteBy = "Bass Daddy"
    var isSecretQuote: Bool { title == "Bass Daddy" }

    /// A friendly one-liner explaining how the badge is earned, shown in the
    /// tap-to-open detail modal.
    var explanation: String {
        // Sizes and hours follow the units and 24-hour settings.
        if let spec {
            let hour = { (h: Int) in ForecastFormat.hour(h, use24: ForecastFormat.use24) }
            switch spec.metric {
            case .weightKg: return "Land a fish weighing \(Units.weight(kg: spec.target)) or more."
            case .lengthCm: return "Land a fish \(Units.length(cm: spec.target)) or longer."
            case .night: return "Log a catch late at night, between \(hour(22)) and \(hour(5))."
            case .dawn: return "Log a catch at first light, between \(hour(5)) and \(hour(7))."
            default: break
            }
        }
        switch title {
        case "First Catch":     return "Log your very first catch in Currents."
        case "Snap Happy":      return "Add a photo to 3 of your catches."
        case "Marked It":       return "Log a catch at one of your saved spots."
        case "Good Sport":      return "Release 3 catches back to the water."
        case "Doubleheader":    return "Log 2 catches in a single day."
        case "Weekend Warrior": return "Log a catch on a Saturday or Sunday."
        case "10 Club":         return "Log 10 catches."
        case "Quarter Century": return "Log 25 catches."
        case "5 Species":       return "Catch 5 different species."
        case "Explorer":        return "Log catches at 3 different saved spots."
        case "Photographer":    return "Add photos to 10 of your catches."
        case "Hot Streak":      return "Log a catch in 2 back-to-back weeks."
        case "Conservationist": return "Release 10 catches."
        case "Hat Trick":       return "Log 3 catches in a single day."
        case "Four Seasons":    return "Log catches in 4 different months of the year."
        case "50 Catches":      return "Log 50 catches."
        case "Diversified":     return "Catch 10 different species."
        case "On Fire":         return "Keep a weekly fishing streak alive for 4 weeks."
        case "Full Stringer":   return "Log 5 catches in a single day."
        case "Wanderer":        return "Log catches at 5 different saved spots."
        case "Sharp Eye":       return "Land a catch when the bite score was 75 or higher."
        case "Release Artist":  return "Release 25 catches."
        case "Century":         return "Log 100 catches."
        case "Nomad":           return "Log catches at 8 different saved spots."
        case "Perfect Read":    return "Land a catch when the bite score was 85 or higher."
        case "Year-Round":      return "Log catches in 8 different months of the year."
        case "Portfolio":       return "Add photos to 35 of your catches."
        case "Big Day":         return "Log 8 catches in a single day."
        case "Relentless":      return "Keep a weekly fishing streak alive for 8 weeks."
        case "Collector":       return "Catch 15 different species."
        case "Double Century":  return "Log 200 catches."
        case "500 Club":        return "Log 500 catches."
        case "Species Master":  return "Catch 25 different species."
        case "Unstoppable":     return "Keep a weekly fishing streak alive for 12 weeks."
        case "Water Guardian":  return "Release 100 catches."
        case "Shutter Legend":  return "Add photos to 100 of your catches."
        case "World Traveler":  return "Log catches at 15 different saved spots."
        case "Thousand Club":   return "Log 1,000 catches. A life on the water."
        case "Master of All Waters": return "Catch 50 different species."
        case "Eternal Flame":   return "Keep a weekly fishing streak alive for 26 weeks, half a year."
        case "Bass Daddy":      return "“\(Self.bassDaddyQuote)” \(Self.bassDaddyQuoteBy)"
        case "Patron":          return "You left a tip in Currents. Thank you so much."
        default:                return "Keep fishing to unlock this badge."
        }
    }

    /// Every badge, rarity by rarity. The one place a badge's target lives:
    /// compute, the progress text and the achievements page all read it.
    static let specs: [BadgeSpec] = [
        // Common
        .init(title: "First Catch", icon: "fish.fill", rarity: .common, metric: .catches, target: 1),
        .init(title: "Snap Happy", icon: "camera.fill", rarity: .common, metric: .photos, target: 3),
        .init(title: "Marked It", icon: "mappin.circle.fill", rarity: .common, metric: .spots, target: 1),
        .init(title: "Good Sport", icon: "arrow.uturn.backward", rarity: .common, metric: .released, target: 3),
        .init(title: "Keeper", icon: "scalemass", rarity: .common, metric: .weightKg, target: 1),
        .init(title: "Doubleheader", icon: "fish.fill", rarity: .common, metric: .bestDay, target: 2),
        .init(title: "Weekend Warrior", icon: "tent.fill", rarity: .common, metric: .weekend, target: 1),

        // Uncommon
        .init(title: "10 Club", icon: "trophy.fill", rarity: .uncommon, metric: .catches, target: 10),
        .init(title: "Quarter Century", icon: "star.leadinghalf.filled", rarity: .uncommon, metric: .catches, target: 25),
        .init(title: "5 Species", icon: "leaf.fill", rarity: .uncommon, metric: .species, target: 5),
        .init(title: "Explorer", icon: "globe.americas.fill", rarity: .uncommon, metric: .spots, target: 3),
        .init(title: "Photographer", icon: "camera.fill", rarity: .uncommon, metric: .photos, target: 10),
        .init(title: "Hot Streak", icon: "flame.fill", rarity: .uncommon, metric: .streakWeeks, target: 2),
        .init(title: "Conservationist", icon: "arrow.uturn.backward.circle.fill", rarity: .uncommon, metric: .released, target: 10),
        .init(title: "Hat Trick", icon: "fish.fill", rarity: .uncommon, metric: .bestDay, target: 3),
        .init(title: "Solid Fish", icon: "scalemass", rarity: .uncommon, metric: .weightKg, target: 2),
        .init(title: "Four Seasons", icon: "calendar", rarity: .uncommon, metric: .months, target: 4),

        // Rare
        .init(title: "50 Catches", icon: "star.fill", rarity: .rare, metric: .catches, target: 50),
        .init(title: "Night Owl", icon: "moon.fill", rarity: .rare, metric: .night, target: 1),
        .init(title: "Dawn Patrol", icon: "sun.max.fill", rarity: .rare, metric: .dawn, target: 1),
        .init(title: "Heavy Hitter", icon: "scalemass", rarity: .rare, metric: .weightKg, target: 5),
        .init(title: "Long One", icon: "ruler", rarity: .rare, metric: .lengthCm, target: 50),
        .init(title: "Diversified", icon: "leaf.fill", rarity: .rare, metric: .species, target: 10),
        .init(title: "On Fire", icon: "flame.fill", rarity: .rare, metric: .streakWeeks, target: 4),
        .init(title: "Full Stringer", icon: "fish.fill", rarity: .rare, metric: .bestDay, target: 5),
        .init(title: "Wanderer", icon: "map.fill", rarity: .rare, metric: .spots, target: 5),
        .init(title: "Sharp Eye", icon: "gauge.medium", rarity: .rare, metric: .biteScore, target: 75),
        .init(title: "Release Artist", icon: "arrow.uturn.backward.circle.fill", rarity: .rare, metric: .released, target: 25),

        // Epic
        .init(title: "Century", icon: "crown.fill", rarity: .epic, metric: .catches, target: 100),
        .init(title: "Nomad", icon: "globe.americas.fill", rarity: .epic, metric: .spots, target: 8),
        .init(title: "Perfect Read", icon: "gauge.medium", rarity: .epic, metric: .biteScore, target: 85),
        .init(title: "Year-Round", icon: "calendar.badge.checkmark", rarity: .epic, metric: .months, target: 8),
        .init(title: "Monster", icon: "scalemass", rarity: .epic, metric: .weightKg, target: 12),
        .init(title: "Portfolio", icon: "camera.fill", rarity: .epic, metric: .photos, target: 35),
        .init(title: "Big Day", icon: "sun.max.fill", rarity: .epic, metric: .bestDay, target: 8),
        .init(title: "Relentless", icon: "flame.fill", rarity: .epic, metric: .streakWeeks, target: 8),
        .init(title: "Meter Class", icon: "ruler", rarity: .epic, metric: .lengthCm, target: 80),
        .init(title: "Collector", icon: "leaf.fill", rarity: .epic, metric: .species, target: 15),

        // Legendary
        .init(title: "Double Century", icon: "star.circle.fill", rarity: .legendary, metric: .catches, target: 200),
        .init(title: "500 Club", icon: "rosette", rarity: .legendary, metric: .catches, target: 500),
        .init(title: "Species Master", icon: "crown.fill", rarity: .legendary, metric: .species, target: 25),
        .init(title: "Unstoppable", icon: "flame.fill", rarity: .legendary, metric: .streakWeeks, target: 12),
        .init(title: "Trophy Hunter", icon: "scalemass", rarity: .legendary, metric: .weightKg, target: 30),
        .init(title: "Meter Monster", icon: "ruler", rarity: .legendary, metric: .lengthCm, target: 100),
        .init(title: "Water Guardian", icon: "arrow.uturn.backward.circle.fill", rarity: .legendary, metric: .released, target: 100),
        .init(title: "Shutter Legend", icon: "camera.fill", rarity: .legendary, metric: .photos, target: 100),
        .init(title: "World Traveler", icon: "globe.americas.fill", rarity: .legendary, metric: .spots, target: 15),

        // Mythic
        .init(title: "Thousand Club", icon: "medal.fill", rarity: .mythic, metric: .catches, target: 1000),
        .init(title: "Leviathan", icon: "scalemass", rarity: .mythic, metric: .weightKg, target: 50),
        .init(title: "Master of All Waters", icon: "crown.fill", rarity: .mythic, metric: .species, target: 50),
        .init(title: "Eternal Flame", icon: "flame.fill", rarity: .mythic, metric: .streakWeeks, target: 26),
        .init(title: "Bass Daddy", icon: "fish.fill", rarity: .mythic, metric: .secret, target: 1),
        .init(title: "Patron", icon: "heart.fill", rarity: .mythic, metric: .supporter, target: 1),
    ]

    static let specsByTitle: [String: BadgeSpec] =
        Dictionary(uniqueKeysWithValues: specs.map { ($0.title, $0) })

    /// `streakWeeks` is the live streak (see `streakWeeks(from:)`); streak
    /// badges are judged on the longest run ever, so they stay earned after
    /// a streak ends.
    static func compute(from catches: [CatchDetail], streakWeeks: Int) -> [BadgeDefinition] {
        badges(from: BadgeMetrics(catches: catches, streakWeeks: streakWeeks))
    }

    /// The badges for metrics already tallied, so a page that also shows
    /// progress tallies the catches once.
    static func badges(from metrics: BadgeMetrics) -> [BadgeDefinition] {
        specs.map { spec in
            let earned = metrics.isEarned(spec)
            return BadgeDefinition(icon: spec.icon, title: spec.title, rarity: spec.rarity,
                                   earned: earned, hidden: spec.metric.isHidden,
                                   earnedAt: earned ? metrics.earnedAt[spec.title] : nil)
        }
    }

    /// The badges computable from an angler's PUBLIC data — their profile
    /// stats plus published catches — shown on a friend's profile. Spot,
    /// release and forecast badges need local data, so they're omitted
    /// rather than shown permanently locked.
    static func computeFriend(totalCatches: Int, speciesCount: Int,
                              bestWeightKg: Double, bestLengthCm: Double,
                              rows: [CommunityService.LeaderRow]) -> [BadgeDefinition] {
        let photos = rows.filter { $0.hasRemotePhoto || $0.localPhotoPath != nil }.count
        let hours = rows.map { Calendar.current.component(.hour, from: $0.date) }
        let night = hours.contains { $0 < 5 || $0 >= 22 }
        let dawn = hours.contains { $0 >= 5 && $0 < 7 }
        let months = Set(rows.map { Calendar.current.component(.month, from: $0.date) }).count

        return [
            BadgeDefinition(icon: "fish.fill", title: "First Catch", rarity: .common, earned: totalCatches >= 1),
            BadgeDefinition(icon: "camera.fill", title: "Snap Happy", rarity: .common, earned: photos >= 3),
            BadgeDefinition(icon: "scalemass", title: "Keeper", rarity: .common, earned: bestWeightKg >= 1),
            BadgeDefinition(icon: "trophy.fill", title: "10 Club", rarity: .uncommon, earned: totalCatches >= 10),
            BadgeDefinition(icon: "star.leadinghalf.filled", title: "Quarter Century", rarity: .uncommon, earned: totalCatches >= 25),
            BadgeDefinition(icon: "leaf.fill", title: "5 Species", rarity: .uncommon, earned: speciesCount >= 5),
            BadgeDefinition(icon: "camera.fill", title: "Photographer", rarity: .uncommon, earned: photos >= 10),
            BadgeDefinition(icon: "scalemass", title: "Solid Fish", rarity: .uncommon, earned: bestWeightKg >= 2),
            BadgeDefinition(icon: "calendar", title: "Four Seasons", rarity: .uncommon, earned: months >= 4),
            BadgeDefinition(icon: "star.fill", title: "50 Catches", rarity: .rare, earned: totalCatches >= 50),
            BadgeDefinition(icon: "moon.fill", title: "Night Owl", rarity: .rare, earned: night),
            BadgeDefinition(icon: "sun.max.fill", title: "Dawn Patrol", rarity: .rare, earned: dawn),
            BadgeDefinition(icon: "scalemass", title: "Heavy Hitter", rarity: .rare, earned: bestWeightKg >= 5),
            BadgeDefinition(icon: "ruler", title: "Long One", rarity: .rare, earned: bestLengthCm >= 50),
            BadgeDefinition(icon: "leaf.fill", title: "Diversified", rarity: .rare, earned: speciesCount >= 10),
            BadgeDefinition(icon: "crown.fill", title: "Century", rarity: .epic, earned: totalCatches >= 100),
            BadgeDefinition(icon: "calendar.badge.checkmark", title: "Year-Round", rarity: .epic, earned: months >= 8),
            BadgeDefinition(icon: "scalemass", title: "Monster", rarity: .epic, earned: bestWeightKg >= 12),
            BadgeDefinition(icon: "ruler", title: "Meter Class", rarity: .epic, earned: bestLengthCm >= 80),
            BadgeDefinition(icon: "leaf.fill", title: "Collector", rarity: .epic, earned: speciesCount >= 15),
            BadgeDefinition(icon: "star.circle.fill", title: "Double Century", rarity: .legendary, earned: totalCatches >= 200),
            BadgeDefinition(icon: "rosette", title: "500 Club", rarity: .legendary, earned: totalCatches >= 500),
            BadgeDefinition(icon: "crown.fill", title: "Species Master", rarity: .legendary, earned: speciesCount >= 25),
            BadgeDefinition(icon: "scalemass", title: "Trophy Hunter", rarity: .legendary, earned: bestWeightKg >= 30),
            BadgeDefinition(icon: "ruler", title: "Meter Monster", rarity: .legendary, earned: bestLengthCm >= 100),
            BadgeDefinition(icon: "medal.fill", title: "Thousand Club", rarity: .mythic, earned: totalCatches >= 1000),
            BadgeDefinition(icon: "scalemass", title: "Leviathan", rarity: .mythic, earned: bestWeightKg >= 50),
            BadgeDefinition(icon: "crown.fill", title: "Master of All Waters", rarity: .mythic, earned: speciesCount >= 50),
        ]
    }

    /// The calendar for every streak and week count. Weeks run Monday to
    /// Sunday, as the streak copy says, whatever the locale's first weekday
    /// (Sunday for en_US and en_ZA). Built on each read, so a time zone
    /// change applies straight away.
    static var weekCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Consecutive-week fishing streak: the number of back-to-back weeks
    /// (Monday to Sunday, see `weekCalendar`) in which at least one catch was
    /// logged, counting back from this week. It stays alive while the latest
    /// catch week is this week or last week. Daily streaks were effectively
    /// unreachable, so the streak is weekly.
    static func streakWeeks(from catches: [CatchDetail]) -> Int {
        let calendar = weekCalendar
        let weeks = Set(catches.map { weekStart(of: $0.catchRecord.caughtAt, calendar: calendar) })
        let thisWeek = weekStart(of: .now, calendar: calendar)
        var week: Date? = weeks.contains(thisWeek) ? thisWeek : adjacentWeek(-1, to: thisWeek, calendar: calendar)
        var streak = 0
        while let current = week, weeks.contains(current), streak < weeks.count {
            streak += 1
            week = adjacentWeek(-1, to: current, calendar: calendar)
        }
        return streak
    }

    /// The start of the calendar week holding `date`.
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The start of the week `offset` weeks from the one starting at `week`.
    /// Calendar arithmetic rather than counting days, so a week made shorter
    /// or longer by a daylight saving change, or one that spans New Year,
    /// still counts as one week.
    static func adjacentWeek(_ offset: Int, to week: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .weekOfYear, value: offset, to: week).map { weekStart(of: $0, calendar: calendar) }
    }
}

// MARK: - Metrics

/// The numbers the badges are judged on, tallied in one pass over the
/// catches from oldest to newest so each badge also knows the catch that
/// earned it.
struct BadgeMetrics {
    /// The live weekly streak, as passed in.
    let currentStreak: Int
    /// When each badge's target was first reached, by badge title.
    let earnedAt: [String: Date]
    private let tally: Tally

    init(catches: [CatchDetail], streakWeeks: Int) {
        let calendar = BadgeDefinition.weekCalendar
        var tally = Tally()
        var reached: [String: Date] = [:]
        var locked = BadgeDefinition.specs.filter { !$0.metric.isHidden }
        let oldestFirst = catches.sorted { $0.catchRecord.caughtAt < $1.catchRecord.caughtAt }
        for detail in oldestFirst {
            tally.add(detail, calendar: calendar)
            guard !locked.isEmpty else { continue }
            let caughtAt = detail.catchRecord.caughtAt
            locked.removeAll { spec in
                let done = tally.value(spec.metric) >= spec.target
                if done { reached[spec.title] = caughtAt }
                return done
            }
        }
        if let unlocked = BadgeDefinition.bassDaddyUnlockedAt {
            reached["Bass Daddy"] = unlocked
        }
        if let since = BadgeDefinition.supporterSince {
            reached["Patron"] = since
        }
        self.tally = tally
        self.currentStreak = streakWeeks
        self.earnedAt = reached
    }

    /// The best so far for `metric`. Streaks give the longest run of weeks
    /// ever logged.
    func value(_ metric: BadgeMetric) -> Double {
        switch metric {
        case .streakWeeks: return Double(max(tally.bestRun, currentStreak))
        case .secret: return BadgeDefinition.bassDaddyUnlocked ? 1 : 0
        case .supporter: return BadgeDefinition.isSupporter ? 1 : 0
        default: return tally.value(metric)
        }
    }

    func isEarned(_ spec: BadgeSpec) -> Bool {
        value(spec.metric) >= spec.target
    }

    /// Running totals, updated catch by catch.
    private struct Tally {
        var total = 0
        var species = Set<Int64>()
        var spots = Set<String>()
        var released = 0
        var withPhoto = 0
        var heaviest = 0.0
        var longest = 0.0
        var bestScore = 0
        var months = Set<Int>()
        var perDay: [Date: Int] = [:]
        var bestDay = 0
        var weekend = false
        var night = false
        var dawn = false
        /// The latest week of the run of back-to-back weeks so far.
        var runWeek: Date?
        var run = 0
        var bestRun = 0

        mutating func add(_ detail: CatchDetail, calendar: Calendar) {
            let record = detail.catchRecord
            let date = record.caughtAt
            total += 1
            if let id = detail.species?.id { species.insert(id) }
            if let id = detail.spot?.id { spots.insert(id) }
            if record.released { released += 1 }
            if !record.allPhotoPaths.isEmpty { withPhoto += 1 }
            heaviest = max(heaviest, record.weightKg ?? 0)
            longest = max(longest, record.lengthCm ?? 0)
            bestScore = max(bestScore, record.forecastScoreAtCapture ?? 0)
            months.insert(calendar.component(.month, from: date))

            let day = calendar.startOfDay(for: date)
            let onDay = (perDay[day] ?? 0) + 1
            perDay[day] = onDay
            bestDay = max(bestDay, onDay)

            if calendar.isDateInWeekend(date) { weekend = true }
            let hour = calendar.component(.hour, from: date)
            if hour < 5 || hour >= 22 { night = true }
            if hour >= 5 && hour < 7 { dawn = true }

            addWeek(BadgeDefinition.weekStart(of: date, calendar: calendar), calendar: calendar)
        }

        /// Catches arrive oldest first, so a new week either follows the run
        /// or starts a new one.
        private mutating func addWeek(_ week: Date, calendar: Calendar) {
            guard week != runWeek else { return }
            var follows = false
            if let runWeek {
                follows = BadgeDefinition.adjacentWeek(1, to: runWeek, calendar: calendar) == week
            }
            run = follows ? run + 1 : 1
            runWeek = week
            bestRun = max(bestRun, run)
        }

        func value(_ metric: BadgeMetric) -> Double {
            switch metric {
            case .catches:     return Double(total)
            case .species:     return Double(species.count)
            case .spots:       return Double(spots.count)
            case .released:    return Double(released)
            case .photos:      return Double(withPhoto)
            case .weightKg:    return heaviest
            case .lengthCm:    return longest
            case .biteScore:   return Double(bestScore)
            case .months:      return Double(months.count)
            case .bestDay:     return Double(bestDay)
            case .streakWeeks: return Double(run)
            case .weekend:     return weekend ? 1 : 0
            case .night:       return night ? 1 : 0
            case .dawn:        return dawn ? 1 : 0
            case .secret, .supporter: return 0
            }
        }
    }
}

// MARK: - Badge views

/// A round medal in its rarity colour: a solid rim, a fine inner ring and
/// the badge's symbol. A locked medal is an empty dashed slot with a small
/// lock.
struct BadgeMedal: View {
    let badge: BadgeDefinition
    var size: CGFloat = 64
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { badge.rarity.color }

    /// On a light page the rim and symbol are deepened a little, so yellow
    /// and cyan medals keep their contrast.
    private var inkShift: Double { badge.earned && scheme == .light ? -0.18 : 0 }

    var body: some View {
        ZStack {
            if badge.earned { earnedFace } else { lockedFace }
            Image(systemName: badge.icon)
                .font(.system(size: size * 0.4, weight: .semibold)) // ui-lint: allow, symbol sized to the medal
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(badge.earned ? tint : Color.dsText3)
                .brightness(inkShift)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if !badge.earned { lock }
        }
        .accessibilityHidden(true)
    }

    private var earnedFace: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(scheme == .dark ? 0.24 : 0.16))
            Circle()
                .strokeBorder(tint, lineWidth: max(2, size * 0.05))
                .brightness(inkShift)
            Circle()
                .inset(by: size * 0.12)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
    }

    private var lockedFace: some View {
        ZStack {
            Circle()
                .fill(Color.dsFill)
            Circle()
                .strokeBorder(Color.dsText3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
    }

    private var lock: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: max(9, size * 0.16), weight: .bold)) // ui-lint: allow, lock sized to the medal
            .foregroundStyle(.dsText2)
            .frame(width: size * 0.34, height: size * 0.34)
            .background(Color.dsFill2, in: Circle())
            .overlay(Circle().strokeBorder(Color.dsBackground, lineWidth: 2))
    }
}

/// Medals with their names under them, as many across as fit: four on a
/// phone at the default text size, fewer at large sizes. Every name gets two
/// lines of room, so a row's medals line up whether the names wrap or not.
struct BadgeMedalGrid: View {
    let badges: [BadgeDefinition]
    let onSelect: (BadgeDefinition) -> Void
    @ScaledMetric(relativeTo: .caption) private var cellWidth: CGFloat = 76

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: DS.Space.s2, alignment: .top)],
                  alignment: .center, spacing: DS.Space.s4) {
            ForEach(badges) { badge in
                Button {
                    onSelect(badge)
                } label: {
                    cell(badge)
                }
                .buttonStyle(.dim)
                .accessibilityLabel(badge.accessibilityLabel)
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private func cell(_ badge: BadgeDefinition) -> some View {
        VStack(spacing: DS.Space.s2) {
            BadgeMedal(badge: badge)
            Text(badge.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(badge.earned ? Color.dsText : Color.dsText2)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A profile's achievements: the earned medals, rarest first, each opening
/// its detail sheet, and a link to the full achievements page.
struct AchievementsCard: View {
    let catches: [CatchDetail]
    var topCount = 5

    var body: some View {
        // Tallied once here; the content below re-renders on its own when a
        // medal is opened.
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: BadgeDefinition.streakWeeks(from: catches))
        // Hidden badges only count once earned, so the tally has no spoiler.
        let visible = badges.filter { $0.earned || !$0.hidden }
        AchievementsCardContent(catches: catches,
                                earned: Self.rarestFirst(visible.filter(\.earned)),
                                visibleCount: visible.count,
                                topCount: topCount)
    }

    /// Rarest first; within a rarity, the most recently earned first.
    private static func rarestFirst(_ badges: [BadgeDefinition]) -> [BadgeDefinition] {
        badges.sorted {
            ($0.rarity.rawValue, $0.earnedAt ?? .distantPast) > ($1.rarity.rawValue, $1.earnedAt ?? .distantPast)
        }
    }
}

private struct AchievementsCardContent: View {
    let catches: [CatchDetail]
    let earned: [BadgeDefinition]
    let visibleCount: Int
    let topCount: Int
    @State private var selected: BadgeDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("\(earned.count) of \(visibleCount) earned")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.dsText2)

            if earned.isEmpty {
                Text("No badges yet. Log a catch to earn your first.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            } else {
                medals
            }

            NavigationLink("Show all badges") {
                AchievementsView(catches: catches)
            }
            .buttonStyle(.dsTonal)
        }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
        }
    }

    private var medals: some View {
        // Wraps rather than running off the edge when topCount is large.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: DS.Space.s3)],
                  alignment: .leading, spacing: DS.Space.s3) {
            ForEach(earned.prefix(topCount)) { badge in
                Button {
                    selected = badge
                } label: {
                    BadgeMedal(badge: badge, size: 46)
                }
                .buttonStyle(.dim)
                .accessibilityLabel(badge.accessibilityLabel)
            }
        }
    }
}

/// A badge's sheet: the medal large (tap an earned one to turn it), how it is
/// earned or the secret quote, then the date it was earned or how close it
/// is, and the profile title it unlocks.
struct BadgeDetailView: View {
    let badge: BadgeDefinition
    /// How far along a locked badge is, when the caller knows the catches.
    var progress: BadgeProgress? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The rule's sizes and hours redraw when either setting changes.
    @AppStorage("units") private var units = "metric"
    @AppStorage("use24HourTime") private var use24 = true
    @State private var turns: Double = 0

    private var flair: TitleFlair? {
        TitleFlair.all.first { $0.achievement == badge.title }
    }

    var body: some View {
        // Its own stack so Done sits in the toolbar, visible at the medium
        // height. Every caller presents it bare in a sheet.
        NavigationStack {
            content
                .detailScrollEdge()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                }
        }
        .dsSheet([.medium, .large])
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                medal
                    .padding(.top, DS.Space.s2)
                Text(badge.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(.dsText)
                    .padding(.top, DS.Space.s4)
                Text(badge.rarity.label)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .padding(.top, DS.Space.s1)
                about
                    .padding(.top, DS.Space.s3)
                status
                    .padding(.top, DS.Space.s5)
                if let flair {
                    Text("Unlocks the profile title \(flair.displayName).")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .padding(.top, DS.Space.s4)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, DS.Space.s6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsScreenBackground()
    }

    /// An earned medal turns once per tap, like flipping it over in the hand.
    @ViewBuilder
    private var medal: some View {
        if badge.earned && !reduceMotion {
            Button {
                withAnimation(DS.Motion.softSpring) { turns += 1 }
            } label: {
                medalArt
            }
            .buttonStyle(.dim)
            .accessibilityHidden(true)
        } else {
            medalArt
        }
    }

    private var medalArt: some View {
        BadgeMedal(badge: badge, size: 120)
            .rotation3DEffect(.degrees(turns * 360), axis: (x: 0, y: 1, z: 0))
    }

    @ViewBuilder
    private var about: some View {
        if badge.isSecretQuote {
            VStack(spacing: DS.Space.s2) {
                Text(BadgeDefinition.bassDaddyQuote)
                    .font(.body.italic())
                    .foregroundStyle(.dsText)
                Text(BadgeDefinition.bassDaddyQuoteBy)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
        } else {
            Text(badge.explanation)
                .font(.body)
                .foregroundStyle(.dsText2)
        }
    }

    @ViewBuilder
    private var status: some View {
        if badge.earned {
            Label {
                Text(earnedText)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.dsScoreGood)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.dsText)
        } else if let progress, !progress.isYesNo {
            VStack(spacing: DS.Space.s2) {
                LogbookProgressBar(fraction: progress.fraction, tint: badge.rarity.color)
                Text(progress.text)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
            }
            .frame(maxWidth: 280)
        } else {
            Label("Not earned yet", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText2)
        }
    }

    private var earnedText: String {
        guard let earnedAt = badge.earnedAt else { return "Earned" }
        return "Earned on \(LogbookFormat.fullDate(earnedAt))"
    }
}
