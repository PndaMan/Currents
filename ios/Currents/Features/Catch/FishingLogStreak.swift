import SwiftUI

enum BadgeRarity: String, Comparable {
    case common, uncommon, rare, epic, legendary

    static func < (lhs: BadgeRarity, rhs: BadgeRarity) -> Bool {
        let order: [BadgeRarity] = [.common, .uncommon, .rare, .epic, .legendary]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    var color: Color {
        switch self {
        case .common:    return .gray
        case .uncommon:  return CurrentsTheme.accent
        case .rare:      return .cyan
        case .epic:      return .purple
        case .legendary: return .yellow
        }
    }

    var label: String { rawValue.capitalized }
}

struct BadgeDefinition {
    let icon: String
    let title: String
    let rarity: BadgeRarity
    let earned: Bool

    static func compute(from catches: [CatchDetail], streakDays: Int) -> [BadgeDefinition] {
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
            BadgeDefinition(icon: "flame.fill", title: "Hot Streak", rarity: .uncommon, earned: streakDays >= 3),
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
            BadgeDefinition(icon: "flame.fill", title: "On Fire", rarity: .rare, earned: streakDays >= 7),

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
            BadgeDefinition(icon: "flame.fill", title: "Unstoppable", rarity: .legendary, earned: streakDays >= 30),
            BadgeDefinition(icon: "scalemass", title: "Trophy Hunter", rarity: .legendary, earned: heaviest >= 30),
        ]
    }

    static func streakDays(from catches: [CatchDetail]) -> Int {
        let calendar = Calendar.current
        let dates = Set(catches.map { calendar.startOfDay(for: $0.catchRecord.caughtAt) })
        guard !dates.isEmpty else { return 0 }

        let sorted = dates.sorted(by: >)
        let today = calendar.startOfDay(for: .now)

        guard let first = sorted.first,
              calendar.dateComponents([.day], from: first, to: today).day! <= 1 else {
            return 0
        }

        var streak = 1
        for i in 1..<sorted.count {
            let diff = calendar.dateComponents([.day], from: sorted[i], to: sorted[i-1]).day!
            if diff <= 1 {
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

    private var streakDays: Int {
        BadgeDefinition.streakDays(from: catches)
    }

    var body: some View {
        if streakDays > 0 {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                    .font(.title3)
                VStack(alignment: .leading) {
                    Text("\(streakDays)-day fishing streak!")
                        .font(.subheadline.bold())
                    Text("Keep it going")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BadgesGridView: View {
    let catches: [CatchDetail]

    private var streakDays: Int {
        BadgeDefinition.streakDays(from: catches)
    }

    private var allBadges: [BadgeDefinition] {
        BadgeDefinition.compute(from: catches, streakDays: streakDays)
    }

    var body: some View {
        let earned = allBadges.filter(\.earned).sorted { $0.rarity > $1.rarity }
        let locked = allBadges.filter { !$0.earned }.sorted { $0.rarity < $1.rarity }

        VStack(alignment: .leading, spacing: 12) {
            if !earned.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 10) {
                    ForEach(earned, id: \.title) { badge in
                        badgeCell(badge)
                    }
                }
            }

            if !locked.isEmpty {
                Text("Locked")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 10) {
                    ForEach(locked.prefix(8), id: \.title) { badge in
                        badgeCell(badge)
                    }
                }
            }
        }
        .padding(.bottom, 6)
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
                        .foregroundStyle(badge.earned ? badge.rarity.color : .secondary.opacity(0.3))
                    Text(badge.rarity.label)
                        .font(.system(size: 7, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(badge.earned ? badge.rarity.color : .secondary.opacity(0.3))
                }
            }
            Text(badge.title)
                .font(.system(size: 8).bold())
                .foregroundStyle(badge.earned ? .primary : .secondary.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(badge.earned ? 1.0 : 0.6)
    }
}
