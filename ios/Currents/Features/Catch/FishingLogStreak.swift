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

    var color: Color {
        switch self {
        case .common:    return .gray
        case .uncommon:  return CurrentsTheme.accent
        case .rare:      return .cyan
        case .epic:      return .purple
        case .legendary: return .yellow
        case .mythic:    return Color(red: 1.0, green: 0.22, blue: 0.45)
        }
    }

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
/// name and emoji ("Century" unlocks "Centurion 💯") — the achievement is the
/// provenance, shown when the worn title is tapped. Colours follow the
/// unlocking achievement's rarity.
struct TitleFlair: Identifiable {
    let achievement: String   // the BadgeDefinition title that unlocks it
    let name: String          // what's worn under the profile name
    let emoji: String
    let rarity: BadgeRarity
    let icon: String          // the achievement's symbol, for the detail modal
    var id: String { achievement }

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
        .init(achievement: "First Catch", name: "First Hook", emoji: "🪝", rarity: .common, icon: "fish.fill"),
        .init(achievement: "Snap Happy", name: "Shutterbug", emoji: "📸", rarity: .common, icon: "camera.fill"),
        .init(achievement: "Marked It", name: "Pathfinder", emoji: "🗺️", rarity: .common, icon: "mappin.circle.fill"),
        .init(achievement: "Good Sport", name: "Good Sport", emoji: "🤝", rarity: .common, icon: "arrow.uturn.backward"),
        .init(achievement: "Keeper", name: "Keeper", emoji: "🪣", rarity: .common, icon: "scalemass"),
        .init(achievement: "Doubleheader", name: "Doubleheader", emoji: "✌️", rarity: .common, icon: "fish.fill"),
        .init(achievement: "Weekend Warrior", name: "Weekend Warrior", emoji: "⛺", rarity: .common, icon: "tent.fill"),
        // Uncommon
        .init(achievement: "10 Club", name: "Rising Angler", emoji: "🎣", rarity: .uncommon, icon: "trophy.fill"),
        .init(achievement: "Quarter Century", name: "Regular", emoji: "🎯", rarity: .uncommon, icon: "star.leadinghalf.filled"),
        .init(achievement: "5 Species", name: "Species Scout", emoji: "🔍", rarity: .uncommon, icon: "leaf.fill"),
        .init(achievement: "Explorer", name: "Explorer", emoji: "🧭", rarity: .uncommon, icon: "globe.americas.fill"),
        .init(achievement: "Photographer", name: "Photographer", emoji: "📷", rarity: .uncommon, icon: "camera.fill"),
        .init(achievement: "Hot Streak", name: "On a Roll", emoji: "⚡", rarity: .uncommon, icon: "flame.fill"),
        .init(achievement: "Conservationist", name: "Conservationist", emoji: "🌿", rarity: .uncommon, icon: "arrow.uturn.backward.circle.fill"),
        .init(achievement: "Hat Trick", name: "Hat Trick", emoji: "🎩", rarity: .uncommon, icon: "fish.fill"),
        .init(achievement: "Solid Fish", name: "Rod Bender", emoji: "🎏", rarity: .uncommon, icon: "scalemass"),
        .init(achievement: "Four Seasons", name: "Four Seasons", emoji: "🍂", rarity: .uncommon, icon: "calendar"),
        // Rare
        .init(achievement: "50 Catches", name: "Seasoned Angler", emoji: "🐠", rarity: .rare, icon: "star.fill"),
        .init(achievement: "Night Owl", name: "Night Owl", emoji: "🦉", rarity: .rare, icon: "moon.fill"),
        .init(achievement: "Dawn Patrol", name: "Early Riser", emoji: "🌅", rarity: .rare, icon: "sun.max.fill"),
        .init(achievement: "Heavy Hitter", name: "Heavy Hitter", emoji: "💪", rarity: .rare, icon: "scalemass"),
        .init(achievement: "Long One", name: "Longliner", emoji: "📏", rarity: .rare, icon: "ruler"),
        .init(achievement: "Diversified", name: "Naturalist", emoji: "🐚", rarity: .rare, icon: "leaf.fill"),
        .init(achievement: "On Fire", name: "Firebrand", emoji: "🔥", rarity: .rare, icon: "flame.fill"),
        .init(achievement: "Full Stringer", name: "Full Stringer", emoji: "🧺", rarity: .rare, icon: "fish.fill"),
        .init(achievement: "Wanderer", name: "Wanderer", emoji: "🥾", rarity: .rare, icon: "map.fill"),
        .init(achievement: "Sharp Eye", name: "Sharp Eye", emoji: "👁️", rarity: .rare, icon: "gauge.medium"),
        .init(achievement: "Release Artist", name: "Release Artist", emoji: "🕊️", rarity: .rare, icon: "arrow.uturn.backward.circle.fill"),
        // Epic
        .init(achievement: "Century", name: "Centurion", emoji: "💯", rarity: .epic, icon: "crown.fill"),
        .init(achievement: "Nomad", name: "Nomad", emoji: "🌍", rarity: .epic, icon: "globe.americas.fill"),
        .init(achievement: "Perfect Read", name: "Water Whisperer", emoji: "🌊", rarity: .epic, icon: "gauge.medium"),
        .init(achievement: "Year-Round", name: "All-Season Angler", emoji: "🗓️", rarity: .epic, icon: "calendar.badge.checkmark"),
        .init(achievement: "Monster", name: "Monster Hunter", emoji: "🦑", rarity: .epic, icon: "scalemass"),
        .init(achievement: "Portfolio", name: "Curator", emoji: "🖼️", rarity: .epic, icon: "camera.fill"),
        .init(achievement: "Big Day", name: "Big Day Hero", emoji: "🌟", rarity: .epic, icon: "sun.max.fill"),
        .init(achievement: "Relentless", name: "Relentless", emoji: "🌪️", rarity: .epic, icon: "flame.fill"),
        .init(achievement: "Meter Class", name: "Meter Class", emoji: "📐", rarity: .epic, icon: "ruler"),
        .init(achievement: "Collector", name: "Collector", emoji: "🧩", rarity: .epic, icon: "leaf.fill"),
        // Legendary
        .init(achievement: "Double Century", name: "Double Centurion", emoji: "⚔️", rarity: .legendary, icon: "star.circle.fill"),
        .init(achievement: "500 Club", name: "Old Salt", emoji: "🐋", rarity: .legendary, icon: "sparkles"),
        .init(achievement: "Species Master", name: "Master of Species", emoji: "🐡", rarity: .legendary, icon: "crown.fill"),
        .init(achievement: "Unstoppable", name: "Unstoppable", emoji: "🚀", rarity: .legendary, icon: "flame.fill"),
        .init(achievement: "Trophy Hunter", name: "Trophy Hunter", emoji: "🏆", rarity: .legendary, icon: "scalemass"),
        .init(achievement: "Meter Monster", name: "Meter Monster", emoji: "🐉", rarity: .legendary, icon: "ruler"),
        .init(achievement: "Water Guardian", name: "Water Guardian", emoji: "🛡️", rarity: .legendary, icon: "arrow.uturn.backward.circle.fill"),
        .init(achievement: "Shutter Legend", name: "Shutter Legend", emoji: "🎞️", rarity: .legendary, icon: "camera.fill"),
        .init(achievement: "World Traveler", name: "World Traveler", emoji: "✈️", rarity: .legendary, icon: "globe.americas.fill"),
        // Mythic
        .init(achievement: "Thousand Club", name: "Thousand Legend", emoji: "🌌", rarity: .mythic, icon: "sparkles"),
        .init(achievement: "Leviathan", name: "Leviathan", emoji: "🐙", rarity: .mythic, icon: "scalemass"),
        .init(achievement: "Master of All Waters", name: "Master of All Waters", emoji: "🔱", rarity: .mythic, icon: "crown.fill"),
        .init(achievement: "Eternal Flame", name: "Eternal Flame", emoji: "🌋", rarity: .mythic, icon: "flame.fill"),
        .init(achievement: "Bass Daddy", name: "Bass Daddy", emoji: "🐟", rarity: .mythic, icon: "fish.fill"),
    ]
}

