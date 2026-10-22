import SwiftUI

// MARK: - Progress

/// How far a badge is from being earned, for the badge sheet's progress bar
/// and the "closest" hint.
struct BadgeProgress {
    let value: Double
    let target: Double
    let text: String

    var fraction: Double { target > 0 ? min(1, max(0, value / target)) : 0 }
}

/// The numbers BadgeDefinition.compute works from, kept so a locked badge can
/// say how close it is. The targets mirror the thresholds in compute.
struct BadgeMetrics {
    let total: Int
    let species: Int
    let spots: Int
    let released: Int
    let withPhoto: Int
    let heaviest: Double
    let longest: Double
    let highScore: Int
    let uniqueMonths: Int
    let maxPerDay: Int
    let weekend: Bool
    let night: Bool
    let dawn: Bool
    let streak: Int

    init(catches: [CatchDetail], streakWeeks: Int) {
        let cal = Calendar.current
        total = catches.count
        species = Set(catches.compactMap { $0.species?.id }).count
        spots = Set(catches.compactMap { $0.spot?.id }).count
        released = catches.filter { $0.catchRecord.released }.count
        withPhoto = catches.filter { !$0.catchRecord.allPhotoPaths.isEmpty }.count
        heaviest = catches.compactMap(\.catchRecord.weightKg).max() ?? 0
        longest = catches.compactMap(\.catchRecord.lengthCm).max() ?? 0
        highScore = catches.compactMap(\.catchRecord.forecastScoreAtCapture).max() ?? 0
        uniqueMonths = Set(catches.map { cal.component(.month, from: $0.catchRecord.caughtAt) }).count
        maxPerDay = Dictionary(grouping: catches, by: { cal.startOfDay(for: $0.catchRecord.caughtAt) })
            .values.map(\.count).max() ?? 0
        weekend = catches.contains { cal.isDateInWeekend($0.catchRecord.caughtAt) }
        let hours = catches.map { cal.component(.hour, from: $0.catchRecord.caughtAt) }
        night = hours.contains { $0 < 5 || $0 >= 22 }
        dawn = hours.contains { $0 >= 5 && $0 < 7 }
        streak = streakWeeks
    }

    private enum Metric { case total, species, spots, released, photos, kg, cm, score, months, perDay, streak, weekend, night, dawn }

    private static let targets: [String: (Metric, Double)] = [
        "First Catch": (.total, 1), "Snap Happy": (.photos, 3), "Marked It": (.spots, 1),
        "Good Sport": (.released, 3), "Keeper": (.kg, 1), "Doubleheader": (.perDay, 2),
        "Weekend Warrior": (.weekend, 1),
        "10 Club": (.total, 10), "Quarter Century": (.total, 25), "5 Species": (.species, 5),
        "Explorer": (.spots, 3), "Photographer": (.photos, 10), "Hot Streak": (.streak, 2),
        "Conservationist": (.released, 10), "Hat Trick": (.perDay, 3), "Solid Fish": (.kg, 2),
        "Four Seasons": (.months, 4),
        "50 Catches": (.total, 50), "Night Owl": (.night, 1), "Dawn Patrol": (.dawn, 1),
        "Heavy Hitter": (.kg, 5), "Long One": (.cm, 50), "Diversified": (.species, 10),
        "On Fire": (.streak, 4), "Full Stringer": (.perDay, 5), "Wanderer": (.spots, 5),
        "Sharp Eye": (.score, 75), "Release Artist": (.released, 25),
        "Century": (.total, 100), "Nomad": (.spots, 8), "Perfect Read": (.score, 85),
        "Year-Round": (.months, 8), "Monster": (.kg, 12), "Portfolio": (.photos, 35),
        "Big Day": (.perDay, 8), "Relentless": (.streak, 8), "Meter Class": (.cm, 80),
        "Collector": (.species, 15),
        "Double Century": (.total, 200), "500 Club": (.total, 500), "Species Master": (.species, 25),
        "Unstoppable": (.streak, 12), "Trophy Hunter": (.kg, 30), "Meter Monster": (.cm, 100),
        "Water Guardian": (.released, 100), "Shutter Legend": (.photos, 100), "World Traveler": (.spots, 15),
        "Thousand Club": (.total, 1000), "Leviathan": (.kg, 50), "Master of All Waters": (.species, 50),
        "Eternal Flame": (.streak, 26),
    ]

