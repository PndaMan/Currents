import SwiftUI

/// Badge definition and computation shared across views
struct BadgeDefinition {
    let icon: String
    let title: String
    let earned: Bool

    static func compute(from catches: [CatchDetail], streakDays: Int) -> [BadgeDefinition] {
        let total = catches.count
        let species = Set(catches.compactMap { $0.species?.id }).count
        let spots = Set(catches.compactMap { $0.spot?.id }).count
        let released = catches.filter { $0.catchRecord.released }.count
        let withPhoto = catches.filter { !$0.catchRecord.allPhotoPaths.isEmpty }.count

        return [
            BadgeDefinition(icon: "fish.fill", title: "First Catch", earned: total >= 1),
            BadgeDefinition(icon: "trophy.fill", title: "10 Club", earned: total >= 10),
            BadgeDefinition(icon: "star.fill", title: "50 Catches", earned: total >= 50),
            BadgeDefinition(icon: "crown.fill", title: "Century", earned: total >= 100),
            BadgeDefinition(icon: "leaf.fill", title: "5 Species", earned: species >= 5),
            BadgeDefinition(icon: "globe.americas.fill", title: "Explorer", earned: spots >= 3),
            BadgeDefinition(icon: "arrow.uturn.backward", title: "Conservationist", earned: released >= 10),
            BadgeDefinition(icon: "camera.fill", title: "Photographer", earned: withPhoto >= 5),
            BadgeDefinition(icon: "flame.fill", title: "Hot Streak", earned: streakDays >= 3),
            BadgeDefinition(icon: "moon.fill", title: "Night Owl", earned: catches.contains {
                Calendar.current.component(.hour, from: $0.catchRecord.caughtAt) < 5 ||
                Calendar.current.component(.hour, from: $0.catchRecord.caughtAt) >= 22
            }),
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

/// Displays the user's fishing streak (shown in CatchesTab).
struct FishingStreakView: View {
    let catches: [CatchDetail]

    private var streakDays: Int {
        BadgeDefinition.streakDays(from: catches)
    }

    private var badges: [BadgeDefinition] {
        BadgeDefinition.compute(from: catches, streakDays: streakDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Streak
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
}

/// Badge grid shown on the Profile page
struct BadgesGridView: View {
    let catches: [CatchDetail]

    private var streakDays: Int {
        BadgeDefinition.streakDays(from: catches)
    }

    private var badges: [BadgeDefinition] {
        BadgeDefinition.compute(from: catches, streakDays: streakDays)
    }

    var earnedBadges: [BadgeDefinition] {
        badges.filter(\.earned)
    }

    var body: some View {
        let earned = earnedBadges
        if !earned.isEmpty {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 70))
            ], spacing: 8) {
                ForEach(earned, id: \.title) { badge in
                    VStack(spacing: 4) {
                        Image(systemName: badge.icon)
                            .font(.title3)
                            .foregroundStyle(.yellow)
                        Text(badge.title)
                            .font(.system(size: 9).bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 70, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.bottom, 6)
        }
    }
}
