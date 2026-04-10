import SwiftUI
import Charts
import CoreLocation

struct ForecastTab: View {
    @Environment(AppState.self) private var appState
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var tideDay: TideEngine.TideDay?
    @State private var selectedSpecies: Species?
    @State private var allSpecies: [Species] = []
    @State private var selectedDay: Int = 0 // 0 = today, 1 = tomorrow, etc.

    private var forecastDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDay, to: .now) ?? .now
    }

    private var coordinate: CLLocationCoordinate2D {
        appState.locationManager.currentLocation?.coordinate ??
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    // Day picker
                    dayPicker

                    // Main score + day rating
                    if let forecast, let solunar {
                        scoreCard(forecast, solunar: solunar)
                    } else {
                        ProgressView()
                            .frame(height: 120)
                    }

                    // Hourly chart
                    if let forecast, !forecast.hourlyScores.isEmpty {
                        hourlyChart(forecast)
                    }

                    // Solunar feeding windows
                    if let solunar {
                        solunarCard(solunar)
                    }

                    // Tide chart
                    if let tideDay {
                        tideCard(tideDay)
                    }

                    // Sun times
                    if let solunar {
                        sunTimesCard(solunar)
                    }

                    // Breakdown
                    if let forecast {
                        breakdownCard(forecast)
                    }

                    // Species picker
                    speciesPicker
                }
                .padding()
            }
            .navigationTitle("Forecast")
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                recompute()
            }
            .onChange(of: selectedDay) { _, _ in recompute() }
        }
    }

    // MARK: - Day Picker

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                    Button {
                        selectedDay = offset
                    } label: {
                        VStack(spacing: 4) {
                            Text(offset == 0 ? "Today" : dayLabel(date))
                                .font(.caption.bold())
                            Text(date, format: .dateTime.day())
                                .font(.title3.bold())
                                .monospacedDigit()
                        }
                        .frame(width: 60)
                        .padding(.vertical, 8)
                        .background(selectedDay == offset ? Color.blue : Color.clear)
                        .foregroundStyle(selectedDay == offset ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.3))
                        )
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    // MARK: - Score Card

    private func scoreCard(_ forecast: ForecastEngine.ForecastResult, solunar: SolunarEngine.SolunarDay) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                ScoreGauge(score: forecast.score, label: "Bite Score")
                    .scaleEffect(1.4)
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 8) {
                    // Day rating badge
                    HStack {
                        Image(systemName: ratingIcon(solunar.dayRating))
                            .foregroundStyle(ratingColor(solunar.dayRating))
                        Text(solunar.dayRating.label)
                            .font(.headline)
                            .foregroundStyle(ratingColor(solunar.dayRating))
                        Text("Day")
                            .font(.headline)
                    }

                    // Best hours
                    if !forecast.bestHours.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Best: " + forecast.bestHours.map { formatHour($0) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Moon
                    HStack(spacing: 4) {
                        Image(systemName: solunar.moonPhase.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(solunar.moonPhase.displayName)
                            .font(.caption)
                        Text("(\(Int(solunar.moonIllumination * 100))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Top reasons
            VStack(alignment: .leading, spacing: 4) {
                ForEach(forecast.reasons.prefix(4), id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }

    // MARK: - Hourly Chart

    private func hourlyChart(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hourly Forecast")
                .font(.headline)

            Chart(forecast.hourlyScores, id: \.hour) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(barColor(score: point.score))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(formatHour(hour))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .glassCard()
    }

    // MARK: - Solunar Card

    private func solunarCard(_ solunar: SolunarEngine.SolunarDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Solunar Periods")
                    .font(.headline)
                Spacer()
                Image(systemName: solunar.moonPhase.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
            }

            ForEach(solunar.majorPeriods, id: \.peak) { window in
                feedingRow(window, isMajor: true)
            }
            ForEach(solunar.minorPeriods, id: \.peak) { window in
                feedingRow(window, isMajor: false)
            }
        }
        .glassCard()
    }

    private func feedingRow(_ window: SolunarEngine.FeedingWindow, isMajor: Bool) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMajor ? Color.orange : Color.blue)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.kind.rawValue)
                    .font(.subheadline.bold())
                Text("\(window.start, style: .time) – \(window.end, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isMajor ? "MAJOR" : "MINOR")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isMajor ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                .foregroundStyle(isMajor ? .orange : .blue)
                .clipShape(Capsule())
        }
    }

    // MARK: - Tide Card

    private func tideCard(_ tide: TideEngine.TideDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tides")
                .font(.headline)

            // Tide curve chart
            Chart(tide.points, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Height", point.height)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.cyan.gradient)

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Height", point.height)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.cyan.opacity(0.15).gradient)
            }
            .chartYScale(domain: -1.2...1.2)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)

            // High and low tide times
            HStack(spacing: 16) {
                ForEach(tide.highTides) { event in
                    Label("\(event.time, style: .time)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
                ForEach(tide.lowTides) { event in
                    Label("\(event.time, style: .time)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Sun Times Card

    private func sunTimesCard(_ solunar: SolunarEngine.SolunarDay) -> some View {
        HStack {
            VStack(spacing: 4) {
                Image(systemName: "sunrise.fill")
                    .font(.title3)
                    .symbolRenderingMode(.multicolor)
                Text(solunar.sunrise, style: .time)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text("Sunrise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text("Golden Hours")
                    .font(.subheadline.bold())
                Text("\(solunar.dawnGoldenHour.lowerBound, style: .time)–\(solunar.dawnGoldenHour.upperBound, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "sunset.fill")
                    .font(.title3)
                    .symbolRenderingMode(.multicolor)
                Text(solunar.sunset, style: .time)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text("Sunset")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .glassCard()
    }

    // MARK: - Breakdown Card

    private func breakdownCard(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score Breakdown")
                .font(.headline)

            BreakdownRow(label: "Pressure", value: forecast.breakdown.pressure)
            BreakdownRow(label: "Pressure Trend", value: forecast.breakdown.pressureTrend)
            BreakdownRow(label: "Tide", value: forecast.breakdown.tide)
            BreakdownRow(label: "Moon Phase", value: forecast.breakdown.moon)
            BreakdownRow(label: "Solunar Window", value: forecast.breakdown.solunar)
            BreakdownRow(label: "Time of Day", value: forecast.breakdown.timeOfDay)
            BreakdownRow(label: "Wind", value: forecast.breakdown.wind)
            BreakdownRow(label: "Temperature", value: forecast.breakdown.temperature)
            BreakdownRow(label: "Season/Spawn", value: forecast.breakdown.season)
        }
        .glassCard()
    }

    // MARK: - Species Picker

    private var speciesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Species")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button {
                        selectedSpecies = nil
                        recompute()
                    } label: {
                        Text("General")
                            .glassPill()
                    }
                    .tint(selectedSpecies == nil ? .blue : .secondary)

                    ForEach(allSpecies.prefix(20)) { species in
                        Button {
                            selectedSpecies = species
                            recompute()
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

    // MARK: - Helpers

    private func recompute() {
        let coord = coordinate
        let date = forecastDate

        solunar = SolunarEngine.compute(date: date, coordinate: coord)
        tideDay = TideEngine.predict(date: date, coordinate: coord)

        forecast = ForecastEngine.forecast(
            date: date,
            coordinate: coord,
            currentPressureHpa: nil,
            pressureChange6h: nil,
            waterTempC: nil,
            windSpeedKmh: nil,
            windDirection: nil,
            species: selectedSpecies,
            isInSpawningZone: false
        )
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "a" : "p"
        return "\(h)\(ampm)"
    }

    private func barColor(score: Int) -> Color {
        switch score {
        case 0..<25: return .red.opacity(0.7)
        case 25..<50: return .orange.opacity(0.7)
        case 50..<75: return .yellow.opacity(0.7)
        default: return .green.opacity(0.8)
        }
    }

    private func ratingIcon(_ rating: SolunarEngine.DayRating) -> String {
        switch rating {
        case .poor: "star"
        case .fair: "star.leadinghalf.filled"
        case .good: "star.fill"
        case .best: "sparkles"
        }
    }

    private func ratingColor(_ rating: SolunarEngine.DayRating) -> Color {
        switch rating {
        case .poor: .red
        case .fair: .orange
        case .good: .green
        case .best: .yellow
        }
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
