import SwiftUI

/// Displays the user's fishing streak and achievement badges.
struct FishingStreakView: View {
    let catches: [CatchDetail]

    private var streakDays: Int {
        let calendar = Calendar.current
        let dates = Set(catches.map { calendar.startOfDay(for: $0.catchRecord.caughtAt) })
        guard !dates.isEmpty else { return 0 }

        let sorted = dates.sorted(by: >)
        let today = calendar.startOfDay(for: .now)

        // Check if most recent is today or yesterday
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

    private var badges: [(icon: String, title: String, earned: Bool)] {
        let total = catches.count
        let species = Set(catches.compactMap { $0.species?.id }).count
        let spots = Set(catches.compactMap { $0.spot?.id }).count
        let released = catches.filter { $0.catchRecord.released }.count
        let withPhoto = catches.filter { $0.catchRecord.photoPath != nil }.count

        return [
            ("fish.fill", "First Catch", total >= 1),
            ("trophy.fill", "10 Club", total >= 10),
            ("star.fill", "50 Catches", total >= 50),
            ("crown.fill", "Century", total >= 100),
            ("leaf.fill", "5 Species", species >= 5),
            ("globe.americas.fill", "Explorer", spots >= 3),
            ("arrow.uturn.backward", "Conservationist", released >= 10),
            ("camera.fill", "Photographer", withPhoto >= 5),
            ("flame.fill", "Hot Streak", streakDays >= 3),
            ("moon.fill", "Night Owl", catches.contains {
                Calendar.current.component(.hour, from: $0.catchRecord.caughtAt) < 5 ||
                Calendar.current.component(.hour, from: $0.catchRecord.caughtAt) >= 22
            }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Streak
            if streakDays > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
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

            // Badges
            let earned = badges.filter(\.earned)
            if !earned.isEmpty {
                Text("Badges")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
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
            }
        }
    }
}
