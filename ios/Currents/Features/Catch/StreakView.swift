import SwiftUI

/// The weekly streak worked out from catch dates: a week (Monday to Sunday)
/// counts when at least one catch was logged in it.
struct StreakStats {
    let current: Int
    let best: Int
    let bestStart: Date?
    let bestEnd: Date?
    let currentStart: Date?
    let fishedThisWeek: Bool
    let weeks: Set<Date>

    init(catches: [CatchDetail]) {
        let cal = Calendar.current
        func weekStart(_ date: Date) -> Date {
            cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        }
        let weeks = Set(catches.map { weekStart($0.catchRecord.caughtAt) })
        self.weeks = weeks
        let thisWeek = weekStart(.now)
        fishedThisWeek = weeks.contains(thisWeek)
        current = BadgeDefinition.streakWeeks(from: catches)

        // Longest run of back-to-back weeks.
        let sorted = weeks.sorted()
        var best = 0, run = 0
        var runStart: Date?, bestStart: Date?, bestEnd: Date?
        var previous: Date?
        for w in sorted {
            // One calendar week on rather than seven days: a week holding a
            // clock change is an hour short or long.
            if let p = previous, BadgeDefinition.adjacentWeek(1, to: p, calendar: cal) == w {
                run += 1
            } else {
                run = 1
                runStart = w
            }
            if run > best {
                best = run
                bestStart = runStart
                bestEnd = w
            }
            previous = w
        }
        self.best = best
        self.bestStart = bestStart
        self.bestEnd = bestEnd

        // The live run ends this week or last week (see streakWeeks).
        if current > 0, let latest = sorted.last {
            currentStart = BadgeDefinition.adjacentWeek(1 - current, to: latest, calendar: cal)
        } else {
            currentStart = nil
        }
    }
}

/// The streak page, pushed from the Logbook's Streak card.
struct StreakView: View {
    let catches: [CatchDetail]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPlanner = false
    @State private var selected: BadgeDefinition?
    @State private var appeared = false

    private static let shown = 16

    var body: some View {
        let stats = StreakStats(catches: catches)
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: stats.current)
        let metrics = BadgeMetrics(catches: catches, streakWeeks: stats.current)
        // Streak badges come cheapest first, so this is the next one to earn.
        let next = badges.first { $0.spec?.metric == .streakWeeks && !$0.earned }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    DetailHeader(over: "Weekly streak",
                                 title: "\(stats.current) \(stats.current == 1 ? "week" : "weeks")",
                                 subtitle: subtitle(stats))
                    flame
                        .padding(.trailing, DS.gutter)
                }

                Button {
                    showingPlanner = true
                } label: {
                    Label("Plan this week's session", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.dsPrimary)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)

                SectionTitle("Last \(Self.shown) weeks")
                    .padding(.top, DS.Space.s8)
                weekStrip(stats)
                    .padding(.horizontal, DS.gutter)

                statTiles(stats)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s6)

                if let next, let progress = metrics.progress(for: next.title) {
                    SectionTitle("Next badge")
                        .padding(.top, DS.Space.s8)
                    Button {
                        selected = next
                    } label: {
                        VStack(spacing: 0) {
                            ArtRow(title: next.displayName,
                                   subtitle: "\(Int(progress.target)) weeks in a row, \(next.rarity.label.lowercased())") {
                                BadgeMedal(badge: next, size: 52)
                            } trailing: {
                                Text("\(min(stats.current, Int(progress.target))) of \(Int(progress.target))")
                                    .monospacedDigit()
                                    .foregroundStyle(.dsText2)
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

                SectionFoot("A week counts when you log a catch, Monday to Sunday.")
                    .padding(.top, DS.Space.s6)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .logbookPageTitle("Streak")
        .sheet(isPresented: $showingPlanner) { PlanSessionSheet() }
        .sheet(item: $selected) { badge in
            BadgeDetailView(badge: badge, progress: metrics.progress(for: badge.title))
        }
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(DS.Motion.easeOut) { appeared = true }
            }
        }
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .font(.largeTitle.weight(.semibold))
            .imageScale(.large)
            .foregroundStyle(Color.dsScoreLow)
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            .frame(width: 84, height: 84)
            .background(Color.dsScoreLow.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }

    private func subtitle(_ stats: StreakStats) -> String {
        if stats.fishedThisWeek { return "You fished this week. Keep it going next week." }
        let cal = Calendar.current
        let sunday = cal.dateInterval(of: .weekOfYear, for: .now).map { $0.end.addingTimeInterval(-1) } ?? .now
        let day = LogbookFormat.longDay(sunday)
        return stats.current > 0
            ? "Log a catch by \(day) to make it \(stats.current + 1)."
            : "Log a catch by \(day) to start a streak."
    }

    private func weekStrip(_ stats: StreakStats) -> some View {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? cal.startOfDay(for: .now)
        let cells: [Date] = (0..<Self.shown).reversed().compactMap {
            cal.date(byAdding: .day, value: -7 * $0, to: thisWeek)
        }
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, week in
                    let on = stats.weeks.contains(week)
                    let now = week == thisWeek
                    RoundedRectangle(cornerRadius: DS.Radius.thumb / 3, style: .continuous)
                        .fill(on ? Color.dsScoreLow : Color.dsFill)
                        .overlay {
                            if now {
                                RoundedRectangle(cornerRadius: DS.Radius.thumb / 3, style: .continuous)
                                    .strokeBorder(on ? Color.dsText : Color.dsText3, lineWidth: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .scaleEffect(y: appeared ? 1 : 0.2, anchor: .bottom)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? nil : DS.Motion.easeOut.delay(Double(i) * 0.03), value: appeared)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fished in \(cells.filter { stats.weeks.contains($0) }.count) of the last \(Self.shown) weeks")
            HStack {
                Text(cells.first.map { LogbookFormat.shortDay($0) } ?? "")
                Spacer()
                Text("This week")
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
        }
    }

    /// Current and longest streak, and this week, as three equal tiles.
    private func statTiles(_ stats: StreakStats) -> some View {
        let since = stats.current > 0 ? stats.currentStart.map { "Since \(LogbookFormat.shortDay($0))" } : nil
        var longestRun: String?
        if let s = stats.bestStart, stats.best > 1 {
            longestRun = "From \(LogbookFormat.shortDay(s))"
        }
        return HStack(spacing: 10) {
            StatTile("Current", systemImage: "flame.fill", tint: .dsScoreLow,
                     value: "\(stats.current)", unit: stats.current == 1 ? "week" : "weeks",
                     footnote: since ?? "None yet", width: nil)
            StatTile("Longest", systemImage: "trophy.fill", tint: DS.ink(.dsScoreFair),
                     value: "\(stats.best)", unit: stats.best == 1 ? "week" : "weeks",
                     footnote: longestRun, width: nil)
            StatTile("This week", systemImage: stats.fishedThisWeek ? "checkmark.circle.fill" : "circle.dashed",
                     tint: stats.fishedThisWeek ? .dsScoreGood : .dsText3,
                     value: stats.fishedThisWeek ? "Fished" : "Not yet", width: nil)
        }
    }
}
