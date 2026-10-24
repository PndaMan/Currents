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
        let cal = BadgeDefinition.weekCalendar
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    Label(stats.fishedThisWeek ? "Plan next week's session" : "Plan this week's session",
                          systemImage: "calendar.badge.plus")
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
                            ArtRow(over: next.rarity.label, title: next.displayName,
                                   subtitle: "\(Int(progress.target)) weeks in a row") {
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
        .pageTitleFade("Streak")
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
            .foregroundStyle(DS.ink(.dsScoreLow))
            .symbolEffect(.bounce, value: reduceMotion ? false : appeared)
            .frame(width: 84, height: 84)
            .background(Color.dsScoreLow.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }

    private func subtitle(_ stats: StreakStats) -> String {
        if stats.fishedThisWeek { return "You fished this week. Keep it going next week." }
        let day = LogbookFormat.longDay(Self.weekEnd)
        return stats.current > 0
            ? "Log a catch by \(day) to make it \(stats.current + 1)."
            : "Log a catch by \(day) to start a streak."
    }

    /// The start of this week, Monday, in the streak calendar.
    private static var thisWeek: Date {
        BadgeDefinition.weekStart(of: .now, calendar: BadgeDefinition.weekCalendar)
    }

    /// The last moment of this week, Sunday night.
    private static var weekEnd: Date {
        BadgeDefinition.weekCalendar.dateInterval(of: .weekOfYear, for: .now)
            .map { $0.end.addingTimeInterval(-1) } ?? .now
    }

    /// The starts of the weeks the strip shows, oldest first, ending with this week.
    private static var recentWeeks: [Date] {
        let cal = BadgeDefinition.weekCalendar
        let start = Self.thisWeek
        return (0..<shown).reversed().compactMap {
            cal.date(byAdding: .day, value: -7 * $0, to: start)
        }
    }

    private func weekStrip(_ stats: StreakStats) -> some View {
        let thisWeek = Self.thisWeek
        let cells = Self.recentWeeks
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

    /// Current streak, longest streak (or weeks fished when the current run
    /// is the longest) and this week, as three equal tiles. Every tile has a
    /// footnote, so the row keeps one height; each fits one line at a third
    /// of a phone's width.
    private func statTiles(_ stats: StreakStats) -> some View {
        let dates = catches.map(\.catchRecord.caughtAt)
        let cal = BadgeDefinition.weekCalendar
        let currentNote: String
        if stats.current > 0 && stats.current == stats.best {
            currentNote = "Longest yet"
        } else if stats.current > 0, let start = stats.currentStart {
            currentNote = "Since \(LogbookFormat.shortDay(start))"
        } else if let lastWeek = stats.weeks.max(),
                  let sunday = BadgeDefinition.adjacentWeek(1, to: lastWeek, calendar: cal)?.addingTimeInterval(-1) {
            // The last week of the run ended that Sunday.
            currentNote = "Ended \(LogbookFormat.shortDay(sunday))"
        } else {
            currentNote = "None yet"
        }
        let thisWeekCount = dates.filter { $0 >= Self.thisWeek }.count
        // Stacked at accessibility sizes, where three across would squash.
        let row = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return row {
            StatTile("Current", systemImage: "flame.fill", tint: DS.ink(.dsScoreLow),
                     value: "\(stats.current)", unit: stats.current == 1 ? "week" : "weeks",
                     footnote: currentNote, width: nil)
            if stats.current == stats.best {
                // Longest would only repeat Current, so show the strip's tally.
                let recent = Self.recentWeeks
                let fished = recent.filter { stats.weeks.contains($0) }.count
                let caught = recent.first.map { start in dates.filter { $0 >= start }.count } ?? 0
                // The strip above is titled "Last 16 weeks", so "Weeks 3 of 16" reads on.
                StatTile("Weeks", systemImage: "calendar", tint: .teal,
                         value: "\(fished)", unit: "of \(Self.shown)",
                         footnote: caught > 0 ? Self.catchCount(caught) : "No catches",
                         width: nil)
            } else {
                StatTile("Longest", systemImage: "trophy.fill", tint: DS.ink(.dsScoreFair),
                         value: "\(stats.best)", unit: stats.best == 1 ? "week" : "weeks",
                         footnote: stats.bestStart.map { "From \(LogbookFormat.shortDay($0))" } ?? "Your best run",
                         width: nil)
            }
            StatTile("This week", systemImage: stats.fishedThisWeek ? "checkmark.circle.fill" : "circle.dashed",
                     tint: stats.fishedThisWeek ? .dsScoreGood : DS.accent,
                     value: stats.fishedThisWeek ? "Fished" : "Not yet",
                     footnote: stats.fishedThisWeek
                        ? Self.catchCount(thisWeekCount)
                        : "Ends \(LogbookFormat.shortDay(Self.weekEnd))",
                     width: nil)
        }
    }

    private static func catchCount(_ n: Int) -> String {
        n == 1 ? "1 catch" : "\(n) catches"
    }
}