    /// Progress toward a badge, or nil for the secret one.
    func progress(for title: String) -> BadgeProgress? {
        guard let entry = Self.targets[title] else { return nil }
        let (metric, target) = entry
        func count(_ v: Int, _ unit: String) -> BadgeProgress {
            BadgeProgress(value: Double(v), target: target,
                          text: "\(min(v, Int(target))) of \(Int(target)) \(unit)")
        }
        func yes(_ done: Bool) -> BadgeProgress {
            BadgeProgress(value: done ? 1 : 0, target: 1, text: done ? "Done" : "Not yet")
        }
        switch metric {
        case .total: return count(total, "catches")
        case .species: return count(species, "species")
        case .spots: return count(spots, target == 1 ? "spot" : "spots")
        case .released: return count(released, "released")
        case .photos: return count(withPhoto, "with photos")
        case .months: return count(uniqueMonths, "months")
        case .perDay: return count(maxPerDay, "in a day")
        case .streak: return count(streak, "weeks in a row")
        case .kg:
            return BadgeProgress(value: heaviest, target: target,
                                 text: heaviest > 0
                                    ? "Heaviest so far \(Units.weight(kg: heaviest)), needs \(Units.weight(kg: target))"
                                    : "Needs a fish of \(Units.weight(kg: target))")
        case .cm:
            return BadgeProgress(value: longest, target: target,
                                 text: longest > 0
                                    ? "Longest so far \(Units.length(cm: longest)), needs \(Units.length(cm: target))"
                                    : "Needs a fish of \(Units.length(cm: target))")
        case .score:
            return BadgeProgress(value: Double(highScore), target: target,
                                 text: "Best bite score so far \(highScore), needs \(Int(target))")
        case .weekend: return yes(weekend)
        case .night: return yes(night)
        case .dawn: return yes(dawn)
        }
    }

    /// The locked, visible badge nearest to being earned.
    func closest(in badges: [BadgeDefinition]) -> BadgeDefinition? {
        var best: BadgeDefinition?
        var bestFraction: Double = -1
        for badge in badges where !badge.earned && !badge.hidden {
            guard let p = progress(for: badge.title) else { continue }
            let fraction: Double = p.fraction
            let isCloser = fraction > bestFraction
            let tieWithLowerRarity = fraction == bestFraction
                && badge.rarity.rawValue < (best?.rarity.rawValue ?? Int.max)
            if isCloser || tieWithLowerRarity {
                best = badge
                bestFraction = fraction
            }
        }
        return best
    }
}

// MARK: - Achievements page

/// Every badge, earned first, with a rarity tally. Pushed from the Logbook's
/// Badges card.
struct AchievementsView: View {
    let catches: [CatchDetail]
    @State private var selected: BadgeDefinition?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var streak: Int { BadgeDefinition.streakWeeks(from: catches) }

    var body: some View {
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: streak)
        let visible = badges.filter { $0.earned || !$0.hidden }
        let earned = badges.filter(\.earned).sorted { $0.rarity.rawValue > $1.rarity.rawValue }
        let locked = badges.filter { !$0.earned && !$0.hidden }.sorted { $0.rarity.rawValue < $1.rarity.rawValue }
        let metrics = BadgeMetrics(catches: catches, streakWeeks: streak)
        let next = metrics.closest(in: badges)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: "Achievements",
                             title: "\(earned.count) of \(visible.count)",
                             subtitle: "Tap a badge to see what it takes.")

                rarityTally(visible)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s5)

                if let next, let progress = metrics.progress(for: next.title) {
                    SectionTitle("Closest")
                        .padding(.top, DS.Space.s8)
                    Button {
                        selected = next
                    } label: {
                        VStack(spacing: 0) {
                            ArtRow(over: next.rarity.label, title: next.title, subtitle: progress.text) {
                                BadgeMedal(badge: next, size: 52)
                            }
                            LogbookProgressBar(fraction: appeared ? progress.fraction : 0, tint: next.rarity.color)
                                .padding(.leading, DS.gutter + 52 + 14)
                                .padding(.trailing, DS.gutter)
                                .padding(.bottom, DS.Space.s2)
                                .animation(reduceMotion ? nil : DS.Motion.easeOut, value: appeared)
                        }
                    }
                    .buttonStyle(.dsRow)
                }

                if !earned.isEmpty {
                    SectionTitle("Earned", detail: "\(earned.count)")
                        .padding(.top, DS.Space.s8)
                    BadgeMedalGrid(badges: earned) { selected = $0 }
                }

                if !locked.isEmpty {
                    SectionTitle("Locked", detail: "\(locked.count)")
                        .padding(.top, DS.Space.s8)
                    BadgeMedalGrid(badges: locked) { selected = $0 }
                    SectionFoot("Secret badges appear once you find them.")
                        .padding(.top, DS.Space.s2)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.dsScoreFair)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge, progress: metrics.progress(for: badge.title))
        }
        .sensoryFeedback(.selection, trigger: selected?.id)
        .onAppear { appeared = true }
    }

    /// Earned out of total for each rarity, with a bar in the rarity colour.
    /// Three across, wrapping to a second row.
    private func rarityTally(_ badges: [BadgeDefinition]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(BadgeRarity.allCases, id: \.self) { rarity in
                let tier = badges.filter { $0.rarity == rarity }
                if !tier.isEmpty {
                    let got = tier.filter(\.earned).count
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rarity.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(got) of \(tier.count)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                            .lineLimit(1)
                        LogbookProgressBar(fraction: appeared ? Double(got) / Double(tier.count) : 0,
                                           tint: rarity.color, height: 6)
                            .animation(reduceMotion ? nil : DS.Motion.easeOut, value: appeared)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(rarity.label), \(got) of \(tier.count) earned")
                }
            }
        }
    }
}
