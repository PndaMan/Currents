import SwiftUI
import Charts

/// The Logbook's Stats page: totals, your patterns, catches by month, by
/// species, gear and technique, best hours and days, bite score at catch
/// time, top spots, size trend and personal bests. All worked out on the
/// phone from the local log.
struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("use24HourTime") private var use24HourTime = true
    @AppStorage("units") private var units = "metric"
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var personalBests: [PersonalBest] = []
    @State private var monthlyCounts: [(month: String, count: Int)] = []
    @State private var hourCounts: [(hour: Int, count: Int)] = []
    @State private var avgForecast: Double?
    @State private var totalCatches = 0
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var allCatches: [CatchDetail] = []
    @State private var loaded = false
    /// The log could not be read; the page offers a retry rather than "no stats".
    @State private var loadFailed = false
    @State private var selectedMonth: String?
    @State private var showingAllSpecies = false

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: "Stats", subtitle: headerSubtitle)
                if !loaded {
                    FishLoader(message: "Counting your catches")
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                } else if loadFailed {
                    InlineEmpty(systemImage: "exclamationmark.triangle",
                                text: "Your stats could not be worked out. Nothing is lost.",
                                actionTitle: "Try again") {
                        Task { await loadData() }
                    }
                    .padding(.top, DS.Space.s5)
                } else if totalCatches == 0 {
                    InlineEmpty(systemImage: "chart.bar",
                                text: "No stats yet. Log a few catches to see your patterns and personal bests.")
                        .padding(.top, DS.Space.s5)
                } else {
                    totalsTiles
                    patternsSection
                    monthSection
                    speciesSection
                    gearSection
                    hoursSection
                    weekdaySection
                    biteScoreSection
                    spotsSection
                    weightTrendSection
                    personalBestsSection
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailScrollEdge()
        .dsScreenBackground()
        .pageTitleFade("Stats")
        // Ticks while scrubbing the month chart, not when the finger lifts.
        .haptic(.selection, trigger: selectedMonth) { _, new in new != nil }
        .task { await loadData() }
    }

    // MARK: - Header and totals

    private var dateRange: String? {
        guard let first = allCatches.map(\.catchRecord.caughtAt).min() else { return nil }
        let f = Date.FormatStyle.dateTime.month(.abbreviated).year()
        return "\(first.formatted(f)) to \(Date.now.formatted(f))"
    }

    /// "Oct 2025 to Oct 2026, 41 catches", once there is something to count.
    private var headerSubtitle: String? {
        guard loaded, !loadFailed, totalCatches > 0 else { return nil }
        let count = "\(totalCatches) \(totalCatches == 1 ? "catch" : "catches")"
        return dateRange.map { "\($0), \(count)" } ?? count
    }

    /// Three tiles across, stacked at accessibility sizes where three
    /// across would squash.
    private var tileRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    /// Every tile carries a short footnote that adds a fact, so each row
    /// keeps one height and the footnote fits one line at a third width.
    private var totalsTiles: some View {
        let released = allCatches.filter { $0.catchRecord.released }.count
        let rate = allCatches.isEmpty ? 0 : Int((Double(released) / Double(allCatches.count) * 100).rounded())
        let weights = allCatches.compactMap(\.catchRecord.weightKg)
        let avgWeight = weights.isEmpty ? nil : weights.reduce(0, +) / Double(weights.count)
        let heaviest = personalBests.filter { $0.heaviestKg != nil }
            .max { ($0.heaviestKg ?? 0) < ($1.heaviestKg ?? 0) }
        let longest = personalBests.filter { $0.longestCm != nil }
            .max { ($0.longestCm ?? 0) < ($1.longestCm ?? 0) }
        let cal = Calendar.current
        let year = cal.component(.year, from: .now)
        let thisYear = allCatches.filter { cal.component(.year, from: $0.catchRecord.caughtAt) == year }
        let speciesThisYear = Set(thisYear.compactMap(\.catchRecord.speciesId)).count
        return VStack(spacing: 10) {
            tileRow {
                StatTile("Catches", systemImage: "fish.fill", tint: DS.accent,
                         value: "\(totalCatches)", footnote: "\(thisYear.count) this year", width: nil)
                StatTile("Species", systemImage: "leaf.fill", tint: .dsScoreGood,
                         value: "\(personalBests.count)", footnote: "\(speciesThisYear) this year", width: nil)
                StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreLow,
                         value: "\(rate)%", footnote: "\(released) of \(allCatches.count)", width: nil)
            }
            if heaviest != nil || avgWeight != nil || longest != nil {
                tileRow {
                    if let heaviest, let kg = heaviest.heaviestKg {
                        let p = Units.weightParts(kg: kg, imperial: imperial)
                        StatTile("Heaviest", systemImage: "trophy.fill", tint: .dsScoreFair,
                                 value: p.0, unit: p.1, footnote: tileName(heaviest.commonName), width: nil)
                    }
                    if let avgWeight {
                        let p = Units.weightParts(kg: oneDecimal(avgWeight), imperial: imperial)
                        StatTile("Average", systemImage: "scalemass", tint: .teal,
                                 value: p.0, unit: p.1, footnote: "\(weights.count) weighed", width: nil)
                    }
                    if let longest, let cm = longest.longestCm {
                        let p = Units.lengthParts(cm: cm, imperial: imperial)
                        StatTile("Longest", systemImage: "ruler", tint: .indigo,
                                 value: p.0, unit: p.1, footnote: tileName(longest.commonName), width: nil)
                    }
                }
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)
    }

    /// A species name short enough for a third-width footnote: "Leervis"
    /// for "Leervis (Garrick)", and "Bass" for "Largemouth Bass", rather
    /// than a name cut off mid-word. Whole at accessibility sizes, where the
    /// footnote wraps.
    private func tileName(_ name: String) -> String {
        let plain = name.range(of: " (").map { String(name[..<$0.lowerBound]) } ?? name
        guard !typeSize.isAccessibilitySize, plain.count > 12,
              let last = plain.split(separator: " ").last else { return plain }
        return String(last)
    }

    /// An average weight rounded to one decimal in the shown unit: two
    /// decimals beside the heaviest fish claimed a precision it lacks.
    private func oneDecimal(_ kg: Double) -> Double {
        let perKg = imperial ? 2.2046226 : 1
        return (kg * perKg * 10).rounded() / 10 / perKg
    }

    // MARK: - Patterns

    /// Headline patterns the charts below do not already show.
    @ViewBuilder
    private var patternsSection: some View {
        let insights = InsightsEngine.compute(from: allCatches, use24: use24HourTime)
        if !insights.isEmpty {
            CardSection("Your patterns") {
                ForEach(insights) { insight in
                    if let lure = insight.lure {
                        // The lure's own art, as the gear card draws it.
                        GearItemRow(title: insight.title, subtitle: lure, value: insight.value) {
                            LureThumb(name: lure, size: 34)
                        }
                    } else {
                        CardRow(insight.title, subtitle: insight.detail, systemImage: insight.icon,
                                tint: patternTint(insight.kind), value: insight.value)
                    }
                }
            }
            .padding(.top, DS.Space.s8)
        }
    }

    /// Dawn and dusk are one colour wherever Stats shows them: the Best time
    /// row and the Best hours bars.
    private static let dawnDuskTint: Color = .dsScoreFair

    private func patternTint(_ kind: Insight.Kind) -> Color {
        switch kind {
        case .bestTime: return Self.dawnDuskTint
        case .bestLure: return OwnedGear.Category.lure.tint
        }
    }

    // MARK: - By month

    @ViewBuilder
    private var monthSection: some View {
        if monthlyCounts.contains(where: { $0.count > 0 }) {
            SectionTitle("Catches by month", detail: "Last 12 months")
                .padding(.top, DS.Space.s8)
            let picked = selectedMonth.flatMap { m in monthlyCounts.first { $0.month == m } }
            let readout = picked ?? monthlyCounts.max { $0.count < $1.count }
            if let readout {
                let name = monthName(readout.month, wide: true)
                let count = "\(readout.count) \(readout.count == 1 ? "catch" : "catches")"
                // Until a bar is picked the readout is the best month, so it says so.
                Text(picked == nil ? "Best month was \(name), with \(count)" : "\(name), \(count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .contentTransition(.numericText())
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s2)
            }
            Chart(monthlyCounts, id: \.month) { item in
                BarMark(x: .value("Month", item.month), y: .value("Catches", item.count), width: .ratio(0.7))
                    .foregroundStyle(selectedMonth == nil || selectedMonth == item.month ? DS.accent : DS.accent.opacity(0.35))
            }
            .chartXSelection(value: $selectedMonth)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(monthName(str, wide: false))
                        }
                    }
                }
            }
            .frame(height: 160)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Catches by month")
            .accessibilityValue(monthlyCounts.map { "\(monthName($0.month, wide: true)) \($0.count)" }.joined(separator: ", "))
        }
    }

    /// "2026-10" to "Oct" or "October 2026".
    private func monthName(_ key: String, wide: Bool) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1])) else { return key }
        return wide ? date.formatted(.dateTime.month(.wide).year()) : date.formatted(.dateTime.month(.narrow))
    }

    // MARK: - By species

    @ViewBuilder
    private var speciesSection: some View {
        if !speciesCounts.isEmpty {
            SectionTitle("By species", detail: "\(speciesCounts.count)")
                .padding(.top, DS.Space.s8)
            let shown = showingAllSpecies ? speciesCounts : Array(speciesCounts.prefix(8))
            let maxCount = speciesCounts.map(\.count).max() ?? 1
            let byId = speciesById
            VStack(spacing: DS.Space.s3) {
                ForEach(shown, id: \.speciesId) { item in
                    ThumbBarRow(name: item.commonName, count: item.count, maxCount: maxCount) {
                        if let species = byId[item.speciesId] {
                            ThumbView(species: species, size: 44)
                        } else {
                            ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            if speciesCounts.count > 8 {
                Button(showingAllSpecies ? "Show fewer" : "Show all \(speciesCounts.count) species") {
                    withAnimation(DS.Motion.softSpring) { showingAllSpecies.toggle() }
                }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s3)
            }

            let lures = bestLures
            if !lures.isEmpty {
                SectionTitle("Best lure by species")
                    .padding(.top, DS.Space.s8)
                ForEach(lures, id: \.species) { row in
                    ArtRow(over: row.species, title: row.lure, subtitle: row.detail) {
                        LureThumb(name: row.lure, size: 52)
                    }
                }
            }
        }
    }

    private var speciesById: [Int64: Species] {
        var map: [Int64: Species] = [:]
        for detail in allCatches {
            if let species = detail.species { map[species.id] = species }
        }
        return map
    }

    /// The most productive lure (or loadout) per species, top eight species,
    /// with the runner-up in the detail line.
    private var bestLures: [(species: String, lure: String, detail: String)] {
        let withGear = allCatches.filter { $0.gearLoadout != nil && $0.species != nil }
        let grouped = Dictionary(grouping: withGear, by: { $0.species?.commonName ?? "" })
        return grouped.sorted { $0.value.count > $1.value.count }.prefix(8).compactMap { species, catches in
            let lureGroups = Dictionary(grouping: catches, by: { lureName($0.gearLoadout) })
            let top = lureGroups.sorted { $0.value.count > $1.value.count }.prefix(2)
            guard let first = top.first else { return nil }
            var detail = "\(first.value.count) fish"
            if top.count > 1 {
                let second = top[top.index(after: top.startIndex)]
                detail += ", then \(second.key) with \(second.value.count)"
            }
            return (species, first.key, detail)
        }
    }

    /// The loadout's lure, or its name when no lure was set.
    private func lureName(_ loadout: GearLoadout?) -> String {
        let lure = loadout?.lure?.trimmingCharacters(in: .whitespaces) ?? ""
        return lure.isEmpty ? (loadout?.name ?? "") : lure
    }

    // MARK: - Gear

    @ViewBuilder
    private var gearSection: some View {
        let gearGroups = Dictionary(grouping: allCatches.filter { $0.gearLoadout != nil }, by: { $0.gearLoadout?.name ?? "" })
        let sorted = gearGroups.sorted { $0.value.count > $1.value.count }
        SectionTitle("Gear effectiveness")
            .padding(.top, DS.Space.s8)
        if sorted.isEmpty {
            InlineEmpty(systemImage: "backpack", text: "No gear logged yet. Add a loadout when you log a catch.")
        } else {
            let maxCount = sorted.first?.value.count ?? 1
            VStack(spacing: DS.Space.s3) {
                ForEach(sorted.prefix(8), id: \.key) { name, catches in
                    ThumbBarRow(name: name, count: catches.count, maxCount: maxCount) {
                        LureThumb(name: lureName(catches.first?.gearLoadout), size: 44)
                    }
                }
            }
            .padding(.horizontal, DS.gutter)

            let techniques = Dictionary(grouping: allCatches.compactMap { $0.gearLoadout?.technique }.filter { !$0.isEmpty }, by: { $0 })
                .sorted { $0.value.count > $1.value.count }
            if !techniques.isEmpty {
                SectionTitle("Techniques")
                    .padding(.top, DS.Space.s8)
                LabeledBarList(items: techniques.prefix(6).map { ($0.key, $0.value.count) })
                    .padding(.horizontal, DS.gutter)
            }
        }
    }

    // MARK: - Best hours and days

    @ViewBuilder
    private var hoursSection: some View {
        if !hourCounts.isEmpty {
            SectionTitle("Best hours")
                .padding(.top, DS.Space.s8)
            Chart(hourCounts, id: \.hour) { item in
                // The hour is a number, so there is no band for a width ratio
                // to take a share of: the bar is a rectangle from its own
                // start to its own end, centred on the hour, up from zero.
                RectangleMark(xStart: .value("From", Double(item.hour) - 0.38),
                              xEnd: .value("To", Double(item.hour) + 0.38),
                              yStart: .value("Base", 0),
                              yEnd: .value("Catches", item.count))
                    .foregroundStyle(hourColor(item.hour))
            }
            .chartXScale(domain: -0.5...23.5)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0.0, 6.0, 12.0, 18.0]) { value in
                    // The anchor puts the middle of each label under its bar; a
                    // numeric axis would start the label there instead.
                    AxisValueLabel(anchor: UnitPoint.top) {
                        if let h = value.as(Double.self) { Text(formatHour(Int(h))) }
                    }
                }
            }
            .frame(height: 140)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Catches by hour of day")
            .accessibilityValue(hourCounts.map { "\(formatHour($0.hour)) \($0.count)" }.joined(separator: ", "))
            HStack(spacing: 14) {
                legendItem(color: DS.ink(Self.dawnDuskTint), label: "Dawn and dusk")
                legendItem(color: DS.accent, label: "Day")
                legendItem(color: DS.accent.opacity(0.35), label: "Night")
            }
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var weekdaySection: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        let dayCounts = Dictionary(grouping: allCatches, by: {
            Calendar.current.component(.weekday, from: $0.catchRecord.caughtAt) - 1
        })
        .map { (index: $0.key, day: symbols[$0.key], count: $0.value.count) }
        .sorted { $0.index < $1.index }
        if !dayCounts.isEmpty {
            let best = dayCounts.max { $0.count < $1.count }
            SectionTitle("Days of the week")
                .padding(.top, DS.Space.s8)
            Chart(dayCounts, id: \.index) { item in
                BarMark(x: .value("Day", item.day), y: .value("Catches", item.count), width: .ratio(0.6))
                    .foregroundStyle(item.index == best?.index ? DS.accent : DS.accent.opacity(0.35))
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Catches by day of the week")
            .accessibilityValue(dayCounts.map { "\($0.day) \($0.count)" }.joined(separator: ", "))
        }
    }

    // MARK: - Bite score at catch time

    @ViewBuilder
    private var biteScoreSection: some View {
        if let avg = avgForecast {
            SectionTitle("Bite score at catch time")
                .padding(.top, DS.Space.s8)
            HStack(spacing: 16) {
                ScoreRing(score: Int(avg.rounded()), size: 80, caption: "average")
                Text(avg > 50
                     ? "You catch more when the bite score is high."
                     : "You catch fish whatever the score says.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.gutter)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Top spots

    @ViewBuilder
    private var spotsSection: some View {
        let groups = Dictionary(grouping: allCatches.filter { $0.spot != nil }, by: { $0.spot?.id ?? "" })
        let sorted = groups.sorted { $0.value.count > $1.value.count }
        SectionTitle("Top spots")
            .padding(.top, DS.Space.s8)
        if sorted.isEmpty {
            InlineEmpty(systemImage: "mappin.and.ellipse", text: "No spots yet. Log a catch at a saved spot.")
        } else {
            ForEach(sorted.prefix(10), id: \.key) { _, catches in
                if let spot = catches.first?.spot {
                    // The spot opens on the Explore map in its sheet.
                    Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                        ArtRow(title: spot.name, subtitle: speciesMix(catches), chevron: true) {
                            PlaceSnapshotThumb(spot: spot, size: 52)
                        } trailing: {
                            Text("\(catches.count)")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.dsText)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    /// "Bass 4, Carp 2" for a spot's catches, most caught first.
    private func speciesMix(_ catches: [CatchDetail]) -> String {
        Dictionary(grouping: catches.compactMap { $0.species?.commonName }, by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
            .map { "\($0.key) \($0.value.count)" }
            .joined(separator: ", ")
    }

    // MARK: - Weight trend

    @ViewBuilder
    private var weightTrendSection: some View {
        let weighed = allCatches
            .filter { $0.catchRecord.weightKg != nil }
            .sorted { $0.catchRecord.caughtAt < $1.catchRecord.caughtAt }
        if weighed.count > 1 {
            SectionTitle("Weight over time")
                .padding(.top, DS.Space.s8)
            Chart(weighed, id: \.catchRecord.id) { detail in
                PointMark(
                    x: .value("Date", detail.catchRecord.caughtAt),
                    y: .value("Weight", imperial ? (detail.catchRecord.weightKg ?? 0) * 2.20462 : (detail.catchRecord.weightKg ?? 0))
                )
                .foregroundStyle(by: .value("Species", detail.species?.commonName ?? "Unknown"))
            }
            .chartYAxisLabel(imperial ? "lb" : "kg")
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Weight of each catch over time")
        }
    }

    // MARK: - Personal bests

    @ViewBuilder
    private var personalBestsSection: some View {
        if !personalBests.isEmpty {
            SectionTitle("Personal bests")
                .padding(.top, DS.Space.s8)
            let byId = speciesById
            ForEach(personalBests, id: \.speciesId) { pb in
                let best = bestCatch(pb)
                let subtitle = bestSubtitle(pb)
                if let best {
                    NavigationLink {
                        CatchDetailView(detail: best)
                    } label: {
                        ArtRow(title: pb.commonName, subtitle: subtitle, chevron: true) {
                            CatchThumb(detail: best, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                } else {
                    ArtRow(title: pb.commonName, subtitle: subtitle) {
                        if let species = byId[pb.speciesId] {
                            ThumbView(species: species, size: 52)
                        } else {
                            ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 52)
                        }
                    }
                }
            }
        }
    }

    /// "Heaviest 9.8 kg, longest 99.5 cm, 1 caught", rounded as the Heaviest
    /// and Longest tiles round, so one fish reads the same in both places.
    /// The heaviest and the longest can be two fish, so each is named.
    private func bestSubtitle(_ pb: PersonalBest) -> String {
        var parts: [String] = []
        if let kg = pb.heaviestKg {
            let p = Units.weightParts(kg: kg, imperial: imperial)
            parts.append("heaviest \(p.0) \(p.1)")
        }
        if let cm = pb.longestCm {
            let p = Units.lengthParts(cm: cm, imperial: imperial)
            parts.append("longest \(p.0) \(p.1)")
        }
        parts.append("\(pb.totalCatches) caught")
        let line = parts.joined(separator: ", ")
        return line.prefix(1).uppercased() + String(line.dropFirst())
    }

    /// The catch a personal best row opens: the heaviest of the species,
    /// else the longest, else the latest. The query leaves the catch ids
    /// empty, so they are matched here from the log.
    private func bestCatch(_ pb: PersonalBest) -> CatchDetail? {
        let mine = allCatches.filter { $0.catchRecord.speciesId == pb.speciesId }
        let heaviest = mine.filter { $0.catchRecord.weightKg != nil }
            .max { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }
        let longest = mine.filter { $0.catchRecord.lengthCm != nil }
            .max { ($0.catchRecord.lengthCm ?? 0) < ($1.catchRecord.lengthCm ?? 0) }
        return heaviest ?? longest ?? mine.first
    }

    // MARK: - Helpers

    private func loadData() async {
        let repo = appState.catchRepository
        do {
            totalCatches = try repo.totalCount()
            personalBests = try repo.personalBests()
            avgForecast = try repo.averageForecastScore()
            speciesCounts = try repo.speciesCounts()
            allCatches = try repo.fetchAll(limit: 1000)
            // Counted on the phone's clock. SQLite's strftime reads the stored
            // UTC times, which put every hour bar two hours early in Cape Town
            // and could file a catch after midnight under the month before.
            monthlyCounts = Self.everyMonth(Self.countsByMonth(allCatches))
            hourCounts = Self.countsByHour(allCatches)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        loaded = true
    }

    /// Catches per month in local time, keyed "2026-10", months with none
    /// left out.
    private static func countsByMonth(_ catches: [CatchDetail]) -> [(month: String, count: Int)] {
        let cal = Calendar.current
        let byMonth = Dictionary(grouping: catches) { detail -> String in
            let parts = cal.dateComponents([.year, .month], from: detail.catchRecord.caughtAt)
            return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        }
        return byMonth.map { (month: $0.key, count: $0.value.count) }
    }

    /// Catches per hour of the day in local time, as "Your patterns" counts
    /// them, hours with none left out.
    private static func countsByHour(_ catches: [CatchDetail]) -> [(hour: Int, count: Int)] {
        let cal = Calendar.current
        let byHour = Dictionary(grouping: catches) { cal.component(.hour, from: $0.catchRecord.caughtAt) }
        return byHour.map { (hour: $0.key, count: $0.value.count) }.sorted { $0.hour < $1.hour }
    }

    /// The counts hold only months with catches, which drew four bars
    /// under "Last 12 months". Every month of the last 12, oldest first,
    /// with zero where nothing was caught.
    private static func everyMonth(_ counts: [(month: String, count: Int)],
                                   months: Int = 12) -> [(month: String, count: Int)] {
        let cal = Calendar.current
        let byMonth = Dictionary(counts.map { ($0.month, $0.count) }, uniquingKeysWith: +)
        guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: .now)) else { return counts }
        return (0..<months).reversed().compactMap { back -> (month: String, count: Int)? in
            guard let date = cal.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            let parts = cal.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            let key = String(format: "%04d-%02d", year, month)
            return (month: key, count: byMonth[key] ?? 0)
        }
    }

    /// "06:00", or "6 am" in 12-hour time, as on Today.
    private func formatHour(_ hour: Int) -> String {
        ForecastFormat.hour(hour, use24: use24HourTime)
    }

    /// Dawn and dusk are the hours the Best time row counts as dawn and
    /// evening; day runs between them.
    private func hourColor(_ hour: Int) -> Color {
        if InsightsEngine.isDawnOrDusk(hour) { return DS.ink(Self.dawnDuskTint) }
        if (InsightsEngine.dawnHours.upperBound..<InsightsEngine.duskHours.lowerBound).contains(hour) {
            return DS.accent
        }
        // Faint accent rather than a fill grey, so night bars show on white.
        return DS.accent.opacity(0.35)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

/// A bar row with a square thumbnail: the name above a proportional bar,
/// with the count trailing. Every count on the page uses the one accent.
private struct ThumbBarRow<Leading: View>: View {
    let name: String
    let count: Int
    let maxCount: Int
    var tint: Color = DS.accent
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 14) {
            leading()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.dsText)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.dsText)
                }
                Capsule()
                    .fill(Color.dsFill)
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(tint)
                                .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(max(maxCount, 1))))
                        }
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal bars that never clip their labels: the full name sits above a
/// proportional bar, with the count trailing.
private struct LabeledBarList: View {
    let items: [(name: String, count: Int)]
    var tint: Color = DS.accent

    var body: some View {
        let maxCount = max(items.map(\.count).max() ?? 1, 1)
        VStack(spacing: 12) {
            ForEach(items, id: \.name) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(.dsText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.dsFill)
                            Capsule().fill(tint)
                                .frame(width: max(6, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
