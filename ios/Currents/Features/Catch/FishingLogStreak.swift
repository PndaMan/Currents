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
        case .common:    return .dsText2
        case .uncommon:  return .dsScoreGood
        case .rare:      return .cyan
        case .epic:      return .purple
        case .legendary: return .dsScoreFair
        case .mythic:    return .pink
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
/// name ("Century" unlocks "Centurion"). The achievement is the
/// provenance, shown when the worn title is tapped. Colours follow the
/// unlocking achievement's rarity.
struct TitleFlair: Identifiable {
    let achievement: String   // the BadgeDefinition title that unlocks it
    let name: String          // what's worn under the profile name
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
        .init(achievement: "500 Club", name: "Old Salt", rarity: .legendary, icon: "sparkles"),
        .init(achievement: "Species Master", name: "Master of Species", rarity: .legendary, icon: "crown.fill"),
        .init(achievement: "Unstoppable", name: "Unstoppable", rarity: .legendary, icon: "flame.fill"),
        .init(achievement: "Trophy Hunter", name: "Trophy Hunter", rarity: .legendary, icon: "scalemass"),
        .init(achievement: "Meter Monster", name: "Meter Monster", rarity: .legendary, icon: "ruler"),
        .init(achievement: "Water Guardian", name: "Water Guardian", rarity: .legendary, icon: "arrow.uturn.backward.circle.fill"),
        .init(achievement: "Shutter Legend", name: "Shutter Legend", rarity: .legendary, icon: "camera.fill"),
        .init(achievement: "World Traveler", name: "World Traveler", rarity: .legendary, icon: "globe.americas.fill"),
        // Mythic
        .init(achievement: "Thousand Club", name: "Thousand Legend", rarity: .mythic, icon: "sparkles"),
        .init(achievement: "Leviathan", name: "Leviathan", rarity: .mythic, icon: "scalemass"),
        .init(achievement: "Master of All Waters", name: "Master of All Waters", rarity: .mythic, icon: "crown.fill"),
        .init(achievement: "Eternal Flame", name: "Eternal Flame", rarity: .mythic, icon: "flame.fill"),
        .init(achievement: "Bass Daddy", name: "Bass Daddy", rarity: .mythic, icon: "fish.fill"),
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

    /// The secret badge shows a quote instead of how it is earned.
    static let bassDaddyQuote = "My rod is my sword, the water my kingdom, and every bass bows before the throne."
    static let bassDaddyQuoteBy = "Bass Daddy"
    var isSecretQuote: Bool { title == "Bass Daddy" }

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
        case "Night Owl":       return "Log a catch late at night, between 10 pm and 5 am."
        case "Dawn Patrol":     return "Log a catch at first light, between 5 and 7 am."
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
        case "Eternal Flame":   return "Keep a weekly fishing streak alive for 26 weeks, half a year."
        case "Bass Daddy":      return "“\(Self.bassDaddyQuote)” \(Self.bassDaddyQuoteBy)"
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

// MARK: - Badge views

/// A round badge medal in its rarity colour; locked badges are grey with a
/// small lock.
struct BadgeMedal: View {
    let badge: BadgeDefinition
    var size: CGFloat = 64
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { badge.rarity.color }

    var body: some View {
        ZStack {
            Circle()
                .fill(badge.earned ? AnyShapeStyle(tint.opacity(scheme == .dark ? 0.24 : 0.18)) : AnyShapeStyle(Color.dsFill))
            if badge.earned {
                Circle().strokeBorder(tint.opacity(0.6), lineWidth: 2)
            }
            Image(systemName: badge.icon)
                .font(.system(size: size * 0.4, weight: .semibold)) // ui-lint: allow, symbol sized to the medal
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(badge.earned ? tint : Color.dsText3)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if !badge.earned {
                Image(systemName: "lock.fill")
                    .font(.system(size: max(9, size * 0.16), weight: .bold)) // ui-lint: allow, lock sized to the medal
                    .foregroundStyle(.dsText2)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Color.dsFill2, in: Circle())
                    .overlay(Circle().strokeBorder(Color.dsBackground, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
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
                    .foregroundStyle(Color.dsScoreLow)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text("\(streakWeeks)-week streak")
                        .font(.subheadline.weight(.semibold))
                    Text(streakWeeks == 1 ? "Fish again next week to keep it" : "Keep it going")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                }
            }
        }
    }
}

/// Every badge as a four-across grid of medals: earned first, rarest first,
/// then the locked ladder. Tap one for what it takes.
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
        // Hidden badges never tease themselves; locked lists skip them.
        allBadges.filter { !$0.earned && !$0.hidden }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
    }

    var body: some View {
        let metrics = BadgeMetrics(catches: catches, streakWeeks: streakWeeks)
        VStack(alignment: .leading, spacing: 0) {
            if !earnedBadges.isEmpty {
                SectionTitle("Earned", detail: "\(earnedBadges.count)")
                BadgeMedalGrid(badges: earnedBadges) { selected = $0 }
            }
            if !lockedBadges.isEmpty {
                SectionTitle("Locked", detail: "\(lockedBadges.count)")
                    .padding(.top, DS.Space.s6)
                BadgeMedalGrid(badges: lockedBadges) { selected = $0 }
                Text("Some badges are secret and only appear once you find them.")
                    .font(.footnote)
                    .foregroundStyle(.dsText3)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
            }
        }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge, progress: metrics.progress(for: badge.title))
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }
}

