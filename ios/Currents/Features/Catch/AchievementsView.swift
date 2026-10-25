import SwiftUI

// MARK: - Progress

/// How far a locked badge is from being earned, for the badge sheet's
/// progress bar and the "closest" row.
struct BadgeProgress {
    let value: Double
    let target: Double
    let text: String
    /// A badge that is earned or not, with nothing in between (a weekend,
    /// night or dawn catch): no bar, only what it needs.
    var isYesNo = false

    var fraction: Double { target > 0 ? min(1, max(0, value / target)) : 0 }
}

extension BadgeMetrics {
    /// Progress toward a badge, or nil for the secret one.
    func progress(for title: String) -> BadgeProgress? {
        guard let spec = BadgeDefinition.specsByTitle[title], !spec.metric.isHidden else { return nil }
        let target = spec.target
        let goal = Int(target)
        func count(_ have: Double, _ unit: String) -> BadgeProgress {
            BadgeProgress(value: have, target: target, text: "\(min(Int(have), goal)) of \(goal) \(unit)")
        }
        func needs(_ text: String) -> BadgeProgress {
            BadgeProgress(value: value(spec.metric), target: 1, text: text, isYesNo: true)
        }
        func hour(_ h: Int) -> String { ForecastFormat.hour(h, use24: ForecastFormat.use24) }
        switch spec.metric {
        case .catches: return count(value(.catches), "catches")
        case .species: return count(value(.species), "species")
        case .spots: return count(value(.spots), goal == 1 ? "saved spot fished" : "saved spots fished")
        case .released: return count(value(.released), "released")
        case .photos: return count(value(.photos), "catches with photos")
        case .months: return count(value(.months), "different months")
        case .bestDay: return count(value(.bestDay), "catches in one day")
        // A new run has to be built, so the live streak is what counts here.
        case .streakWeeks: return count(Double(currentStreak), "weeks in a row")
        case .weightKg: return sizeProgress(value(.weightKg), target, label: "Heaviest", format: Self.weightText)
        case .lengthCm: return sizeProgress(value(.lengthCm), target, label: "Longest", format: Self.lengthText)
        case .biteScore: return scoreProgress(value(.biteScore), target)
        case .weekend: return needs("Needs a catch on a Saturday or Sunday")
        case .night: return needs("Needs a catch between \(hour(22)) and \(hour(5))")
        case .dawn: return needs("Needs a catch between \(hour(5)) and \(hour(7))")
        case .secret, .supporter: return nil
        }
    }

    /// The best is rounded down and the target is not, so a fish just short
    /// of the target never reads as the target.
    private func sizeProgress(_ best: Double, _ target: Double, label: String,
                              format: (Double, Bool) -> String) -> BadgeProgress {
        let text = best > 0
            ? "\(label) so far \(format(best, true)), needs \(format(target, false))"
            : "Needs a fish of \(format(target, false)) or more"
        return BadgeProgress(value: best, target: target, text: text)
    }

    /// "99.5 cm" or "39.1 in", one decimal. `Units.length` rounds to whole
    /// centimetres under a metre, which turned 99.5 cm into the 100 cm target.
    private static func lengthText(_ cm: Double, roundingDown: Bool) -> String {
        let cmPerUnit = Units.isImperial ? 2.54 : 1
        var shown = cm / cmPerUnit
        if roundingDown { shown = (shown * 10 + 1e-6).rounded(.down) / 10 }
        let (value, unit) = Units.lengthParts(cm: shown * cmPerUnit)
        return "\(value) \(unit)"
    }

    /// "9.84 kg" or "21.69 lb", two decimals, rounded down the same way.
    private static func weightText(_ kg: Double, roundingDown: Bool) -> String {
        let unitsPerKg = Units.isImperial ? 2.2046226 : 1
        var shown = kg * unitsPerKg
        if roundingDown { shown = (shown * 100 + 1e-6).rounded(.down) / 100 }
        let (value, unit) = Units.weightParts(kg: shown / unitsPerKg)
        return "\(value) \(unit)"
    }

