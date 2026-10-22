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
            if let p = previous, cal.dateComponents([.day], from: p, to: w).day == 7 {
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
            currentStart = cal.date(byAdding: .day, value: -7 * (current - 1), to: latest)
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
        let streakTitles = ["Hot Streak", "On Fire", "Relentless", "Unstoppable", "Eternal Flame"]
        let next = badges.first { streakTitles.contains($0.title) && !$0.earned }

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

                LogbookKeyValueList(rows: rows(stats))
                    .padding(.top, DS.Space.s6)

                if let next, let progress = metrics.progress(for: next.title) {
                    SectionTitle("Next badge")
                        .padding(.top, DS.Space.s8)
                    Button {
                        selected = next
                    } label: {
                        ArtRow(title: next.title,
                               subtitle: "\(Int(progress.target)) weeks in a row, \(next.rarity.label.lowercased())") {
                            BadgeMedal(badge: next, size: 48)
                        } trailing: {
                            Text("\(stats.current)/\(Int(progress.target))")
                                .foregroundStyle(.dsText2)
                        }
                    }
                    .buttonStyle(.dsRow)
                }

                Text("A week counts when you log at least one catch between Monday and Sunday. Sessions with no catches do not count yet.")
                    .font(.callout)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(.dsScoreLow)
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
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
        if stats.fishedThisWeek { return "You have fished this week. See you next week." }
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
            .foregroundStyle(.dsText3)
        }
    }

    private func rows(_ stats: StreakStats) -> [(String, String)] {
        var rows: [(String, String)] = []
        let unit: (Int) -> String = { $0 == 1 ? "1 week" : "\($0) weeks" }
        if let start = stats.currentStart, stats.current > 0 {
            rows.append(("Current streak", "\(unit(stats.current)), since \(LogbookFormat.shortDay(start))"))
        } else {
            rows.append(("Current streak", "None yet"))
        }
        rows.append(("Longest streak", unit(stats.best)))
        if let s = stats.bestStart, let e = stats.bestEnd, stats.best > 0 {
            let end = Calendar.current.date(byAdding: .day, value: 6, to: e) ?? e
            rows.append(("Longest run", "\(LogbookFormat.shortDay(s)) to \(LogbookFormat.shortDay(end))"))
        }
        rows.append(("This week", stats.fishedThisWeek ? "Fished" : "Not yet"))
        return rows
    }
}
