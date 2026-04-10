import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @State private var personalBests: [PersonalBest] = []
    @State private var monthlyCounts: [(month: String, count: Int)] = []
    @State private var hourCounts: [(hour: Int, count: Int)] = []
    @State private var avgForecast: Double?
    @State private var totalCatches = 0
    @State private var speciesCounts: [(speciesId: Int64, commonName: String, count: Int)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                // Summary stats
                summaryCard

                // Monthly trend
                if !monthlyCounts.isEmpty {
                    monthlyTrendChart
                }

                // Best time to fish
                if !hourCounts.isEmpty {
                    bestTimeChart
                }

                // Forecast accuracy
                if let avg = avgForecast {
                    forecastAccuracyCard(avg)
                }

                // Species diversity
                if !speciesCounts.isEmpty {
                    speciesDiversityChart
                }

                // Personal bests
                if !personalBests.isEmpty {
                    personalBestsSection
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .task { await loadData() }
    }

    // MARK: - Summary

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

    // MARK: - Monthly Trend

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

    // MARK: - Best Time

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
        }
        .glassCard()
    }

    // MARK: - Forecast Accuracy

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

    // MARK: - Species Diversity

    private var speciesDiversityChart: some View {
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
    }

    // MARK: - Personal Bests

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

    // MARK: - Helpers

    private func loadData() async {
        totalCatches = (try? appState.catchRepository.totalCount()) ?? 0
        personalBests = (try? appState.catchRepository.personalBests()) ?? []
        monthlyCounts = (try? appState.catchRepository.monthlyCounts()) ?? []
        hourCounts = (try? appState.catchRepository.catchesByHour()) ?? []
        avgForecast = try? appState.catchRepository.averageForecastScore()
        speciesCounts = (try? appState.catchRepository.speciesCounts()) ?? []
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "a" : "p")"
    }

    private func hourColor(_ hour: Int) -> Color {
        switch hour {
        case 5...8: return .orange // dawn
        case 16...19: return .orange // dusk
        case 9...15: return .blue // day
        default: return .indigo // night
        }
    }
}