/// Four medals across with their names under them.
struct BadgeMedalGrid: View {
    let badges: [BadgeDefinition]
    let onSelect: (BadgeDefinition) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                  alignment: .center, spacing: 16) {
            ForEach(badges) { badge in
                Button {
                    onSelect(badge)
                } label: {
                    VStack(spacing: 6) {
                        BadgeMedal(badge: badge)
                        Text(badge.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(badge.earned ? Color.dsText : Color.dsText2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dim)
                .accessibilityLabel("\(badge.title), \(badge.rarity.label), \(badge.earned ? "earned" : "locked")")
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}

/// Compact achievements card for a profile: your top earned badges (by rarity)
/// as tappable medals, plus a link to every badge. Each medal opens the same
/// explanatory sheet.
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
                Label("Achievements", systemImage: "medal.fill").font(.headline)
                Spacer()
                // Hidden badges only count once earned, so the tally has no spoiler.
                Text("\(earned.count) of \(allBadges.filter { $0.earned || !$0.hidden }.count)")
                    .font(.footnote).foregroundStyle(.dsText2)
            }

            if earned.isEmpty {
                Text("No badges yet. Log catches and explore new spots and species to start earning them.")
                    .font(.footnote).foregroundStyle(.dsText2)
            } else {
                HStack(spacing: 12) {
                    ForEach(earned.prefix(topCount)) { badge in
                        Button { selected = badge } label: { BadgeMedal(badge: badge, size: 46) }
                            .buttonStyle(.dim)
                            .accessibilityLabel(badge.title)
                    }
                    Spacer(minLength: 0)
                }
            }

            Button { showingAll = true } label: {
                Label("Show all achievements", systemImage: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge,
                            progress: BadgeMetrics(catches: catches, streakWeeks: streakWeeks).progress(for: badge.title))
        }
        .sheet(isPresented: $showingAll) {
            NavigationStack {
                ScrollView {
                    BadgesGridView(catches: catches)
                        .padding(.vertical, DS.Space.s4)
                }
                .dsScreenBackground()
                .navigationTitle("Achievements")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
    }
}

/// A half sheet explaining a badge: its medal, rarity, how it is earned (or
/// the secret quote), and either when it was unlocked or how close you are.
struct BadgeDetailView: View {
    let badge: BadgeDefinition
    /// How far along a locked badge is, when the caller knows the catches.
    var progress: BadgeProgress? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var tint: Color { badge.rarity.color }

    var body: some View {
        VStack(spacing: 0) {
            Text("Achievement")
                .font(.headline)
                .padding(.top, DS.Space.s5)

            BadgeMedal(badge: badge, size: 104)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .padding(.top, DS.Space.s6)

            Text(badge.rarity.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(tint.opacity(0.16), in: Capsule())
                .padding(.top, DS.Space.s3)

            Text(badge.title)
                .font(.title2.bold())
                .foregroundStyle(.dsText)
                .padding(.top, DS.Space.s2)

            Group {
                if badge.isSecretQuote {
                    VStack(spacing: 8) {
                        Text(BadgeDefinition.bassDaddyQuote)
                            .font(.callout.italic())
                            .foregroundStyle(.dsText)
                        Text(BadgeDefinition.bassDaddyQuoteBy)
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                    }
                } else {
                    Text(badge.explanation)
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)

            if badge.earned {
                Label("Unlocked", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsScoreGood)
                    .padding(.top, DS.Space.s4)
            } else if let progress {
                VStack(spacing: 8) {
                    ProgressView(value: max(0.02, progress.fraction))
                        .tint(tint)
                    Text(progress.text)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.dsText2)
                }
                .frame(maxWidth: 260)
                .padding(.top, DS.Space.s4)
            } else {
                Label("Not earned yet", systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText2)
                    .padding(.top, DS.Space.s4)
            }

            Spacer(minLength: DS.Space.s4)

            Button("Done") { dismiss() }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, DS.Space.s4)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(DS.Motion.spring) { appeared = true }
        }
    }
}
