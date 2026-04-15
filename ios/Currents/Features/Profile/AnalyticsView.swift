import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("use24HourTime") private var use24HourTime = true
    @State private var personalBests: [PersonalBest] = []
    @State private var monthlyCounts: [(month: String, count: Int)] = []
    @State private var hourCounts: [(hour: Int, count: Int)] = []
    @State private var avgForecast: Double?
    @State private var totalCatches = 0
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []
    @State private var allCatches: [CatchDetail] = []
    @State private var selectedSection: AnalyticsSection = .overview

    enum AnalyticsSection: String, CaseIterable {
        case overview = "Overview"
        case species = "Species"
        case spots = "Spots"
        case gear = "Gear"
        case patterns = "Patterns"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                // Section picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AnalyticsSection.allCases, id: \.self) { section in
                            FilterChip(
                                title: section.rawValue,
                                isSelected: selectedSection == section
                            ) {
                                selectedSection = section
                            }
                        }
                    }
                }

                switch selectedSection {
                case .overview:
                    overviewSection
                case .species:
                    speciesSection
                case .spots:
                    spotsSection
                case .gear:
                    gearSection
                case .patterns:
                    patternsSection
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .task { await loadData() }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        summaryCard

        // At a Glance
        if totalCatches > 0 {
            atAGlanceCard
        }

        if !monthlyCounts.isEmpty {
            monthlyTrendChart
        }

        if !hourCounts.isEmpty {
            overviewBestTimeChart
        }

        if let avg = avgForecast {
            forecastAccuracyCard(avg)
        }

        // Species breakdown
        if !speciesCounts.isEmpty {
            overviewSpeciesBreakdown
        }

        // Top spots
        overviewTopSpots

        if !personalBests.isEmpty {
            personalBestsSection
        }
    }

    private var atAGlanceCard: some View {
        HStack(spacing: 12) {
            let released = allCatches.filter { $0.catchRecord.released }.count
            let releaseRate = totalCatches > 0 ? Int(Double(released) / Double(totalCatches) * 100) : 0
            let weights = allCatches.compactMap(\.catchRecord.weightKg)
            let avgWeight = weights.isEmpty ? 0.0 : weights.reduce(0, +) / Double(weights.count)

            StatCard(value: "\(releaseRate)%", label: "Released", icon: "arrow.uturn.backward")
            if avgWeight > 0 {
                StatCard(value: String(format: "%.1fkg", avgWeight), label: "Avg Weight", icon: "scalemass")
            }
            if let biggest = weights.max() {
                StatCard(value: String(format: "%.1fkg", biggest), label: "Biggest", icon: "trophy.fill")
            }
        }
    }

    private var overviewBestTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Time to Fish")
                .font(.headline)

            Chart(hourCounts, id: \.hour) { item in
                BarMark(
                    x: .value("Hour", item.hour),
                    y: .value("Catches", item.count)
                )
                .foregroundStyle(hourColor(item.hour))
            }
            .chartXAxis {
                AxisMarks(values: [0, 4, 8, 12, 16, 20]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text(formatHour(h)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 120)

            if let peak = hourCounts.max(by: { $0.count < $1.count }) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                    Text("Peak: \(formatHour(peak.hour))")
                        .font(.subheadline.bold())
                    Text("(\(peak.count) catches)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private var overviewSpeciesBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Species Breakdown")
                .font(.headline)

            Chart(speciesCounts.prefix(8), id: \.speciesId) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Species", item.commonName)
                )
                .foregroundStyle(.blue.gradient)
            }
            .frame(height: CGFloat(min(speciesCounts.count, 8)) * 36)
        }
        .glassCard()
    }

    @ViewBuilder
    private var overviewTopSpots: some View {
        let spotGroups = Dictionary(grouping: allCatches.filter { $0.spot != nil }, by: { $0.spot!.name })
        let sortedSpots = spotGroups.sorted { $0.value.count > $1.value.count }

        if !sortedSpots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top Spots")
                    .font(.headline)

                ForEach(sortedSpots.prefix(5), id: \.key) { spotName, spotCatches in
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        Text(spotName)
                        Spacer()
                        Text("\(spotCatches.count)")
                            .font(.headline.bold())
                            .monospacedDigit()
                        Text("catches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .glassCard()
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(totalCatches)", label: "Total", icon: "fish.fill")
            StatCard(value: "\(personalBests.count)", label: "Species", icon: "leaf.fill")
            if let biggest = personalBests.compactMap(\.heaviestKg).max() {
                StatCard(value: String(format: "%.1fkg", biggest), label: "Biggest", icon: "trophy.fill")
            }
            if let longest = personalBests.compactMap(\.longestCm).max() {
                StatCard(value: String(format: "%.0fcm", longest), label: "Longest", icon: "ruler")
            }
        }
    }

    private var monthlyTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catch Trend")
                .font(.headline)
            Text("Last 12 months")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(monthlyCounts, id: \.month) { item in
                BarMark(
                    x: .value("Month", item.month),
                    y: .value("Catches", item.count)
                )
                .foregroundStyle(.blue.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(String(str.suffix(2)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .glassCard()
    }

    private func forecastAccuracyCard(_ avg: Double) -> some View {
        HStack {
            ScoreGauge(score: Int(avg), label: "Avg Forecast\nat Catch Time")
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("Forecast Validation")
                    .font(.headline)
                if avg > 50 {
                    Text("You tend to catch more when the forecast is high — the model is working!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You're catching fish in all conditions — nice!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    private var personalBestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal Bests")
                .font(.headline)

            ForEach(personalBests, id: \.speciesId) { pb in
                HStack {
                    Image(systemName: "fish.fill")
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pb.commonName)
                            .font(.subheadline.bold())
                        Text("\(pb.totalCatches) caught")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let kg = pb.heaviestKg {
                            Text(String(format: "%.2f kg", kg))
                                .font(.subheadline.bold())
                                .monospacedDigit()
                        }
                        if let cm = pb.longestCm {
                            Text(String(format: "%.0f cm", cm))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .glassCard()
    }

    // MARK: - Species Section

    @ViewBuilder
    private var speciesSection: some View {
        // Species diversity donut
        if !speciesCounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Species Breakdown")
                    .font(.headline)

                Chart(speciesCounts.prefix(10), id: \.speciesId) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.0
                    )
                    .foregroundStyle(by: .value("Species", item.commonName))
                }
                .frame(height: 200)
            }
            .glassCard()

            // Species ranking
            VStack(alignment: .leading, spacing: 8) {
                Text("Species Ranking")
                    .font(.headline)

                ForEach(Array(speciesCounts.enumerated()), id: \.element.speciesId) { index, item in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 30)
                            .foregroundStyle(index < 3 ? .yellow : .secondary)
                        Image(systemName: "fish.fill")
                            .foregroundStyle(.blue)
                        Text(item.commonName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    if index < speciesCounts.count - 1 { Divider() }
                }
            }
            .glassCard()
        }

        // Best baits per species
        if !allCatches.isEmpty {
            bestBaitsSection
        }
    }

    private var bestBaitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Baits by Species")
                .font(.headline)
            Text("Based on your catch history with gear")
                .font(.caption)
                .foregroundStyle(.secondary)

            let catchesWithGear = allCatches.filter { $0.gearLoadout != nil && $0.species != nil }
            let grouped = Dictionary(grouping: catchesWithGear, by: { $0.species!.commonName })

            ForEach(grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(8), id: \.key) { species, catches in
                VStack(alignment: .leading, spacing: 4) {
                    Text(species)
                        .font(.subheadline.bold())

                    let lureGroups = Dictionary(grouping: catches, by: { $0.gearLoadout?.lure ?? $0.gearLoadout?.name ?? "Unknown" })
                    let sorted = lureGroups.sorted { $0.value.count > $1.value.count }

                    ForEach(sorted.prefix(3), id: \.key) { lure, lureCatches in
                        HStack {
                            Image(systemName: "fish.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(lure)
                                .font(.caption)
                            Spacer()
                            Text("\(lureCatches.count) catches")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }

            if catchesWithGear.isEmpty {
                Text("Log catches with gear loadouts to see bait effectiveness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    // MARK: - Spots Section

    @ViewBuilder
    private var spotsSection: some View {
        // Top spots
        let spotGroups = Dictionary(grouping: allCatches.filter { $0.spot != nil }, by: { $0.spot!.name })
        let sortedSpots = spotGroups.sorted { $0.value.count > $1.value.count }

        if !sortedSpots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top Spots")
                    .font(.headline)

                ForEach(Array(sortedSpots.prefix(10).enumerated()), id: \.element.key) { index, item in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 30)
                            .foregroundStyle(index < 3 ? .yellow : .secondary)
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(item.key)
                                .font(.subheadline)
                            let species = Set(item.value.compactMap { $0.species?.commonName })
                            Text(species.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(item.value.count)")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    if index < min(sortedSpots.count, 10) - 1 { Divider() }
                }
            }
            .glassCard()

            // Spot species diversity
            VStack(alignment: .leading, spacing: 8) {
                Text("Spot Species Diversity")
                    .font(.headline)

                ForEach(sortedSpots.prefix(5), id: \.key) { spotName, catches in
                    let speciesMap = Dictionary(grouping: catches.filter { $0.species != nil }, by: { $0.species!.commonName })
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spotName)
                            .font(.subheadline.bold())
                        Chart(speciesMap.sorted(by: { $0.value.count > $1.value.count }).prefix(5), id: \.key) { item in
                            BarMark(
                                x: .value("Count", item.value.count),
                                y: .value("Species", item.key)
                            )
                            .foregroundStyle(.blue.gradient)
                            .annotation(position: .trailing, spacing: 4) {
                                Text("\(item.value.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let name = value.as(String.self) {
                                        Text(name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: 100, alignment: .trailing)
                                    }
                                }
                            }
                        }
                        .frame(height: CGFloat(min(speciesMap.count, 5)) * 36)
                    }
                    .padding(.vertical, 4)
                }
            }
            .glassCard()
        } else {
            ContentUnavailableView(
                "No spot data",
                systemImage: "mappin",
                description: Text("Log catches at saved spots to see spot analytics")
            )
        }
    }

    // MARK: - Gear Section

    @ViewBuilder
    private var gearSection: some View {
        let gearCatches = allCatches.filter { $0.gearLoadout != nil }
        let gearGroups = Dictionary(grouping: gearCatches, by: { $0.gearLoadout!.name })
        let sorted = gearGroups.sorted { $0.value.count > $1.value.count }

        if !sorted.isEmpty {
            // Gear effectiveness chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Gear Effectiveness")
                    .font(.headline)

                Chart(sorted.prefix(8), id: \.key) { item in
                    BarMark(
                        x: .value("Catches", item.value.count),
                        y: .value("Gear", item.key)
                    )
                    .foregroundStyle(.green.gradient)
                }
                .frame(height: CGFloat(min(sorted.count, 8)) * 36)
            }
            .glassCard()

            // Technique breakdown
            let techniques = allCatches.compactMap { $0.gearLoadout?.technique }
            let techGroups = Dictionary(grouping: techniques, by: { $0 })
            let sortedTech = techGroups.sorted { $0.value.count > $1.value.count }

            if !sortedTech.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Technique Breakdown")
                        .font(.headline)

                    ForEach(sortedTech.prefix(6), id: \.key) { technique, uses in
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            Text(technique)
                                .font(.subheadline)
                            Spacer()
                            Text("\(uses.count) catches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .glassCard()
            }
        } else {
            ContentUnavailableView(
                "No gear data",
                systemImage: "wrench.and.screwdriver",
                description: Text("Log catches with gear loadouts to see gear analytics")
            )
        }
    }

    // MARK: - Patterns Section

    @ViewBuilder
    private var patternsSection: some View {
        // Best time to fish
        if !hourCounts.isEmpty {
            bestTimeChart
        }

        // Day of week
        dayOfWeekChart

        // Release rate over time
        releaseRateCard

        // Catch size trends
        if allCatches.contains(where: { $0.catchRecord.weightKg != nil }) {
            catchSizeTrends
        }
    }

    private var bestTimeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Time to Fish")
                .font(.headline)
            Text("Based on your catch history")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(hourCounts, id: \.hour) { item in
                BarMark(
                    x: .value("Hour", item.hour),
                    y: .value("Catches", item.count)
                )
                .foregroundStyle(hourColor(item.hour))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text(formatHour(h))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 140)

            if let bestHour = hourCounts.max(by: { $0.count < $1.count }) {
                Label("Peak: \(formatHour(bestHour.hour))", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .orange, label: "Dawn/Dusk")
                legendItem(color: .blue, label: "Day")
                legendItem(color: .indigo, label: "Night")
            }
            .font(.caption2)
        }
        .glassCard()
    }

    private var dayOfWeekChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Day of Week")
                .font(.headline)

            let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayCounts = Dictionary(grouping: allCatches, by: {
                Calendar.current.component(.weekday, from: $0.catchRecord.caughtAt) - 1
            }).map { (day: days[$0.key], count: $0.value.count) }
            .sorted { days.firstIndex(of: $0.day)! < days.firstIndex(of: $1.day)! }

            if !dayCounts.isEmpty {
                Chart(dayCounts, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Catches", item.count)
                    )
                    .foregroundStyle(.purple.gradient)
                }
                .frame(height: 120)
            }
        }
        .glassCard()
    }

    private var releaseRateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Rate")
                .font(.headline)

            let total = allCatches.count
            let released = allCatches.filter { $0.catchRecord.released }.count
            let rate = total > 0 ? Double(released) / Double(total) * 100 : 0

            HStack {
                ScoreGauge(score: Int(rate), label: "Released")
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(released) of \(total) fish released")
                        .font(.subheadline)
                    if rate > 80 {
                        Text("Great conservation practice!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .glassCard()
    }

    private var catchSizeTrends: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Trends")
                .font(.headline)

            let weightCatches = allCatches
                .filter { $0.catchRecord.weightKg != nil }
                .sorted { $0.catchRecord.caughtAt < $1.catchRecord.caughtAt }

            Chart(weightCatches, id: \.catchRecord.id) { detail in
                PointMark(
                    x: .value("Date", detail.catchRecord.caughtAt),
                    y: .value("Weight", detail.catchRecord.weightKg ?? 0)
                )
                .foregroundStyle(by: .value("Species", detail.species?.commonName ?? "Unknown"))
            }
            .frame(height: 160)
        }
        .glassCard()
    }

    // MARK: - Helpers

    private func loadData() async {
        totalCatches = (try? appState.catchRepository.totalCount()) ?? 0
        personalBests = (try? appState.catchRepository.personalBests()) ?? []
        monthlyCounts = (try? appState.catchRepository.monthlyCounts()) ?? []
        hourCounts = (try? appState.catchRepository.catchesByHour()) ?? []
        avgForecast = try? appState.catchRepository.averageForecastScore()
        speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
        allCatches = (try? appState.catchRepository.fetchAll(limit: 1000)) ?? []
    }

    private func formatHour(_ hour: Int) -> String {
        if use24HourTime {
            return String(format: "%02d:00", hour)
        }
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }

    private func hourColor(_ hour: Int) -> Color {
        switch hour {
        case 5...8: return .orange
        case 16...19: return .orange
        case 9...15: return .blue
        default: return .indigo
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