    private func scoreProgress(_ best: Double, _ target: Double) -> BadgeProgress {
        let text = best > 0
            ? "Best bite score so far \(Int(best)), needs \(Int(target))"
            : "Needs a catch at a bite score of \(Int(target)) or more"
        return BadgeProgress(value: best, target: target, text: text)
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

// MARK: - Summary

/// Everything the achievements page shows, worked out once per set of
/// catches instead of on every render.
struct AchievementsSummary {
    let metrics: BadgeMetrics
    let earnedCount: Int
    /// Earned plus locked, leaving out secret badges not yet found.
    let visibleCount: Int
    let closest: BadgeDefinition?
    let shelves: [BadgeShelf]
    /// A secret badge is still waiting to be found.
    let secretsLeft: Bool

    init(catches: [CatchDetail]) {
        let metrics = BadgeMetrics(catches: catches, streakWeeks: BadgeDefinition.streakWeeks(from: catches))
        let badges = BadgeDefinition.badges(from: metrics)
        let visible = badges.filter { $0.earned || !$0.hidden }
        self.metrics = metrics
        earnedCount = visible.filter(\.earned).count
        visibleCount = visible.count
        closest = metrics.closest(in: badges)
        shelves = BadgeGroup.allCases.compactMap { group in
            let onShelf = visible.filter { $0.group == group }
            return onShelf.isEmpty ? nil : BadgeShelf(group: group, badges: onShelf)
        }
        secretsLeft = badges.contains { $0.hidden && !$0.earned }
    }
}

/// One group of medals on the page, cheapest first.
struct BadgeShelf: Identifiable {
    let group: BadgeGroup
    let badges: [BadgeDefinition]
    var id: BadgeGroup { group }
    var earnedCount: Int { badges.filter(\.earned).count }
}

// MARK: - Achievements page

/// Every badge as a medal, shelved by what it counts (catches, species, big
/// fish and so on). A medal opens its sheet. Pushed from the Logbook's
/// Badges card and from the profile's achievements card.
struct AchievementsView: View {
    let catches: [CatchDetail]

    var body: some View {
        // Tallied here, once per set of catches. Opening a medal re-renders
        // the page below without tallying again.
        AchievementsPage(summary: AchievementsSummary(catches: catches))
    }
}

private struct AchievementsPage: View {
    let summary: AchievementsSummary
    @State private var selected: BadgeDefinition?
    // The closest badge's sizes and hours redraw when either setting changes.
    @AppStorage("units") private var units = "metric"
    @AppStorage("use24HourTime") private var use24 = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                closestRow
                shelves
                if summary.secretsLeft {
                    SectionFoot("Secret badges appear once you find them.")
                        .padding(.top, DS.Space.s4)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pageTitleFade("Badges")
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge, progress: summary.metrics.progress(for: badge.title))
        }
    }

    /// One catch earns First Catch, so nothing earned means nothing logged.
    @ViewBuilder
    private var header: some View {
        DetailHeader(over: "Badges",
                     title: "\(summary.earnedCount) of \(summary.visibleCount) earned",
                     subtitle: summary.closest == nil ? "You have earned every badge." : nil)
        if summary.earnedCount == 0 {
            InlineEmpty(systemImage: "medal", text: "No badges yet. Log a catch to earn your first.")
                .padding(.top, DS.Space.s5)
        }
    }

    @ViewBuilder
    private var closestRow: some View {
        if summary.earnedCount > 0, let next = summary.closest,
           let progress = summary.metrics.progress(for: next.title) {
            SectionTitle("Closest")
                .padding(.top, DS.Space.s6)
            Button {
                selected = next
            } label: {
                ClosestBadgeRow(badge: next, progress: progress)
            }
            .buttonStyle(.dsRow)
        }
    }

    private var shelves: some View {
        ForEach(summary.shelves) { shelf in
            SectionTitle(shelf.group.title, detail: "\(shelf.earnedCount) of \(shelf.badges.count)")
                .padding(.top, DS.Space.s8)
            BadgeMedalGrid(badges: shelf.badges) { selected = $0 }
        }
    }
}

/// The locked badge nearest to being earned: its medal, what is left and a
/// bar for anything counted.
private struct ClosestBadgeRow: View {
    let badge: BadgeDefinition
    let progress: BadgeProgress
    private let medalSize: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            ArtRow(over: badge.rarity.label, title: badge.displayName, subtitle: progress.text, chevron: true) {
                BadgeMedal(badge: badge, size: medalSize)
            }
            if !progress.isYesNo {
                // Starts under the title: ArtRow's medal plus its 14 pt gap.
                LogbookProgressBar(fraction: progress.fraction, tint: badge.rarity.color)
                    .padding(.leading, DS.gutter + medalSize + 14)
                    .padding(.trailing, DS.gutter)
                    .padding(.bottom, DS.Space.s2)
            }
        }
    }
}
