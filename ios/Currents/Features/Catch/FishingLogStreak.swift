import SwiftUI

enum BadgeRarity: Int, CaseIterable {
    case common = 0
    case uncommon = 1
    case rare = 2
    case epic = 3
    case legendary = 4

    var color: Color {
        switch self {
        case .common:    return .gray
        case .uncommon:  return CurrentsTheme.accent
        case .rare:      return .cyan
        case .epic:      return .purple
        case .legendary: return .yellow
        }
    }

    var label: String {
        switch self {
        case .common:    return "Common"
        case .uncommon:  return "Uncommon"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        }
    }
}

struct BadgeDefinition: Identifiable {
    let icon: String
    let title: String
    let rarity: BadgeRarity
    let earned: Bool

    var id: String { title }

    /// A friendly one-liner explaining how the badge is earned, shown in the
    /// tap-to-open detail modal.
    var explanation: String {
        switch title {
        case "First Catch":     return "Log your very first catch in Currents."
        case "Snap Happy":      return "Add a photo to 3 of your catches."
        case "Marked It":       return "Save your first fishing spot on the map."
        case "Good Sport":      return "Release 3 catches back to the water."
        case "10 Club":         return "Log 10 catches."
        case "5 Species":       return "Catch 5 different species."
        case "Explorer":        return "Fish at 3 different saved spots."
        case "Photographer":    return "Add photos to 10 of your catches."
        case "Hot Streak":      return "Log a catch in 2 back-to-back weeks."
        case "Conservationist": return "Release 10 catches."
        case "50 Catches":      return "Log 50 catches."
        case "Night Owl":       return "Log a catch late at night (10pm–5am)."
        case "Dawn Patrol":     return "Log a catch at first light (5–7am)."
        case "Heavy Hitter":    return "Land a fish weighing 5 kg (11 lb) or more."
        case "Long One":        return "Land a fish 50 cm (20 in) or longer."
        case "Diversified":     return "Catch 10 different species."
        case "On Fire":         return "Keep a weekly fishing streak alive for 4 weeks."
        case "Century":         return "Log 100 catches."
        case "Nomad":           return "Fish at 10 different saved spots."
        case "Perfect Read":    return "Land a catch when the bite score was 90 or higher."
        case "Year-Round":      return "Log catches in 10 different months of the year."
        case "Monster":         return "Land a fish weighing 15 kg (33 lb) or more."
        case "Portfolio":       return "Add photos to 50 of your catches."
        case "500 Club":        return "Log 500 catches."
        case "Species Master":  return "Catch 25 different species."
        case "Unstoppable":     return "Keep a weekly fishing streak alive for 12 weeks."
        case "Trophy Hunter":   return "Land a fish weighing 30 kg (66 lb) or more."
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

        return [
            // Common
            BadgeDefinition(icon: "fish.fill", title: "First Catch", rarity: .common, earned: total >= 1),
            BadgeDefinition(icon: "camera.fill", title: "Snap Happy", rarity: .common, earned: withPhoto >= 3),
            BadgeDefinition(icon: "mappin.circle.fill", title: "Marked It", rarity: .common, earned: spots >= 1),
            BadgeDefinition(icon: "arrow.uturn.backward", title: "Good Sport", rarity: .common, earned: released >= 3),

            // Uncommon
            BadgeDefinition(icon: "trophy.fill", title: "10 Club", rarity: .uncommon, earned: total >= 10),
            BadgeDefinition(icon: "leaf.fill", title: "5 Species", rarity: .uncommon, earned: species >= 5),
            BadgeDefinition(icon: "globe.americas.fill", title: "Explorer", rarity: .uncommon, earned: spots >= 3),
            BadgeDefinition(icon: "camera.fill", title: "Photographer", rarity: .uncommon, earned: withPhoto >= 10),
            BadgeDefinition(icon: "flame.fill", title: "Hot Streak", rarity: .uncommon, earned: streakWeeks >= 2),
            BadgeDefinition(icon: "arrow.uturn.backward.circle.fill", title: "Conservationist", rarity: .uncommon, earned: released >= 10),

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

            // Epic
            BadgeDefinition(icon: "crown.fill", title: "Century", rarity: .epic, earned: total >= 100),
            BadgeDefinition(icon: "globe.americas.fill", title: "Nomad", rarity: .epic, earned: spots >= 10),
            BadgeDefinition(icon: "gauge.medium", title: "Perfect Read", rarity: .epic, earned: highScore >= 90),
            BadgeDefinition(icon: "calendar.badge.checkmark", title: "Year-Round", rarity: .epic, earned: uniqueMonths >= 10),
            BadgeDefinition(icon: "scalemass", title: "Monster", rarity: .epic, earned: heaviest >= 15),
            BadgeDefinition(icon: "camera.fill", title: "Portfolio", rarity: .epic, earned: withPhoto >= 50),

            // Legendary
            BadgeDefinition(icon: "sparkles", title: "500 Club", rarity: .legendary, earned: total >= 500),
            BadgeDefinition(icon: "crown.fill", title: "Species Master", rarity: .legendary, earned: species >= 25),
            BadgeDefinition(icon: "flame.fill", title: "Unstoppable", rarity: .legendary, earned: streakWeeks >= 12),
            BadgeDefinition(icon: "scalemass", title: "Trophy Hunter", rarity: .legendary, earned: heaviest >= 30),
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
        allBadges.filter { !$0.earned }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
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
                    ForEach(Array(lockedBadges.prefix(8)), id: \.title) { badge in
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
                Text("\(earned.count)/\(allBadges.count)")
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
            .buttonStyle(.borderedProminent).tint(CurrentsTheme.accent)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}
