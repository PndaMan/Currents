import SwiftUI
import Charts

struct ForecastTab: View {
    @Environment(AppState.self) private var appState
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var moonPhase: MoonPhase = .current()
    @State private var selectedSpecies: Species?
    @State private var allSpecies: [Species] = []

    // Simulated hourly pressure data for the chart
    @State private var pressureHistory: [(hour: Int, hPa: Double)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    // Main score
                    if let forecast {
                        scoreCard(forecast)
                    } else {
                        ProgressView()
                            .frame(height: 120)
                    }

                    // Pressure trend chart
                    pressureChart

                    // Moon phase
                    moonCard

                    // Conditions breakdown
                    if let forecast {
                        breakdownCard(forecast)
                    }

                    // Species picker for species-specific forecast
                    speciesPicker
                }
                .padding()
            }
            .navigationTitle("Forecast")
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                computeForecast()
                generateMockPressure()
            }
        }
    }

    private func scoreCard(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(spacing: 12) {
            ScoreGauge(score: forecast.score, label: "Bite Score")
                .scaleEffect(1.5)
                .padding()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(forecast.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }

    private var pressureChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Barometric Pressure (24h)")
                .font(.headline)

            Chart(pressureHistory, id: \.hour) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("hPa", point.hPa)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue.gradient)

                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value("hPa", point.hPa)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.blue.opacity(0.1).gradient)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .stride(by: 6)) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)h")
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .glassCard()
    }

    private var moonCard: some View {
        HStack {
            Image(systemName: moonPhase.symbolName)
                .font(.largeTitle)
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading) {
                Text(moonPhase.displayName)
                    .font(.headline)
                Text("Solunar influence: \(moonPhase == .full || moonPhase == .new ? "Strong" : "Moderate")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private func breakdownCard(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score Breakdown")
                .font(.headline)

            BreakdownRow(label: "Pressure", value: forecast.breakdown.pressure)
            BreakdownRow(label: "Pressure Trend", value: forecast.breakdown.pressureTrend)
            BreakdownRow(label: "Tide", value: forecast.breakdown.tide)
            BreakdownRow(label: "Moon", value: forecast.breakdown.moon)
            BreakdownRow(label: "Temperature", value: forecast.breakdown.temperature)
            BreakdownRow(label: "Season/Spawn", value: forecast.breakdown.season)
        }
        .glassCard()
    }

    private var speciesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Species")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button {
                        selectedSpecies = nil
                        computeForecast()
                    } label: {
                        Text("General")
                            .glassPill()
                    }
                    .tint(selectedSpecies == nil ? .blue : .secondary)

                    ForEach(allSpecies.prefix(20)) { species in
                        Button {
                            selectedSpecies = species
                            computeForecast()
                        } label: {
                            Text(species.commonName)
                                .glassPill()
                        }
                        .tint(selectedSpecies?.id == species.id ? .blue : .secondary)
                    }
                }
            }
        }
        .glassCard()
    }

    private func computeForecast() {
        // Use whatever pressure data we have cached
        let latestPressure = pressureHistory.last?.hPa
        let pressureDelta: Double? = if pressureHistory.count > 6 {
            (pressureHistory.last?.hPa ?? 0) - (pressureHistory[pressureHistory.count - 7].hPa)
        } else {
            nil
        }

        forecast = ForecastEngine.compute(
            currentPressureHpa: latestPressure,
            pressureChange6h: pressureDelta,
            tidePhase: nil,
            moonPhase: moonPhase,
            waterTempC: nil,
            species: selectedSpecies,
            isInSpawningZone: false
        )
    }

    private func generateMockPressure() {
        // Generate realistic pressure data seeded by today's date for consistency
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: .now) ?? 1
        var rng = SeededRNG(seed: UInt64(dayOfYear))

        // Base pressure varies by "season" — lower in winter, higher in summer
        let seasonalOffset = sin(Double(dayOfYear) / 365.0 * .pi * 2) * 4
        var pressure = 1016.0 + seasonalOffset

        let currentHour = calendar.component(.hour, from: .now)
        pressureHistory = (0...24).map { hour in
            // Slight diurnal variation + random walk
            let diurnal = sin(Double(hour) / 24.0 * .pi * 2) * 0.5
            pressure += diurnal + rng.nextDouble(in: -1.2...0.8)
            pressure = max(995, min(1040, pressure))
            return (hour: hour, hPa: pressure)
        }

        // Re-compute forecast now that we have pressure data
        computeForecast()

        // Mark current hour
        _ = currentHour // available for future use (current hour indicator on chart)
    }
}

/// Simple seeded RNG for deterministic mock data (same pressure curve each day).
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let raw = Double(next() & 0x1FFFFFFFFFFFFF) / Double(0x1FFFFFFFFFFFFF)
        return range.lowerBound + raw * (range.upperBound - range.lowerBound)
    }
}

struct BreakdownRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(String(format: "%.2fx", value))
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(value > 1.1 ? .green : value < 0.9 ? .red : .secondary)
        }
    }
}