struct BadgeDefinition: Identifiable {
    let icon: String
    let title: String
    let rarity: BadgeRarity
    let earned: Bool
    /// Hidden badges (easter eggs) stay invisible until earned — they never
    /// appear in locked lists or counts.
    var hidden: Bool = false

    var id: String { title }

    /// The secret Bass Daddy unlock — typing 90210 into the friend-code box.
    /// Stored locally; once unlocked it's yours forever.
    static var bassDaddyUnlocked: Bool {
        UserDefaults.standard.bool(forKey: "bassDaddyUnlocked")
    }
    static func unlockBassDaddy() {
        UserDefaults.standard.set(true, forKey: "bassDaddyUnlocked")
    }

    /// A friendly one-liner explaining how the badge is earned, shown in the
    /// tap-to-open detail modal.
    var explanation: String {
        switch title {
        case "First Catch":     return "Log your very first catch in Currents."
        case "Snap Happy":      return "Add a photo to 3 of your catches."
        case "Marked It":       return "Save your first fishing spot on the map."
        case "Good Sport":      return "Release 3 catches back to the water."
        case "Keeper":          return "Land a fish weighing 1 kg (2.2 lb) or more."
        case "Doubleheader":    return "Log 2 catches in a single day."
        case "Weekend Warrior": return "Log a catch on a Saturday or Sunday."
        case "10 Club":         return "Log 10 catches."
        case "Quarter Century": return "Log 25 catches."
        case "5 Species":       return "Catch 5 different species."
        case "Explorer":        return "Fish at 3 different saved spots."
        case "Photographer":    return "Add photos to 10 of your catches."
        case "Hot Streak":      return "Log a catch in 2 back-to-back weeks."
        case "Conservationist": return "Release 10 catches."
        case "Hat Trick":       return "Log 3 catches in a single day."
        case "Solid Fish":      return "Land a fish weighing 2 kg (4.4 lb) or more."
        case "Four Seasons":    return "Log catches in 4 different months of the year."
        case "50 Catches":      return "Log 50 catches."
        case "Night Owl":       return "Log a catch late at night (10pm–5am)."
        case "Dawn Patrol":     return "Log a catch at first light (5–7am)."
        case "Heavy Hitter":    return "Land a fish weighing 5 kg (11 lb) or more."
        case "Long One":        return "Land a fish 50 cm (20 in) or longer."
        case "Diversified":     return "Catch 10 different species."
        case "On Fire":         return "Keep a weekly fishing streak alive for 4 weeks."
        case "Full Stringer":   return "Log 5 catches in a single day."
        case "Wanderer":        return "Fish at 5 different saved spots."
        case "Sharp Eye":       return "Land a catch when the bite score was 75 or higher."
        case "Release Artist":  return "Release 25 catches."
        case "Century":         return "Log 100 catches."
        case "Nomad":           return "Fish at 8 different saved spots."
        case "Perfect Read":    return "Land a catch when the bite score was 85 or higher."
        case "Year-Round":      return "Log catches in 8 different months of the year."
        case "Monster":         return "Land a fish weighing 12 kg (26 lb) or more."
        case "Portfolio":       return "Add photos to 35 of your catches."
        case "Big Day":         return "Log 8 catches in a single day."
        case "Relentless":      return "Keep a weekly fishing streak alive for 8 weeks."
        case "Meter Class":     return "Land a fish 80 cm (31 in) or longer."
        case "Collector":       return "Catch 15 different species."
        case "Double Century":  return "Log 200 catches."
        case "500 Club":        return "Log 500 catches."
        case "Species Master":  return "Catch 25 different species."
        case "Unstoppable":     return "Keep a weekly fishing streak alive for 12 weeks."
        case "Trophy Hunter":   return "Land a fish weighing 30 kg (66 lb) or more."
        case "Meter Monster":   return "Land a fish 100 cm (39 in) or longer."
        case "Water Guardian":  return "Release 100 catches."
        case "Shutter Legend":  return "Add photos to 100 of your catches."
        case "World Traveler":  return "Fish at 15 different saved spots."
        case "Thousand Club":   return "Log 1,000 catches. A life on the water."
        case "Leviathan":       return "Land a fish weighing 50 kg (110 lb) or more."
        case "Master of All Waters": return "Catch 50 different species."
        case "Eternal Flame":   return "Keep a weekly fishing streak alive for 26 weeks — half a year."
        case "Bass Daddy":      return "You knew the secret code. Welcome to the 90210 club, Bass Daddy. 🐟"
        default:                return "Keep fishing to unlock this badge."
        }
    }

    static func compute(from catches: [CatchDetail], streakWeeks: Int) -> [BadgeDefinition] {
        let total = catches.count
        let species = Set(catches.compactMap { $0.species?.id }).count
        let spots = Set(catches.compactMap { $0.spot?.id }).count
        let released = catches.filter { $0.catchRecord.released }.count
        let withPhoto = catches.filter { !$0.catchRecord.allPhotoPaths.isEmpty }.count
        let heaviest = catches.compactMap(\.catchRecord.weightKg).max() ?? 0
        let longest = catches.compactMap(\.catchRecord.lengthCm).max() ?? 0
        let highScore = catches.compactMap(\.catchRecord.forecastScoreAtCapture).max() ?? 0
        let uniqueMonths = Set(catches.map { Calendar.current.component(.month, from: $0.catchRecord.caughtAt) }).count
        // Best single calendar day, for the catches-in-a-day ladder.
        let maxPerDay = Dictionary(grouping: catches, by: {
            Calendar.current.startOfDay(for: $0.catchRecord.caughtAt)
        }).values.map(\.count).max() ?? 0
        let weekendCatch = catches.contains { Calendar.current.isDateInWeekend($0.catchRecord.caughtAt) }

        return [
            // Common
            BadgeDefinition(icon: "fish.fill", title: "First Catch", rarity: .common, earned: total >= 1),
            BadgeDefinition(icon: "camera.fill", title: "Snap Happy", rarity: .common, earned: withPhoto >= 3),
            BadgeDefinition(icon: "mappin.circle.fill", title: "Marked It", rarity: .common, earned: spots >= 1),
            BadgeDefinition(icon: "arrow.uturn.backward", title: "Good Sport", rarity: .common, earned: released >= 3),
            BadgeDefinition(icon: "scalemass", title: "Keeper", rarity: .common, earned: heaviest >= 1),
            BadgeDefinition(icon: "fish.fill", title: "Doubleheader", rarity: .common, earned: maxPerDay >= 2),
            BadgeDefinition(icon: "tent.fill", title: "Weekend Warrior", rarity: .common, earned: weekendCatch),

            // Uncommon
            BadgeDefinition(icon: "trophy.fill", title: "10 Club", rarity: .uncommon, earned: total >= 10),
            BadgeDefinition(icon: "star.leadinghalf.filled", title: "Quarter Century", rarity: .uncommon, earned: total >= 25),
            BadgeDefinition(icon: "leaf.fill", title: "5 Species", rarity: .uncommon, earned: species >= 5),
            BadgeDefinition(icon: "globe.americas.fill", title: "Explorer", rarity: .uncommon, earned: spots >= 3),
            BadgeDefinition(icon: "camera.fill", title: "Photographer", rarity: .uncommon, earned: withPhoto >= 10),
            BadgeDefinition(icon: "flame.fill", title: "Hot Streak", rarity: .uncommon, earned: streakWeeks >= 2),
            BadgeDefinition(icon: "arrow.uturn.backward.circle.fill", title: "Conservationist", rarity: .uncommon, earned: released >= 10),
            BadgeDefinition(icon: "fish.fill", title: "Hat Trick", rarity: .uncommon, earned: maxPerDay >= 3),
            BadgeDefinition(icon: "scalemass", title: "Solid Fish", rarity: .uncommon, earned: heaviest >= 2),
            BadgeDefinition(icon: "calendar", title: "Four Seasons", rarity: .uncommon, earned: uniqueMonths >= 4),

            // Rare
            BadgeDefinition(icon: "star.fill", title: "50 Catches", rarity: .rare, earned: total >= 50),
            BadgeDefinition(icon: "moon.fill", title: "Night Owl", rarity: .rare, earned: catches.contains {
                let h = Calendar.current.component(.hour, from: $0.catchRecord.caughtAt)
                return h < 5 || h >= 22
            }),
            BadgeDefinition(icon: "sun.max.fill", title: "Dawn Patrol", rarity: .rare, earned: catches.contains {
                let h = Calendar.current.component(.hour, from: $0.catchRecord.caughtAt)
                return h >= 5 && h < 7
            }),
            BadgeDefinition(icon: "scalemass", title: "Heavy Hitter", rarity: .rare, earned: heaviest >= 5),
            BadgeDefinition(icon: "ruler", title: "Long One", rarity: .rare, earned: longest >= 50),
            BadgeDefinition(icon: "leaf.fill", title: "Diversified", rarity: .rare, earned: species >= 10),
            BadgeDefinition(icon: "flame.fill", title: "On Fire", rarity: .rare, earned: streakWeeks >= 4),
            BadgeDefinition(icon: "fish.fill", title: "Full Stringer", rarity: .rare, earned: maxPerDay >= 5),
            BadgeDefinition(icon: "map.fill", title: "Wanderer", rarity: .rare, earned: spots >= 5),
            BadgeDefinition(icon: "gauge.medium", title: "Sharp Eye", rarity: .rare, earned: highScore >= 75),
            BadgeDefinition(icon: "arrow.uturn.backward.circle.fill", title: "Release Artist", rarity: .rare, earned: released >= 25),

            // Epic
            BadgeDefinition(icon: "crown.fill", title: "Century", rarity: .epic, earned: total >= 100),
            BadgeDefinition(icon: "globe.americas.fill", title: "Nomad", rarity: .epic, earned: spots >= 8),
            BadgeDefinition(icon: "gauge.medium", title: "Perfect Read", rarity: .epic, earned: highScore >= 85),
            BadgeDefinition(icon: "calendar.badge.checkmark", title: "Year-Round", rarity: .epic, earned: uniqueMonths >= 8),
            BadgeDefinition(icon: "scalemass", title: "Monster", rarity: .epic, earned: heaviest >= 12),
            BadgeDefinition(icon: "camera.fill", title: "Portfolio", rarity: .epic, earned: withPhoto >= 35),
            BadgeDefinition(icon: "sun.max.fill", title: "Big Day", rarity: .epic, earned: maxPerDay >= 8),
            BadgeDefinition(icon: "flame.fill", title: "Relentless", rarity: .epic, earned: streakWeeks >= 8),
            BadgeDefinition(icon: "ruler", title: "Meter Class", rarity: .epic, earned: longest >= 80),
            BadgeDefinition(icon: "leaf.fill", title: "Collector", rarity: .epic, earned: species >= 15),

            // Legendary
            BadgeDefinition(icon: "star.circle.fill", title: "Double Century", rarity: .legendary, earned: total >= 200),
            BadgeDefinition(icon: "sparkles", title: "500 Club", rarity: .legendary, earned: total >= 500),
            BadgeDefinition(icon: "crown.fill", title: "Species Master", rarity: .legendary, earned: species >= 25),
            BadgeDefinition(icon: "flame.fill", title: "Unstoppable", rarity: .legendary, earned: streakWeeks >= 12),
            BadgeDefinition(icon: "scalemass", title: "Trophy Hunter", rarity: .legendary, earned: heaviest >= 30),
            BadgeDefinition(icon: "ruler", title: "Meter Monster", rarity: .legendary, earned: longest >= 100),
            BadgeDefinition(icon: "arrow.uturn.backward.circle.fill", title: "Water Guardian", rarity: .legendary, earned: released >= 100),
            BadgeDefinition(icon: "camera.fill", title: "Shutter Legend", rarity: .legendary, earned: withPhoto >= 100),
            BadgeDefinition(icon: "globe.americas.fill", title: "World Traveler", rarity: .legendary, earned: spots >= 15),

            // Mythic
            BadgeDefinition(icon: "sparkles", title: "Thousand Club", rarity: .mythic, earned: total >= 1000),
            BadgeDefinition(icon: "scalemass", title: "Leviathan", rarity: .mythic, earned: heaviest >= 50),
            BadgeDefinition(icon: "crown.fill", title: "Master of All Waters", rarity: .mythic, earned: species >= 50),
            BadgeDefinition(icon: "flame.fill", title: "Eternal Flame", rarity: .mythic, earned: streakWeeks >= 26),
            BadgeDefinition(icon: "fish.fill", title: "Bass Daddy", rarity: .mythic,
                            earned: bassDaddyUnlocked, hidden: true),
        ]
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
            BadgeDefinition(icon: "sparkles", title: "500 Club", rarity: .legendary, earned: totalCatches >= 500),
            BadgeDefinition(icon: "crown.fill", title: "Species Master", rarity: .legendary, earned: speciesCount >= 25),
            BadgeDefinition(icon: "scalemass", title: "Trophy Hunter", rarity: .legendary, earned: bestWeightKg >= 30),
            BadgeDefinition(icon: "ruler", title: "Meter Monster", rarity: .legendary, earned: bestLengthCm >= 100),
            BadgeDefinition(icon: "sparkles", title: "Thousand Club", rarity: .mythic, earned: totalCatches >= 1000),
            BadgeDefinition(icon: "scalemass", title: "Leviathan", rarity: .mythic, earned: bestWeightKg >= 50),
            BadgeDefinition(icon: "crown.fill", title: "Master of All Waters", rarity: .mythic, earned: speciesCount >= 50),
        ]
    }

    /// Consecutive-week fishing streak: the number of back-to-back weeks
    /// (each Mon–Sun) in which at least one catch was logged, counting back
    /// from this week. Daily streaks were effectively unreachable — you had to
    /// fish every single day — so the streak is weekly: it stays alive as long
    /// as you fish at least once a week.
    static func streakWeeks(from catches: [CatchDetail]) -> Int {
        let calendar = Calendar.current
        func weekStart(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
        let weeks = Set(catches.map { weekStart($0.catchRecord.caughtAt) })
        guard !weeks.isEmpty else { return 0 }

        let sorted = weeks.sorted(by: >)
        let thisWeek = weekStart(.now)

        // Active only if the most recent catch week is this week or last week.
        guard let mostRecent = sorted.first,
              let gap = calendar.dateComponents([.day], from: mostRecent, to: thisWeek).day,
              gap <= 7 else {
            return 0
        }

        var streak = 1
        for i in 1..<sorted.count {
            guard let diff = calendar.dateComponents([.day], from: sorted[i], to: sorted[i - 1]).day else { break }
            if diff == 7 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
}

struct FishingStreakView: View {
    let catches: [CatchDetail]

    private var streakWeeks: Int {
        BadgeDefinition.streakWeeks(from: catches)
    }

    var body: some View {
        if streakWeeks > 0 {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text("\(streakWeeks)-week fishing streak!")
                        .font(.subheadline.bold())
                    Text(streakWeeks == 1 ? "Fish again next week to keep it" : "Keep it going")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BadgesGridView: View {
    let catches: [CatchDetail]
    @State private var selected: BadgeDefinition?

    private var streakWeeks: Int {
        BadgeDefinition.streakWeeks(from: catches)
    }

    private var allBadges: [BadgeDefinition] {
        BadgeDefinition.compute(from: catches, streakWeeks: streakWeeks)
    }

    private var earnedBadges: [BadgeDefinition] {
        allBadges.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }

    private var lockedBadges: [BadgeDefinition] {
        // Hidden badges never tease themselves — locked lists skip them.
        allBadges.filter { !$0.earned && !$0.hidden }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !earnedBadges.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 10) {
                    ForEach(earnedBadges, id: \.title) { badge in
                        Button { selected = badge } label: { badgeCell(badge) }
                            .buttonStyle(.plain)
                    }
                }
            }

            if !lockedBadges.isEmpty {
                Text("Locked")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 10) {
                    // Show every locked badge — the ladder is the motivation.
                    ForEach(lockedBadges, id: \.title) { badge in
                        Button { selected = badge } label: { badgeCell(badge) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    private func badgeCell(_ badge: BadgeDefinition) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(badge.earned ? badge.rarity.color.opacity(0.15) : Color.secondary.opacity(0.08))
                    .frame(width: 75, height: 60)
                VStack(spacing: 3) {
                    Image(systemName: badge.icon)
                        .font(.title3)
                        .foregroundStyle(badge.earned ? badge.rarity.color : Color.secondary.opacity(0.4))
                    Text(badge.rarity.label)
                        .font(.system(size: 7, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(badge.earned ? badge.rarity.color : Color.secondary.opacity(0.4))
                }
            }
            Text(badge.title)
                .font(.system(size: 8).bold())
                .foregroundStyle(badge.earned ? .primary : Color.secondary.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(badge.earned ? 1.0 : 0.6)
    }
}

/// Compact achievements card for a profile: your top earned badges (by rarity)
/// as tappable bubbles, plus a "Show all" that opens the full grid. Each bubble
/// opens the same explanatory modal.
struct AchievementsCard: View {
    let catches: [CatchDetail]
    var topCount = 5
    @State private var selected: BadgeDefinition?
    @State private var showingAll = false

    private var streakWeeks: Int { BadgeDefinition.streakWeeks(from: catches) }
    private var allBadges: [BadgeDefinition] {
        BadgeDefinition.compute(from: catches, streakWeeks: streakWeeks)
    }
    private var earned: [BadgeDefinition] {
        allBadges.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Achievements", systemImage: "trophy.fill").font(.headline)
                Spacer()
                // Hidden badges only count once earned — no spoiler in the tally.
                Text("\(earned.count)/\(allBadges.filter { $0.earned || !$0.hidden }.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if earned.isEmpty {
                Text("No badges yet — log catches, explore new spots and species to start earning them.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ForEach(earned.prefix(topCount)) { badge in
                        Button { selected = badge } label: { bubble(badge) }
                            .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }

            Button { showingAll = true } label: {
                Label("Show all achievements", systemImage: "chevron.right")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge)
                .presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                ScrollView { BadgesGridView(catches: catches).padding() }
                    .navigationTitle("Achievements")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    private func bubble(_ badge: BadgeDefinition) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(badge.rarity.color.opacity(0.18)).frame(width: 46, height: 46)
                Circle().stroke(badge.rarity.color.opacity(0.8), lineWidth: 2).frame(width: 46, height: 46)
                Image(systemName: badge.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(badge.rarity.color)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(badge.title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1).frame(width: 48)
        }
    }
}

/// A friendly modal explaining a badge: its icon, rarity, how it's earned, and
/// whether you've unlocked it yet.
struct BadgeDetailView: View {
    let badge: BadgeDefinition
    @Environment(\.dismiss) private var dismiss

    private var tint: Color { badge.rarity.color }

    var body: some View {
        VStack(spacing: 0) {
            // Hero medallion on a soft rarity-tinted wash.
            ZStack {
                RadialGradient(colors: [tint.opacity(badge.earned ? 0.35 : 0.12), .clear],
                               center: .center, startRadius: 4, endRadius: 170)
                ZStack {
                    Circle()
                        .fill(tint.opacity(badge.earned ? 0.18 : 0.08))
                        .frame(width: 116, height: 116)
                    Circle()
                        .stroke(tint.opacity(badge.earned ? 0.9 : 0.3), lineWidth: 3)
                        .frame(width: 116, height: 116)
                    Image(systemName: badge.icon)
                        .font(.system(size: 46))
                        .foregroundStyle(badge.earned ? tint : Color.secondary.opacity(0.45))
                        .symbolRenderingMode(.hierarchical)
                    if !badge.earned {
                        Image(systemName: "lock.fill")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(6).background(.ultraThinMaterial, in: Circle())
                            .offset(x: 40, y: 40)
                    }
                }
                .shadow(color: badge.earned ? tint.opacity(0.4) : .clear, radius: 12)
            }
            .frame(height: 180)

            VStack(spacing: 10) {
                Text(badge.title).font(.title2.bold())

                Text(badge.rarity.label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(tint.opacity(0.15), in: Capsule())

                Text(badge.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 2)

                Label(badge.earned ? "Unlocked" : "Not earned yet",
                      systemImage: badge.earned ? "checkmark.seal.fill" : "hourglass")
                    .font(.subheadline.bold())
                    .foregroundStyle(badge.earned ? .green : .secondary)
                    .padding(.top, 4)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).labelStyle(.prominentButton).tint(CurrentsTheme.accent)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}
